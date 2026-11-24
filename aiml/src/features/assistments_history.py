"""Leakage-safe point-in-time features for ASSISTments interactions."""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd


TARGET_COLUMN = "correct"
GROUP_COLUMN = "user_id"
ORDER_COLUMN = "order_id"
MISSING_SKILL = "__missing_skill__"

NUMERIC_FEATURES = (
    "learner_prior_interactions",
    "learner_prior_success_rate",
    "learner_prior_hint_interaction_rate",
    "learner_prior_mean_attempts",
    "learner_prior_mean_response_ms",
    "skill_prior_interactions",
    "skill_prior_success_rate",
    "skill_prior_hint_interaction_rate",
    "skill_prior_mean_attempts",
    "skill_prior_mean_response_ms",
    "original",
    "position",
    "hint_total",
)

CATEGORICAL_FEATURES = (
    "skill_id",
    "tutor_mode",
    "answer_type",
)

FEATURE_COLUMNS = NUMERIC_FEATURES + CATEGORICAL_FEATURES


def _prior_sum(values: pd.Series, groupers: list[pd.Series]) -> pd.Series:
    filled = values.fillna(0.0).astype(float)
    return filled.groupby(groupers, sort=False).cumsum() - filled


def _prior_valid_count(values: pd.Series, groupers: list[pd.Series]) -> pd.Series:
    valid = values.notna().astype("int64")
    return valid.groupby(groupers, sort=False).cumsum() - valid


def _prior_mean(values: pd.Series, groupers: list[pd.Series]) -> pd.Series:
    total = _prior_sum(values, groupers)
    count = _prior_valid_count(values, groupers)
    return total.div(count.replace(0, np.nan)).fillna(0.0)


def build_point_in_time_examples(
    data: pd.DataFrame,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Build features using only interactions strictly before each target row.

    Current-row attempts, hints, response time, answer text and correctness are
    never included as predictors. Learner and question identifiers remain
    metadata for ordering/grouped evaluation only.
    """

    required = {
        GROUP_COLUMN,
        ORDER_COLUMN,
        TARGET_COLUMN,
        "skill_id",
        "attempt_count",
        "ms_first_response",
        "hint_count",
        "tutor_mode",
        "answer_type",
        "original",
        "position",
        "hint_total",
    }
    missing = sorted(required - set(data.columns))
    if missing:
        raise ValueError("feature input is missing columns: " + ", ".join(missing))

    work = data.sort_values([GROUP_COLUMN, ORDER_COLUMN], kind="stable").copy()
    work["skill_id"] = work["skill_id"].fillna(MISSING_SKILL).astype(str)
    work["tutor_mode"] = work["tutor_mode"].fillna("__missing__").astype(str)
    work["answer_type"] = work["answer_type"].fillna("__missing__").astype(str)

    raw_attempts = pd.to_numeric(work["attempt_count"], errors="coerce")
    raw_response = pd.to_numeric(work["ms_first_response"], errors="coerce")
    raw_hints = pd.to_numeric(work["hint_count"], errors="coerce")

    safe_attempts = raw_attempts.where(raw_attempts >= 1).clip(upper=50)
    safe_response = raw_response.where(raw_response >= 0).clip(upper=3_600_000)
    safe_hint_indicator = raw_hints.where(raw_hints >= 0).gt(0).astype(float)
    safe_hint_indicator = safe_hint_indicator.where(raw_hints.notna())

    learner_group = [work[GROUP_COLUMN]]
    skill_group = [work[GROUP_COLUMN], work["skill_id"]]
    target = work[TARGET_COLUMN].astype(float)

    learner_prior_count = work.groupby(GROUP_COLUMN, sort=False).cumcount()
    learner_prior_correct = _prior_sum(target, learner_group)
    skill_prior_count = work.groupby([GROUP_COLUMN, "skill_id"], sort=False).cumcount()
    skill_prior_correct = _prior_sum(target, skill_group)

    examples = pd.DataFrame(index=work.index)
    examples["learner_prior_interactions"] = learner_prior_count.astype(float)
    examples["learner_prior_success_rate"] = (learner_prior_correct + 1.0) / (
        learner_prior_count + 2.0
    )
    examples["learner_prior_hint_interaction_rate"] = _prior_mean(
        safe_hint_indicator, learner_group
    )
    examples["learner_prior_mean_attempts"] = _prior_mean(safe_attempts, learner_group)
    examples["learner_prior_mean_response_ms"] = _prior_mean(
        safe_response, learner_group
    )
    examples["skill_prior_interactions"] = skill_prior_count.astype(float)
    examples["skill_prior_success_rate"] = (skill_prior_correct + 1.0) / (
        skill_prior_count + 2.0
    )
    examples["skill_prior_hint_interaction_rate"] = _prior_mean(
        safe_hint_indicator, skill_group
    )
    examples["skill_prior_mean_attempts"] = _prior_mean(safe_attempts, skill_group)
    examples["skill_prior_mean_response_ms"] = _prior_mean(safe_response, skill_group)
    examples["original"] = pd.to_numeric(work["original"], errors="coerce")
    examples["position"] = pd.to_numeric(work["position"], errors="coerce")
    examples["hint_total"] = pd.to_numeric(work["hint_total"], errors="coerce")
    examples["skill_id"] = work["skill_id"]
    examples["tutor_mode"] = work["tutor_mode"]
    examples["answer_type"] = work["answer_type"]
    examples[GROUP_COLUMN] = work[GROUP_COLUMN].values
    examples[ORDER_COLUMN] = work[ORDER_COLUMN].values
    examples[TARGET_COLUMN] = work[TARGET_COLUMN].astype("int8").values
    examples = examples.reset_index(drop=True)

    sanitization = {
        "rows_excluded": 0,
        "attempt_count_below_one_treated_missing": int((raw_attempts < 1).sum()),
        "attempt_count_above_50_capped": int((raw_attempts > 50).sum()),
        "negative_response_time_treated_missing": int((raw_response < 0).sum()),
        "response_time_above_one_hour_capped": int((raw_response > 3_600_000).sum()),
        "missing_skill_mapped_to_explicit_category": int(
            (work["skill_id"] == MISSING_SKILL).sum()
        ),
        "notes": [
            "No row is removed solely because skill metadata is missing.",
            "Sanitized current interaction fields are used only in later rows' history aggregates.",
            "Current attempts, hints and response time are excluded from the current prediction.",
        ],
    }
    return examples, sanitization
