import ast
from pathlib import Path

import pandas as pd
import pytest

from analysis.practice_errors import summarize_skill_errors
from evaluation.binary import evaluate_binary
from features.mastery_events import (
    FEATURE_COLUMNS,
    build_next_attempt_examples,
    chronological_split,
    grouped_chronological_split,
)
from models.mastery_baselines import build_mastery_models


def test_mastery_feature_schema_matches_production_service_v2():
    backend = (
        Path(__file__).resolve().parents[2]
        / "resonant_backend"
        / "resonant_ml_service.py"
    )
    tree = ast.parse(backend.read_text(encoding="utf-8"))
    assignments = {
        target.id: ast.literal_eval(node.value)
        for node in tree.body
        if isinstance(node, ast.Assign)
        for target in node.targets
        if isinstance(target, ast.Name)
        and target.id in {"FEATURE_COLUMNS", "FEATURE_SCHEMA_VERSION"}
    }
    assert tuple(assignments["FEATURE_COLUMNS"]) == FEATURE_COLUMNS
    assert assignments["FEATURE_SCHEMA_VERSION"] == "resonant-next-attempt-v2"


def _events():
    return pd.DataFrame(
        [
            {"submission_id": "s1", "learner_id": "p1", "skill_id": "a", "language": "English", "outcome": "incorrect", "response_time_ms": 1000, "hint_used": True, "created_at": "2026-11-01T00:00:00Z"},
            {"submission_id": "s2", "learner_id": "p1", "skill_id": "a", "language": "English", "outcome": "correct", "response_time_ms": 2000, "hint_used": False, "created_at": "2026-11-02T00:00:00Z"},
            {"submission_id": "s3", "learner_id": "p1", "skill_id": "a", "language": "English", "outcome": "correct", "response_time_ms": 900, "hint_used": False, "created_at": "2026-11-03T00:00:00Z"},
            {"submission_id": "s4", "learner_id": "p2", "skill_id": "b", "language": "Hindi", "outcome": "timeout", "response_time_ms": 3000, "hint_used": False, "created_at": "2026-11-04T00:00:00Z"},
        ]
    )


def test_next_attempt_features_use_only_earlier_same_skill_events():
    examples = build_next_attempt_examples(_events())
    assert examples["target_submission_id"].tolist() == ["s2", "s3"]
    assert examples["prior_attempt_count"].tolist() == [1, 2]
    assert examples.iloc[0]["prior_accuracy_smoothed"] == pytest.approx(1 / 3)
    assert examples.iloc[0]["prior_hint_rate"] == 1.0
    assert examples.iloc[0]["target_incorrect"] == 0
    assert examples.iloc[0]["prior_incorrect_count"] == 1
    assert examples.iloc[0]["consecutive_incorrect"] == 1
    assert "learner_id" not in FEATURE_COLUMNS
    assert "target_incorrect" not in FEATURE_COLUMNS
    assert "response_time_ms" not in FEATURE_COLUMNS


def test_chronological_split_holds_future_targets_out():
    examples = build_next_attempt_examples(_events())
    train, test = chronological_split(examples, "2026-11-03T00:00:00Z")
    assert train["target_submission_id"].tolist() == ["s2"]
    assert test["target_submission_id"].tolist() == ["s3"]
    assert train["prediction_time"].max() < test["prediction_time"].min()


def test_grouped_chronological_split_holds_out_learner_identities():
    rows = []
    for learner in range(10):
        for day in range(1, 5):
            rows.append(
                {
                    "submission_id": f"s-{learner}-{day}",
                    "learner_id": f"p-{learner}",
                    "skill_id": "a",
                    "language": "English",
                    "outcome": "incorrect" if (learner + day) % 2 else "correct",
                    "response_time_ms": 1000 + day,
                    "hint_used": False,
                    "created_at": f"2026-11-{day:02d}T00:00:00Z",
                }
            )
    examples = build_next_attempt_examples(pd.DataFrame(rows))
    train, test = grouped_chronological_split(
        examples,
        "2026-11-03T00:00:00Z",
        seed=22,
        test_fraction=0.3,
    )
    assert not (set(train["learner_id"]) & set(test["learner_id"]))
    assert train["prediction_time"].max() < test["prediction_time"].min()


def test_skill_error_analysis_only_summarizes_observed_binary_answer_outcomes():
    summary = summarize_skill_errors(_events())
    assert len(summary) == 1
    assert "Hindi" not in set(summary["language"])
    english = summary.loc[summary["skill_id"] == "a"].iloc[0]
    assert english["answered_attempts"] == 3
    assert english["incorrect_count"] == 1
    assert english["error_rate"] == pytest.approx(1 / 3)


def test_mastery_baseline_pipelines_fit_transform_and_evaluate():
    rows = []
    for index in range(30):
        rows.append(
            {
                "language": "English" if index % 2 == 0 else "Hindi",
                "skill_id": "a" if index % 3 else "b",
                "question_type": "letter_recognition",
                "prior_attempt_count": index + 1,
                "prior_incorrect_count": index // 3,
                "prior_accuracy_smoothed": 0.2 + (index % 10) / 15,
                "prior_recent_accuracy": 0.1 + (index % 5) / 5,
                "prior_hint_rate": (index % 4) / 4,
                "prior_average_response_seconds": 3 + index / 10,
                "days_since_prior_practice": index % 7,
                "consecutive_incorrect": index % 3,
                "missing_dot_rate": (index % 4) / 4,
                "extra_dot_rate": (index % 5) / 5,
                "revision_count": index % 2,
                "prior_intervention_success_rate": 0.5,
                "current_difficulty": 1 + (index % 5),
            }
        )
    frame = pd.DataFrame(rows)
    target = [index % 2 for index in range(len(frame))]
    for model in build_mastery_models(seed=22).values():
        model.fit(frame.iloc[:20], target[:20])
        metrics = evaluate_binary(model, frame.iloc[20:], target[20:])
        assert metrics["rows"] == 10
        assert metrics["roc_auc"] is not None
        assert metrics["pr_auc"] is not None
        assert 0 <= metrics["brier_score"] <= 1
