"""Isolated inference for the public-dataset educational ML experiment.

Only a trusted, locally configured joblib artifact is loaded. The prediction
is an experimental first-attempt correctness estimate and is never converted
into a Resonant learning action.
"""

from __future__ import annotations

from functools import lru_cache
import math
import os
from pathlib import Path
from typing import Any, Mapping

import joblib
import pandas as pd


ARTIFACT_ENV = "RESONANT_EDUCATIONAL_ML_ARTIFACT"
DEFAULT_ARTIFACT_PATH = (
    Path(__file__).resolve().parent.parent
    / "aiml"
    / "artifacts"
    / "assistments_2009_rf_v1.joblib"
)

FEATURE_COLUMNS = (
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
    "skill_id",
    "tutor_mode",
    "answer_type",
)


class EducationalMLUnavailable(RuntimeError):
    """Raised when the configured local model artifact cannot be used."""


class EducationalMLInvalidArtifact(EducationalMLUnavailable):
    """Raised when a local artifact does not satisfy the trusted contract."""


class EducationalMLInputError(ValueError):
    """Raised when direct service use bypasses API request validation."""


def configured_artifact_path() -> Path:
    configured = os.getenv(ARTIFACT_ENV)
    return Path(configured) if configured else DEFAULT_ARTIFACT_PATH


def _validate_artifact(artifact: object) -> dict[str, Any]:
    if not isinstance(artifact, dict):
        raise EducationalMLInvalidArtifact("Educational ML artifact is not a mapping.")
    required = {
        "artifact_format_version",
        "pipeline",
        "feature_columns",
        "model_version",
        "experiment_id",
        "dataset_id",
        "prediction_target",
    }
    missing = sorted(required - set(artifact))
    if missing:
        raise EducationalMLInvalidArtifact(
            "Educational ML artifact is missing fields: " + ", ".join(missing)
        )
    if artifact["artifact_format_version"] != 1:
        raise EducationalMLInvalidArtifact(
            "Unsupported educational ML artifact version."
        )
    if tuple(artifact["feature_columns"]) != FEATURE_COLUMNS:
        raise EducationalMLInvalidArtifact("Educational ML feature schema mismatch.")
    pipeline = artifact["pipeline"]
    if not callable(getattr(pipeline, "predict", None)) or not callable(
        getattr(pipeline, "predict_proba", None)
    ):
        raise EducationalMLInvalidArtifact(
            "Educational ML artifact does not provide probabilistic prediction."
        )
    named_steps = getattr(pipeline, "named_steps", {})
    estimator = named_steps.get("model") if hasattr(named_steps, "get") else None
    if estimator is not None and hasattr(estimator, "n_jobs"):
        # FastAPI runs synchronous endpoints in a worker thread. Avoid nested
        # joblib parallelism there; fitted tree predictions are unchanged.
        estimator.n_jobs = 1
    for field in ("model_version", "experiment_id", "dataset_id", "prediction_target"):
        if not isinstance(artifact[field], str) or not artifact[field].strip():
            raise EducationalMLInvalidArtifact(
                f"Educational ML artifact has invalid {field}."
            )
    return artifact


@lru_cache(maxsize=4)
def _load_artifact_cached(
    resolved_path: str,
    modified_time_ns: int,
    file_size: int,
) -> dict[str, Any]:
    del modified_time_ns, file_size
    try:
        artifact = joblib.load(resolved_path)
    except Exception as error:
        raise EducationalMLInvalidArtifact(
            "Configured educational ML artifact could not be loaded."
        ) from error
    return _validate_artifact(artifact)


def load_educational_ml_artifact(path: Path | None = None) -> dict[str, Any]:
    target = Path(path) if path is not None else configured_artifact_path()
    try:
        resolved = target.resolve(strict=True)
        stat = resolved.stat()
    except (FileNotFoundError, OSError) as error:
        raise EducationalMLUnavailable(
            "Experimental educational model is unavailable; train the documented artifact first."
        ) from error
    if not resolved.is_file():
        raise EducationalMLUnavailable(
            "Experimental educational model is unavailable; configured path is not a file."
        )
    return _load_artifact_cached(str(resolved), stat.st_mtime_ns, stat.st_size)


def _validated_features(values: Mapping[str, Any]) -> pd.DataFrame:
    received = set(values)
    expected = set(FEATURE_COLUMNS)
    missing = sorted(expected - received)
    unexpected = sorted(received - expected)
    if missing or unexpected:
        details = []
        if missing:
            details.append("missing: " + ", ".join(missing))
        if unexpected:
            details.append("unexpected: " + ", ".join(unexpected))
        raise EducationalMLInputError(
            "Invalid educational ML features (" + "; ".join(details) + ")."
        )

    numeric_columns = FEATURE_COLUMNS[:13]
    row = dict(values)
    for column in numeric_columns:
        value = row[column]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise EducationalMLInputError(f"{column} must be numeric.")
        if not math.isfinite(float(value)):
            raise EducationalMLInputError(f"{column} must be finite.")
    for column in FEATURE_COLUMNS[13:]:
        value = row[column]
        if not isinstance(value, str) or not value.strip() or len(value) > 64:
            raise EducationalMLInputError(
                f"{column} must be a non-empty string no longer than 64 characters."
            )
        row[column] = value.strip()
    return pd.DataFrame([row], columns=FEATURE_COLUMNS)


def predict_educational_outcome(
    values: Mapping[str, Any],
    *,
    artifact_path: Path | None = None,
) -> dict[str, Any]:
    artifact = load_educational_ml_artifact(artifact_path)
    features = _validated_features(values)
    pipeline = artifact["pipeline"]
    try:
        prediction = int(pipeline.predict(features)[0])
        probability = float(pipeline.predict_proba(features)[0, 1])
    except Exception as error:
        raise EducationalMLInvalidArtifact(
            "Configured educational ML artifact failed during prediction."
        ) from error
    if (
        prediction not in {0, 1}
        or not math.isfinite(probability)
        or not 0 <= probability <= 1
    ):
        raise EducationalMLInvalidArtifact(
            "Configured educational ML artifact returned an invalid prediction."
        )
    return {
        "prediction": prediction,
        "probability_correct": probability,
        "model_version": artifact["model_version"],
        "experiment_id": artifact["experiment_id"],
        "dataset_id": artifact["dataset_id"],
        "prediction_target": artifact["prediction_target"],
        "experimental": True,
        "learning_action": None,
        "scope": (
            "Experimental educational outcome estimate; not a Braille mastery "
            "score or a Resonant learning action."
        ),
    }
