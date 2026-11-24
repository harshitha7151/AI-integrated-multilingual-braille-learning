import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault(
    "RESONANT_JWT_SECRET",
    "resonant-test-only-jwt-secret-never-use-in-production",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import joblib

import resonant_ml_service as service


class FixedRiskModel:
    classes_ = [0, 1]

    def __init__(self, probability_incorrect=0.7):
        self.probability_incorrect = probability_incorrect

    def predict_proba(self, frame):
        return [
            [1.0 - self.probability_incorrect, self.probability_incorrect]
            for _ in range(len(frame))
        ]


def features(**overrides):
    values = {
        "language": "English",
        "skill_id": "english-letter-a",
        "question_type": "letter_recognition",
        "prior_attempt_count": 2,
        "prior_incorrect_count": 1,
        "prior_accuracy_smoothed": 0.5,
        "prior_recent_accuracy": 0.5,
        "prior_hint_rate": 0.0,
        "prior_average_response_seconds": 1.2,
        "days_since_prior_practice": 1.0,
        "consecutive_incorrect": 1,
        "missing_dot_rate": 0.5,
        "extra_dot_rate": 0.0,
        "revision_count": 0,
        "prior_intervention_success_rate": 0.5,
        "current_difficulty": 2,
    }
    values.update(overrides)
    return values


class ResonantFeatureTests(unittest.TestCase):
    def test_point_in_time_features_ignore_current_future_and_technical_events(self):
        now = datetime(2026, 11, 22, tzinfo=timezone.utc)
        events = [
            {
                "submission_id": "one",
                "skill_id": "english-letter-a",
                "outcome": "incorrect",
                "response_time_ms": 1200,
                "hint_used": True,
                "error_category": "missing_dot",
                "created_at": now - timedelta(days=2),
                "input_status": "valid",
            },
            {
                "submission_id": "technical",
                "skill_id": "english-letter-a",
                "outcome": "incorrect",
                "response_time_ms": 0,
                "hint_used": False,
                "created_at": now - timedelta(days=1),
                "input_status": "technical_failure",
            },
            {
                "submission_id": "target",
                "skill_id": "english-letter-a",
                "outcome": "correct",
                "response_time_ms": 500,
                "hint_used": False,
                "created_at": now,
                "input_status": "valid",
            },
            {
                "submission_id": "future",
                "skill_id": "english-letter-a",
                "outcome": "correct",
                "response_time_ms": 500,
                "hint_used": False,
                "created_at": now + timedelta(seconds=1),
                "input_status": "valid",
            },
        ]
        result = service.build_point_in_time_features(
            events,
            language="English",
            skill_id="english-letter-a",
            question_type="letter_recognition",
            current_difficulty=2,
            prediction_time=now,
        )
        self.assertEqual(result["prior_attempt_count"], 1)
        self.assertEqual(result["prior_incorrect_count"], 1)
        self.assertEqual(result["missing_dot_rate"], 1.0)
        self.assertEqual(result["consecutive_incorrect"], 1)

    def test_exact_feature_contract_rejects_missing_or_reordered_data(self):
        invalid = features()
        invalid.pop("skill_id")
        with self.assertRaisesRegex(ValueError, "schema_mismatch"):
            service.validate_feature_snapshot(invalid)


class ResonantModelTests(unittest.TestCase):
    def _artifact(self, directory: Path, **overrides) -> Path:
        payload = {
            "artifact_kind": service.ARTIFACT_KIND,
            "prediction_task": service.PREDICTION_TASK,
            "feature_schema_version": service.FEATURE_SCHEMA_VERSION,
            "feature_columns": list(service.FEATURE_COLUMNS),
            "training_data_kind": "consented_resonant_events",
            "qualified_for_inference": True,
            "qualification": {"passed": True},
            "model": FixedRiskModel(),
            "model_version": "resonant-risk-test-v1",
            "model_type": "test fixture",
            "supported_languages": ["English"],
            "incorrect_class_label": 1,
        }
        payload.update(overrides)
        path = directory / "resonant_next_attempt_v2.joblib"
        joblib.dump(payload, path)
        return path

    def test_missing_model_is_explicit_cold_start_not_fake_ml(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            with patch.object(service, "TRUSTED_ARTIFACT_DIRECTORIES", (root,)):
                result = service.predict_future_incorrect(
                    features(),
                    artifact_path=root / "missing.joblib",
                )
        self.assertEqual(result["prediction_source"], "cold_start_deterministic")
        self.assertEqual(result["validity_status"], "fallback")
        self.assertEqual(result["fallback_reason"], "artifact_missing")
        self.assertIsNone(result["model_version"])

    def test_only_qualified_resonant_artifact_produces_model_prediction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            path = self._artifact(root)
            with patch.object(service, "TRUSTED_ARTIFACT_DIRECTORIES", (root,)):
                result = service.predict_future_incorrect(features(), artifact_path=path)
        self.assertEqual(result["prediction_source"], "qualified_model")
        self.assertAlmostEqual(result["probability_incorrect"], 0.7)
        self.assertEqual(result["model_version"], "resonant-risk-test-v1")

    def test_unqualified_or_wrong_domain_artifact_falls_back(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            path = self._artifact(root, training_data_kind="external_benchmark")
            with patch.object(service, "TRUSTED_ARTIFACT_DIRECTORIES", (root,)):
                result = service.predict_future_incorrect(features(), artifact_path=path)
        self.assertEqual(result["prediction_source"], "cold_start_deterministic")
        self.assertIn("training_data", result["fallback_reason"])

    def test_qualified_high_risk_can_add_reinforcement_but_not_mastery(self):
        base = {
            "action": "advance",
            "reason": "Observed assessment passed.",
            "evidence": {"accuracy": 1.0},
        }
        prediction = {
            "prediction_id": "11111111-1111-4111-8111-111111111111",
            "probability_incorrect": 0.8,
            "prediction_source": "qualified_model",
            "validity_status": "valid",
            "model_version": "resonant-v1",
            "feature_schema_version": service.FEATURE_SCHEMA_VERSION,
            "fallback_reason": None,
        }
        result = service.hybridize_decision(base, prediction, current_difficulty=3)
        self.assertEqual(result["action"], "reinforce")
        self.assertEqual(result["decision_method"], "hybrid_ml_rules")
        self.assertEqual(result["difficulty_after"], 2)
        self.assertNotIn("mastery_after", result)


if __name__ == "__main__":
    unittest.main()

