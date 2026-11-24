"""Point-in-time features for Resonant future-attempt error prediction.

The feature schema mirrors ``resonant_backend.resonant_ml_service`` version 2.
Only information available before the target attempt is aggregated. Learner
and submission identifiers remain split/trace metadata and never model inputs.
"""

from __future__ import annotations

import hashlib
import math

import pandas as pd

from data.contracts import validate_no_group_overlap, validate_practice_events


FEATURE_SCHEMA_VERSION = "resonant-next-attempt-v2"
FEATURE_COLUMNS = (
    "language",
    "skill_id",
    "question_type",
    "prior_attempt_count",
    "prior_incorrect_count",
    "prior_accuracy_smoothed",
    "prior_recent_accuracy",
    "prior_hint_rate",
    "prior_average_response_seconds",
    "days_since_prior_practice",
    "consecutive_incorrect",
    "missing_dot_rate",
    "extra_dot_rate",
    "revision_count",
    "prior_intervention_success_rate",
    "current_difficulty",
)
METADATA_COLUMNS = ("learner_id", "prediction_time", "target_submission_id")
TARGET_COLUMN = "target_incorrect"


def _rate(numerator: int, denominator: int, default: float = 0.0) -> float:
    return numerator / denominator if denominator else default


def build_next_attempt_examples(events: pd.DataFrame) -> pd.DataFrame:
    """Build future-incorrect examples; the current outcome is label-only."""
    checked = validate_practice_events(events)
    eligible = checked.loc[
        checked["outcome"].isin({"correct", "incorrect"})
        & checked["input_status"].eq("valid")
        & checked["counts_for_learning"]
    ].copy()
    eligible = eligible.sort_values(
        ["learner_id", "skill_id", "created_at", "submission_id"], kind="stable"
    )
    rows: list[dict] = []
    for (learner_id, skill_id), group in eligible.groupby(
        ["learner_id", "skill_id"], sort=False, dropna=False
    ):
        history: list[dict] = []
        for event in group.to_dict("records"):
            if history:
                recent = history[-5:]
                prior_correct = sum(item["outcome"] == "correct" for item in history)
                prior_incorrect = len(history) - prior_correct
                recent_correct = sum(item["outcome"] == "correct" for item in recent)
                gap_seconds = max(
                    0.0,
                    (event["created_at"] - history[-1]["created_at"]).total_seconds(),
                )
                consecutive_incorrect = 0
                for prior in reversed(history):
                    if prior["outcome"] != "incorrect":
                        break
                    consecutive_incorrect += 1
                intervention_events = [
                    item for item in history if item.get("intervention_type")
                ]
                rows.append(
                    {
                        "learner_id": learner_id,
                        "prediction_time": event["created_at"],
                        "target_submission_id": event["submission_id"],
                        "language": event["language"],
                        "skill_id": skill_id,
                        "question_type": event["question_type"],
                        "prior_attempt_count": len(history),
                        "prior_incorrect_count": prior_incorrect,
                        "prior_accuracy_smoothed": (prior_correct + 1)
                        / (len(history) + 2),
                        "prior_recent_accuracy": recent_correct / len(recent),
                        "prior_hint_rate": _rate(
                            sum(bool(item["hint_used"]) for item in history),
                            len(history),
                        ),
                        "prior_average_response_seconds": _rate(
                            sum(item["response_time_ms"] for item in history),
                            len(history),
                        )
                        / 1000.0,
                        "days_since_prior_practice": min(
                            gap_seconds / 86400.0,
                            3650.0,
                        ),
                        "consecutive_incorrect": consecutive_incorrect,
                        "missing_dot_rate": _rate(
                            sum(
                                item.get("error_category") == "missing_dot"
                                for item in history
                            ),
                            len(history),
                        ),
                        "extra_dot_rate": _rate(
                            sum(
                                item.get("error_category") == "extra_dot"
                                for item in history
                            ),
                            len(history),
                        ),
                        "revision_count": sum(
                            item.get("assessment_type") == "revision"
                            or item.get("intervention_type") in {"revise", "revision"}
                            for item in history
                        ),
                        "prior_intervention_success_rate": _rate(
                            sum(
                                item["outcome"] == "correct"
                                for item in intervention_events
                            ),
                            len(intervention_events),
                            default=0.5,
                        ),
                        "current_difficulty": int(event["difficulty"]),
                        "target_incorrect": int(event["outcome"] == "incorrect"),
                    }
                )
            history.append(event)

    columns = [*METADATA_COLUMNS, *FEATURE_COLUMNS, TARGET_COLUMN]
    result = pd.DataFrame(rows, columns=columns)
    if result.empty:
        return result
    if result[list(FEATURE_COLUMNS)].isna().any().any():
        raise RuntimeError("generated mastery features unexpectedly contain missing values")
    if not result[TARGET_COLUMN].isin([0, 1]).all():
        raise RuntimeError("generated targets must be binary observed outcomes")
    numeric = result.loc[:, list(FEATURE_COLUMNS[3:])].astype(float)
    if not numeric.map(math.isfinite).all().all():
        raise RuntimeError("generated mastery features must be finite")
    return result


def chronological_split(
    examples: pd.DataFrame, cutoff: str | pd.Timestamp
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Diagnostic strict forward-time split; learners may occur on both sides."""
    if examples.empty:
        raise ValueError("no eligible history rows exist")
    boundary = pd.to_datetime(cutoff, utc=True, errors="coerce")
    if pd.isna(boundary):
        raise ValueError("cutoff must be a valid timestamp")
    times = pd.to_datetime(examples["prediction_time"], utc=True, errors="coerce")
    if times.isna().any():
        raise ValueError("prediction_time contains invalid timestamps")
    train = examples.loc[times < boundary].copy()
    test = examples.loc[times >= boundary].copy()
    if train.empty or test.empty:
        raise ValueError("chronological cutoff must leave rows in both train and test")
    if train["prediction_time"].max() >= test["prediction_time"].min():
        raise RuntimeError("chronological split is not strictly forward in time")
    return train, test


def grouped_chronological_split(
    examples: pd.DataFrame,
    cutoff: str | pd.Timestamp,
    *,
    seed: int,
    test_fraction: float = 0.2,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Hold out learner identities and evaluate only their post-cutoff rows."""
    before, after = chronological_split(examples, cutoff)
    if not 0 < test_fraction < 1:
        raise ValueError("test_fraction must be between zero and one")
    candidates = sorted(set(after["learner_id"].astype(str)))
    if not candidates:
        raise ValueError("no learner has an eligible post-cutoff example")
    ranked = sorted(
        candidates,
        key=lambda learner: hashlib.sha256(
            f"{seed}|{learner}".encode("utf-8")
        ).hexdigest(),
    )
    test_count = max(1, min(len(ranked), math.ceil(len(ranked) * test_fraction)))
    test_learners = set(ranked[:test_count])
    train = before.loc[~before["learner_id"].astype(str).isin(test_learners)].copy()
    test = after.loc[after["learner_id"].astype(str).isin(test_learners)].copy()
    if train.empty or test.empty:
        raise ValueError("grouped chronological split produced an empty partition")
    validate_no_group_overlap(train, test, "learner_id")
    if train["prediction_time"].max() >= test["prediction_time"].min():
        raise RuntimeError("grouped chronological split is not forward in time")
    return train, test
