import sys
from pathlib import Path

import joblib
import pandas as pd
import pytest
from sklearn.dummy import DummyClassifier

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from educational_ml_service import (  # noqa: E402
    FEATURE_COLUMNS,
    EducationalMLInputError,
    EducationalMLInvalidArtifact,
    EducationalMLUnavailable,
    load_educational_ml_artifact,
    predict_educational_outcome,
)


def _request():
    return {
        "learner_prior_interactions": 8,
        "learner_prior_success_rate": 0.625,
        "learner_prior_hint_interaction_rate": 0.25,
        "learner_prior_mean_attempts": 1.5,
        "learner_prior_mean_response_ms": 1450.0,
        "skill_prior_interactions": 3,
        "skill_prior_success_rate": 0.6,
        "skill_prior_hint_interaction_rate": 1 / 3,
        "skill_prior_mean_attempts": 2.0,
        "skill_prior_mean_response_ms": 1600.0,
        "original": 1,
        "position": 17,
        "hint_total": 4,
        "skill_id": "7.0",
        "tutor_mode": "tutor",
        "answer_type": "algebra",
    }


def _write_artifact(path):
    rows = pd.DataFrame([_request(), _request()], columns=FEATURE_COLUMNS)
    model = DummyClassifier(strategy="prior").fit(rows, [0, 1])
    joblib.dump(
        {
            "artifact_format_version": 1,
            "pipeline": model,
            "feature_columns": list(FEATURE_COLUMNS),
            "model_version": "test-model-v1",
            "experiment_id": "test-experiment-v1",
            "dataset_id": "test-public-dataset",
            "prediction_target": "first-attempt answer correctness (correct=1)",
        },
        path,
    )


def test_trusted_artifact_loads_and_returns_experimental_probability(tmp_path):
    artifact_path = tmp_path / "model.joblib"
    _write_artifact(artifact_path)
    result = predict_educational_outcome(_request(), artifact_path=artifact_path)
    assert result["prediction"] in {0, 1}
    assert 0 <= result["probability_correct"] <= 1
    assert result["model_version"] == "test-model-v1"
    assert result["experimental"] is True
    assert result["learning_action"] is None
    assert "not a Braille mastery" in result["scope"]


def test_missing_and_invalid_artifacts_fail_closed(tmp_path):
    with pytest.raises(EducationalMLUnavailable, match="unavailable"):
        load_educational_ml_artifact(tmp_path / "missing.joblib")

    invalid_path = tmp_path / "invalid.joblib"
    joblib.dump({"pipeline": object()}, invalid_path)
    with pytest.raises(EducationalMLInvalidArtifact, match="missing fields"):
        load_educational_ml_artifact(invalid_path)


def test_direct_service_rejects_schema_drift(tmp_path):
    artifact_path = tmp_path / "model.joblib"
    _write_artifact(artifact_path)
    request = _request()
    request.pop("skill_id")
    with pytest.raises(EducationalMLInputError, match="missing: skill_id"):
        predict_educational_outcome(request, artifact_path=artifact_path)
