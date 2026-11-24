"""Qualification-gated Resonant next-attempt prediction service.

The production task is the probability that the learner's *future* eligible
attempt on a skill will be incorrect.  Features are constructed only from
events before the prediction timestamp.  A missing or unqualified artifact
returns an explicit deterministic cold-start estimate and never a fake model
prediction.
"""

from __future__ import annotations

from datetime import datetime, timezone
import math
import os
from pathlib import Path
from time import perf_counter
from uuid import UUID, uuid4

from psycopg.types.json import Jsonb


ARTIFACT_KIND = "resonant_next_attempt"
FEATURE_SCHEMA_VERSION = "resonant-next-attempt-v2"
PREDICTION_TASK = "probability_of_incorrect_future_attempt"
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
NUMERIC_FEATURES = FEATURE_COLUMNS[3:]
TRUSTED_ARTIFACT_DIRECTORIES = (
    (Path(__file__).resolve().parent.parent / "aiml" / "artifacts").resolve(),
    (Path(__file__).resolve().parent / "artifacts").resolve(),
)
DEFAULT_ARTIFACT_PATH = (
    TRUSTED_ARTIFACT_DIRECTORIES[0] / "resonant_next_attempt_v2.joblib"
)


def _timestamp(value) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    return None


def build_point_in_time_features(
    events: list[dict],
    *,
    language: str,
    skill_id: str,
    question_type: str,
    current_difficulty: int,
    prediction_time: datetime,
) -> dict:
    """Construct bounded features from strictly earlier valid events."""
    if language not in {"English", "Hindi", "Kannada"}:
        raise ValueError("resonant_ml_language_invalid")
    if not skill_id or len(skill_id) > 160:
        raise ValueError("resonant_ml_skill_invalid")
    if not question_type or len(question_type) > 80:
        raise ValueError("resonant_ml_question_type_invalid")
    if not 1 <= int(current_difficulty) <= 5:
        raise ValueError("resonant_ml_difficulty_invalid")
    prediction_time = _timestamp(prediction_time) or datetime.now(timezone.utc)
    eligible: list[dict] = []
    for event in events:
        event_time = _timestamp(event.get("created_at"))
        if event_time is None or event_time >= prediction_time:
            continue
        if event.get("skill_id") != skill_id:
            continue
        if event.get("input_status", "valid") != "valid":
            continue
        if event.get("counts_for_learning", True) is False:
            continue
        if event.get("outcome") not in {"correct", "incorrect"}:
            continue
        eligible.append({**event, "created_at": event_time})
    eligible.sort(key=lambda item: (item["created_at"], str(item.get("submission_id", ""))))

    attempts = len(eligible)
    correct = sum(event["outcome"] == "correct" for event in eligible)
    incorrect = attempts - correct
    recent = eligible[-5:]
    recent_accuracy = (
        sum(event["outcome"] == "correct" for event in recent) / len(recent)
        if recent
        else 0.5
    )
    consecutive_incorrect = 0
    for event in reversed(eligible):
        if event["outcome"] != "incorrect":
            break
        consecutive_incorrect += 1
    hint_rate = (
        sum(bool(event.get("hint_used")) for event in eligible) / attempts
        if attempts
        else 0.0
    )
    average_response_seconds = (
        sum(max(0, int(event.get("response_time_ms") or 0)) for event in eligible)
        / attempts
        / 1000.0
        if attempts
        else 0.0
    )
    days_since = (
        max(0.0, (prediction_time - eligible[-1]["created_at"]).total_seconds() / 86400.0)
        if eligible
        else 0.0
    )
    missing_dot_rate = (
        sum(event.get("error_category") == "missing_dot" for event in eligible) / attempts
        if attempts
        else 0.0
    )
    extra_dot_rate = (
        sum(event.get("error_category") == "extra_dot" for event in eligible) / attempts
        if attempts
        else 0.0
    )
    revision_count = sum(
        event.get("assessment_type") == "revision"
        or event.get("intervention_type") in {"revise", "revision"}
        for event in eligible
    )
    intervention_events = [
        event for event in eligible if event.get("intervention_type")
    ]
    intervention_success = (
        sum(event["outcome"] == "correct" for event in intervention_events)
        / len(intervention_events)
        if intervention_events
        else 0.5
    )
    features = {
        "language": language,
        "skill_id": skill_id,
        "question_type": question_type,
        "prior_attempt_count": attempts,
        "prior_incorrect_count": incorrect,
        "prior_accuracy_smoothed": (correct + 1) / (attempts + 2),
        "prior_recent_accuracy": recent_accuracy,
        "prior_hint_rate": hint_rate,
        "prior_average_response_seconds": average_response_seconds,
        "days_since_prior_practice": min(days_since, 3650.0),
        "consecutive_incorrect": consecutive_incorrect,
        "missing_dot_rate": missing_dot_rate,
        "extra_dot_rate": extra_dot_rate,
        "revision_count": revision_count,
        "prior_intervention_success_rate": intervention_success,
        "current_difficulty": int(current_difficulty),
    }
    validate_feature_snapshot(features)
    return features


def validate_feature_snapshot(features: dict) -> None:
    if tuple(features.keys()) != FEATURE_COLUMNS:
        raise ValueError("resonant_ml_feature_schema_mismatch")
    if features["language"] not in {"English", "Hindi", "Kannada"}:
        raise ValueError("resonant_ml_language_invalid")
    for name in ("skill_id", "question_type"):
        if not isinstance(features[name], str) or not features[name]:
            raise ValueError(f"resonant_ml_{name}_invalid")
    for name in NUMERIC_FEATURES:
        value = features[name]
        if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            raise ValueError(f"resonant_ml_feature_invalid:{name}")
        if float(value) < 0:
            raise ValueError(f"resonant_ml_feature_negative:{name}")
    for name in (
        "prior_accuracy_smoothed",
        "prior_recent_accuracy",
        "prior_hint_rate",
        "missing_dot_rate",
        "extra_dot_rate",
        "prior_intervention_success_rate",
    ):
        if not 0.0 <= float(features[name]) <= 1.0:
            raise ValueError(f"resonant_ml_feature_probability_invalid:{name}")
    if not 1 <= int(features["current_difficulty"]) <= 5:
        raise ValueError("resonant_ml_difficulty_invalid")


def fetch_prior_events(
    connection,
    *,
    learner_id,
    skill_id: str,
    prediction_time: datetime,
) -> list[dict]:
    """Read only eligible event columns; no names, contacts or transcripts."""
    rows = connection.execute(
        """
        SELECT submission_id, skill_id, language, outcome, response_time_ms,
               hint_used, created_at, input_status, TRUE AS counts_for_learning,
               NULL::text AS error_category, NULL::text AS assessment_type,
               intervention_type
        FROM resonant.practice_attempts
        WHERE learner_id = %s AND skill_id = %s AND created_at < %s
        UNION ALL
        SELECT s.submission_id, q.skill_id, s.language,
               CASE WHEN a.correct THEN 'correct' ELSE 'incorrect' END AS outcome,
               a.response_time_ms, a.hint_used, a.created_at, a.input_status,
               a.counts_for_learning, a.error_category, s.assessment_type,
               a.intervention_type
        FROM resonant.assessment_attempts a
        JOIN resonant.assessment_questions q
          ON q.assessment_id = a.assessment_id AND q.question_id = a.question_id
        JOIN resonant.assessment_sessions s
          ON s.assessment_id = a.assessment_id
        WHERE a.learner_id = %s AND q.skill_id = %s AND a.created_at < %s
        ORDER BY created_at, submission_id
        """,
        (
            learner_id,
            skill_id,
            prediction_time,
            learner_id,
            skill_id,
            prediction_time,
        ),
    ).fetchall()
    return [dict(row) for row in rows]


def _artifact_path(configured: str | Path | None = None) -> Path:
    candidate = Path(
        configured
        or os.getenv("RESONANT_ML_ARTIFACT", "")
        or DEFAULT_ARTIFACT_PATH
    ).expanduser().resolve()
    if not any(candidate.is_relative_to(root) for root in TRUSTED_ARTIFACT_DIRECTORIES):
        raise ValueError("resonant_ml_artifact_path_untrusted")
    return candidate


def load_qualified_artifact(
    configured_path: str | Path | None = None,
) -> tuple[dict | None, str]:
    """Load only a reviewed Resonant artifact from a trusted local directory."""
    try:
        path = _artifact_path(configured_path)
    except (OSError, ValueError):
        return None, "artifact_path_invalid"
    if not path.is_file():
        return None, "artifact_missing"
    try:
        import joblib

        payload = joblib.load(path)
    except Exception:
        return None, "artifact_load_failed"
    if not isinstance(payload, dict):
        return None, "artifact_payload_invalid"
    checks = {
        "artifact_kind": payload.get("artifact_kind") == ARTIFACT_KIND,
        "prediction_task": payload.get("prediction_task") == PREDICTION_TASK,
        "feature_schema": payload.get("feature_schema_version") == FEATURE_SCHEMA_VERSION,
        "feature_columns": tuple(payload.get("feature_columns") or ()) == FEATURE_COLUMNS,
        "training_data": payload.get("training_data_kind") == "consented_resonant_events",
        "qualified": payload.get("qualified_for_inference") is True,
        "qualification": (payload.get("qualification") or {}).get("passed") is True,
        "model": callable(getattr(payload.get("model"), "predict_proba", None)),
        "model_version": bool(payload.get("model_version")),
        "incorrect_class": payload.get("incorrect_class_label") == 1,
        "supported_languages": bool(payload.get("supported_languages"))
        and set(payload.get("supported_languages") or []).issubset(
            {"English", "Hindi", "Kannada"}
        ),
    }
    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        return None, "artifact_unqualified:" + ",".join(failed)
    return payload, "qualified"


def predict_future_incorrect(
    features: dict,
    *,
    artifact_path: str | Path | None = None,
) -> dict:
    """Return qualified model output or an explicit deterministic fallback."""
    started = perf_counter()
    validate_feature_snapshot(features)
    payload, artifact_status = load_qualified_artifact(artifact_path)
    fallback_probability = 1.0 - float(features["prior_accuracy_smoothed"])
    prediction_id = uuid4()
    if payload is None:
        return {
            "prediction_id": prediction_id,
            "prediction_task": PREDICTION_TASK,
            "probability_incorrect": round(fallback_probability, 6),
            "prediction_source": "cold_start_deterministic",
            "validity_status": "fallback",
            "model_version": None,
            "feature_schema_version": FEATURE_SCHEMA_VERSION,
            "feature_snapshot": features,
            "fallback_reason": artifact_status,
            "supported_languages": [],
            "uncertainty": None,
            "uncertainty_method": "not_estimated",
            "prediction_latency_ms": max(0, round((perf_counter() - started) * 1000)),
            "predicted_at": datetime.now(timezone.utc),
        }

    supported_languages = payload.get("supported_languages") or []
    if features["language"] not in supported_languages:
        return {
            "prediction_id": prediction_id,
            "prediction_task": PREDICTION_TASK,
            "probability_incorrect": round(fallback_probability, 6),
            "prediction_source": "cold_start_deterministic",
            "validity_status": "fallback",
            "model_version": None,
            "feature_schema_version": FEATURE_SCHEMA_VERSION,
            "feature_snapshot": features,
            "fallback_reason": "language_not_qualified",
            "supported_languages": list(supported_languages),
            "uncertainty": None,
            "uncertainty_method": "not_estimated",
            "prediction_latency_ms": max(0, round((perf_counter() - started) * 1000)),
            "predicted_at": datetime.now(timezone.utc),
        }
    try:
        import pandas as pd

        frame = pd.DataFrame([{name: features[name] for name in FEATURE_COLUMNS}])
        probabilities = payload["model"].predict_proba(frame)[0]
        classes = list(getattr(payload["model"], "classes_", [0, 1]))
        incorrect_label = payload.get("incorrect_class_label", 1)
        index = classes.index(incorrect_label)
        probability = float(probabilities[index])
        if not math.isfinite(probability) or not 0.0 <= probability <= 1.0:
            raise ValueError("invalid_probability")
    except Exception:
        return {
            "prediction_id": prediction_id,
            "prediction_task": PREDICTION_TASK,
            "probability_incorrect": round(fallback_probability, 6),
            "prediction_source": "cold_start_deterministic",
            "validity_status": "fallback",
            "model_version": None,
            "feature_schema_version": FEATURE_SCHEMA_VERSION,
            "feature_snapshot": features,
            "fallback_reason": "model_inference_failed",
            "supported_languages": list(supported_languages),
            "uncertainty": None,
            "uncertainty_method": "not_estimated",
            "prediction_latency_ms": max(0, round((perf_counter() - started) * 1000)),
            "predicted_at": datetime.now(timezone.utc),
        }
    return {
        "prediction_id": prediction_id,
        "prediction_task": PREDICTION_TASK,
        "probability_incorrect": round(probability, 6),
        "prediction_source": "qualified_model",
        "validity_status": "valid",
        "model_version": payload["model_version"],
        "feature_schema_version": FEATURE_SCHEMA_VERSION,
        "feature_snapshot": features,
        "fallback_reason": None,
        "supported_languages": list(supported_languages),
        "uncertainty": None,
        "uncertainty_method": "not_estimated",
        "prediction_latency_ms": max(0, round((perf_counter() - started) * 1000)),
        "predicted_at": datetime.now(timezone.utc),
        "model_metadata": {
            "model_type": payload.get("model_type"),
            "training_data_kind": payload.get("training_data_kind"),
            "qualification": payload.get("qualification"),
        },
    }


def build_prediction(
    connection,
    *,
    learner_id,
    skill_id: str,
    language: str,
    question_type: str,
    current_difficulty: int,
    prediction_time: datetime | None = None,
    artifact_path: str | Path | None = None,
) -> dict:
    prediction_time = prediction_time or datetime.now(timezone.utc)
    events = fetch_prior_events(
        connection,
        learner_id=learner_id,
        skill_id=skill_id,
        prediction_time=prediction_time,
    )
    features = build_point_in_time_features(
        events,
        language=language,
        skill_id=skill_id,
        question_type=question_type,
        current_difficulty=current_difficulty,
        prediction_time=prediction_time,
    )
    return predict_future_incorrect(features, artifact_path=artifact_path)


def register_model_metadata(connection, prediction: dict) -> None:
    metadata = prediction.get("model_metadata")
    model_version = prediction.get("model_version")
    if not model_version or not isinstance(metadata, dict):
        return
    qualification = metadata.get("qualification") or {}
    connection.execute(
        """
        INSERT INTO resonant.ml_model_versions (
            model_version, prediction_task, artifact_kind,
            feature_schema_version, training_data_kind, supported_languages,
            qualified_for_inference, qualification, evaluation_metrics,
            dataset_provenance, trained_at
        ) VALUES (%s, %s, %s, %s, %s, %s, TRUE, %s, %s, %s, %s)
        ON CONFLICT (model_version) DO UPDATE SET
            qualification = EXCLUDED.qualification,
            evaluation_metrics = EXCLUDED.evaluation_metrics,
            qualified_for_inference = EXCLUDED.qualified_for_inference
        """,
        (
            model_version,
            PREDICTION_TASK,
            ARTIFACT_KIND,
            FEATURE_SCHEMA_VERSION,
            metadata.get("training_data_kind", "consented_resonant_events"),
            prediction.get("supported_languages") or [],
            Jsonb(qualification),
            Jsonb(metadata.get("evaluation_metrics") or {}),
            Jsonb(metadata.get("dataset_provenance") or {}),
            metadata.get("trained_at"),
        ),
    )


def persist_prediction(connection, *, learner_id, skill_id: str, language: str, prediction: dict) -> None:
    register_model_metadata(connection, prediction)
    connection.execute(
        """
        INSERT INTO resonant.ml_predictions (
            prediction_id, learner_id, skill_id, language, prediction_task,
            probability_incorrect, prediction_source, validity_status,
            model_version, feature_schema_version, feature_snapshot,
            fallback_reason, prediction_latency_ms, predicted_at
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            prediction["prediction_id"],
            learner_id,
            skill_id,
            language,
            prediction["prediction_task"],
            prediction["probability_incorrect"],
            prediction["prediction_source"],
            prediction["validity_status"],
            prediction["model_version"],
            prediction["feature_schema_version"],
            Jsonb(prediction["feature_snapshot"]),
            prediction["fallback_reason"],
            prediction["prediction_latency_ms"],
            prediction["predicted_at"],
        ),
    )


def resolve_previous_prediction(
    connection,
    *,
    learner_id,
    skill_id: str,
    submission_id: UUID,
    observed_incorrect: bool,
    observed_at: datetime | None = None,
) -> None:
    """Link the newest unresolved earlier prediction to its observed outcome."""
    connection.execute(
        """
        WITH selected AS (
            SELECT prediction_id
            FROM resonant.ml_predictions
            WHERE learner_id = %s AND skill_id = %s AND resolved_at IS NULL
              AND predicted_at < %s
            ORDER BY predicted_at DESC
            LIMIT 1
            FOR UPDATE SKIP LOCKED
        )
        UPDATE resonant.ml_predictions p
        SET linked_submission_id = %s,
            observed_incorrect = %s,
            resolved_at = %s
        FROM selected
        WHERE p.prediction_id = selected.prediction_id
        """,
        (
            learner_id,
            skill_id,
            observed_at or datetime.now(timezone.utc),
            submission_id,
            observed_incorrect,
            observed_at or datetime.now(timezone.utc),
        ),
    )


def hybridize_decision(base_decision: dict, prediction: dict, *, current_difficulty: int) -> dict:
    """Let qualified risk modify conservatism, never prerequisite/mastery truth."""
    decision = {**base_decision, "evidence": dict(base_decision.get("evidence") or {})}
    probability = float(prediction["probability_incorrect"])
    low_risk = float(os.getenv("RESONANT_ML_LOW_RISK_THRESHOLD", "0.25"))
    high_risk = float(os.getenv("RESONANT_ML_HIGH_RISK_THRESHOLD", "0.55"))
    if not 0.0 <= low_risk < high_risk <= 1.0:
        low_risk, high_risk = 0.25, 0.55
    qualified = prediction["prediction_source"] == "qualified_model"
    difficulty_after = int(base_decision.get("difficulty_after", current_difficulty))
    if qualified and probability >= high_risk:
        difficulty_after = max(1, current_difficulty - 1)
        if decision["action"] == "advance":
            decision["action"] = "reinforce"
            decision["reason"] = (
                "Observed assessment evidence permits progress, but a qualified "
                "Resonant model indicates elevated risk on the next attempt. "
                "A different validated exercise will reinforce the skill before advancement."
            )
    elif qualified and probability <= low_risk and decision["action"] == "advance":
        difficulty_after = min(5, current_difficulty + 1)
        decision["reason"] += (
            " A qualified Resonant model also indicates low near-term error risk, "
            "so the next validated exercise may increase by one difficulty level."
        )
    elif qualified:
        # The qualified model is advisory; retain the bounded outcome-based
        # policy unless its risk threshold justifies a one-step adjustment.
        difficulty_after = int(base_decision.get("difficulty_after", current_difficulty))

    decision_method = "hybrid_ml_rules" if qualified else "deterministic_rules"
    decision["decision_method"] = decision_method
    decision["prediction_id"] = prediction["prediction_id"]
    decision["model_probability_incorrect"] = probability if qualified else None
    decision["model_version"] = prediction["model_version"]
    decision["difficulty_before"] = current_difficulty
    decision["difficulty_after"] = difficulty_after
    decision["fallback_used"] = not qualified
    decision["evidence"].update(
        {
            "decision_method": decision_method,
            "model_status": (
                "qualified_prediction_used" if qualified else "cold_start_fallback"
            ),
            "prediction_source": prediction["prediction_source"],
            "prediction_validity_status": prediction["validity_status"],
            "model_version": prediction["model_version"],
            "feature_schema_version": prediction["feature_schema_version"],
            "fallback_reason": prediction["fallback_reason"],
            "difficulty_before": current_difficulty,
            "difficulty_after": difficulty_after,
            # Keep technical probability out of learner-facing copy; it remains
            # available for audited teacher/model evaluation only.
            "probability_incorrect": probability if qualified else None,
        }
    )
    return decision


def model_status() -> dict:
    payload, status = load_qualified_artifact()
    return {
        "mode": "qualified_model" if payload is not None else "cold_start",
        "artifact_status": status,
        "prediction_task": PREDICTION_TASK,
        "feature_schema_version": FEATURE_SCHEMA_VERSION,
        "model_version": payload.get("model_version") if payload else None,
        "supported_languages": payload.get("supported_languages", []) if payload else [],
        "assistance_only": True,
        "deterministic_controller_authoritative": True,
    }

