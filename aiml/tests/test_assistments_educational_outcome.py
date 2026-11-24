import joblib
import pandas as pd
import pytest

from data.assistments_2009 import REQUIRED_COLUMNS, load_assistments_2009
from evaluation.educational_outcome import (
    evaluate_binary_outcome,
    learner_grouped_split,
)
from features.assistments_history import (
    FEATURE_COLUMNS,
    build_point_in_time_examples,
)
from models.educational_outcome import build_models


def _source_rows():
    defaults = {
        "assignment_id": 10,
        "assistment_id": 20,
        "sequence_id": 30,
        "student_class_id": 40,
        "base_sequence_id": 50,
        "teacher_id": 60,
        "school_id": 70,
        "template_id": 80,
        "answer_id": 90,
        "overlap_time": 0,
        "answer_text": "not exported",
        "bottom_hint": 0,
        "opportunity_original": 1,
        "type": "SkillBuilder",
        "skill_name": "Addition",
        "first_action": 0,
        "opportunity": 1,
    }
    rows = []
    for order_id, correct, attempts, response_ms, hints in (
        (3, 1, 3, 3000, 1),
        (1, 0, 1, 1000, 0),
        (2, 1, 2, 2000, 2),
    ):
        row = {
            **defaults,
            "order_id": order_id,
            "user_id": 101,
            "problem_id": 1000 + order_id,
            "original": 1,
            "correct": correct,
            "attempt_count": attempts,
            "ms_first_response": response_ms,
            "tutor_mode": "tutor",
            "answer_type": "algebra",
            "position": order_id,
            "skill_id": 7,
            "hint_count": hints,
            "hint_total": 4,
        }
        rows.append(row)
    return rows


def _write_source_fixture(path, rows=None):
    frame = pd.DataFrame(rows or _source_rows())
    for column in REQUIRED_COLUMNS:
        if column not in frame:
            frame[column] = 0
    frame.to_csv(path, index=False, encoding="latin1")
    return frame


def _model_frame(rows=48):
    records = []
    targets = []
    for index in range(rows):
        records.append(
            {
                "learner_prior_interactions": float(index),
                "learner_prior_success_rate": 0.2 + (index % 7) / 10,
                "learner_prior_hint_interaction_rate": (index % 4) / 4,
                "learner_prior_mean_attempts": 1.0 + (index % 3),
                "learner_prior_mean_response_ms": 800.0 + index * 25,
                "skill_prior_interactions": float(index % 12),
                "skill_prior_success_rate": 0.25 + (index % 6) / 10,
                "skill_prior_hint_interaction_rate": (index % 5) / 5,
                "skill_prior_mean_attempts": 1.0 + (index % 2),
                "skill_prior_mean_response_ms": 700.0 + index * 20,
                "original": index % 2,
                "position": index + 1,
                "hint_total": index % 8,
                "skill_id": str(index % 5),
                "tutor_mode": "tutor" if index % 8 else "test",
                "answer_type": "algebra" if index % 3 else "choose_1",
            }
        )
        targets.append(index % 2)
    return pd.DataFrame(records, columns=FEATURE_COLUMNS), pd.Series(targets)


def test_loader_validates_schema_and_binary_target(tmp_path):
    source = tmp_path / "assistments.csv"
    _write_source_fixture(source)
    loaded = load_assistments_2009(source)
    assert loaded["correct"].tolist() == [1, 0, 1]

    missing_skill = pd.DataFrame(_source_rows()).drop(columns=["skill_id"])
    missing_path = tmp_path / "missing-skill.csv"
    missing_skill.to_csv(missing_path, index=False, encoding="latin1")
    with pytest.raises(ValueError, match="skill_id"):
        load_assistments_2009(missing_path)

    invalid_rows = _source_rows()
    invalid_rows[0]["correct"] = 2
    invalid_path = tmp_path / "invalid-target.csv"
    _write_source_fixture(invalid_path, invalid_rows)
    with pytest.raises(ValueError, match="binary"):
        load_assistments_2009(invalid_path)

    invalid_numeric_rows = _source_rows()
    invalid_numeric_rows[0]["order_id"] = "not-an-order"
    invalid_numeric_path = tmp_path / "invalid-order.csv"
    _write_source_fixture(invalid_numeric_path, invalid_numeric_rows)
    with pytest.raises(ValueError, match="order_id must contain numeric"):
        load_assistments_2009(invalid_numeric_path)


def test_point_in_time_features_exclude_current_and_future_outcomes():
    source = pd.DataFrame(_source_rows())
    examples, sanitization = build_point_in_time_examples(source)
    by_order = examples.set_index("order_id")

    assert by_order.loc[1, "learner_prior_interactions"] == 0
    assert by_order.loc[1, "learner_prior_success_rate"] == pytest.approx(0.5)
    assert by_order.loc[2, "learner_prior_success_rate"] == pytest.approx(1 / 3)
    assert by_order.loc[3, "learner_prior_success_rate"] == pytest.approx(0.5)
    assert sanitization["rows_excluded"] == 0

    changed = source.copy()
    changed.loc[changed["order_id"] == 2, "correct"] = 0
    changed.loc[changed["order_id"] == 2, "attempt_count"] = 50
    changed.loc[changed["order_id"] == 2, "ms_first_response"] = 3_600_000
    changed.loc[changed["order_id"] == 2, "hint_count"] = 0
    changed_examples, _ = build_point_in_time_examples(changed)
    changed_by_order = changed_examples.set_index("order_id")

    pd.testing.assert_series_equal(
        by_order.loc[2, list(FEATURE_COLUMNS)],
        changed_by_order.loc[2, list(FEATURE_COLUMNS)],
        check_names=False,
    )
    assert (
        by_order.loc[3, "learner_prior_success_rate"]
        != changed_by_order.loc[3, "learner_prior_success_rate"]
    )
    assert "correct" not in FEATURE_COLUMNS
    assert "attempt_count" not in FEATURE_COLUMNS
    assert "ms_first_response" not in FEATURE_COLUMNS
    assert "hint_count" not in FEATURE_COLUMNS
    assert "user_id" not in FEATURE_COLUMNS
    assert "problem_id" not in FEATURE_COLUMNS


def test_grouped_split_is_reproducible_and_has_no_learner_overlap():
    groups = [f"learner-{index // 4}" for index in range(40)]
    train_a, test_a, report_a = learner_grouped_split(
        groups, test_size=0.2, seed=20261122
    )
    train_b, test_b, report_b = learner_grouped_split(
        groups, test_size=0.2, seed=20261122
    )
    assert train_a.tolist() == train_b.tolist()
    assert test_a.tolist() == test_b.tolist()
    assert report_a == report_b
    assert report_a["learner_overlap"] == 0
    assert set(groups[index] for index in train_a).isdisjoint(
        groups[index] for index in test_a
    )


def test_models_fit_evaluate_serialize_and_predict(tmp_path):
    features, target = _model_frame()
    train_x, test_x = features.iloc[:36], features.iloc[36:]
    train_y, test_y = target.iloc[:36], target.iloc[36:]

    fitted = build_models(seed=20261122)
    for model in fitted.values():
        model.fit(train_x, train_y)
        metrics = evaluate_binary_outcome(model, test_x, test_y)
        assert metrics["rows"] == 12
        assert 0 <= metrics["accuracy"] <= 1
        assert 0 <= metrics["brier_score"] <= 1

    artifact_path = tmp_path / "educational-outcome.joblib"
    joblib.dump(
        {
            "artifact_format_version": 1,
            "pipeline": fitted["random_forest"],
            "feature_columns": list(FEATURE_COLUMNS),
            "model_version": "test-rf-v1",
            "experiment_id": "test-experiment",
            "dataset_id": "test-dataset",
            "prediction_target": "first-attempt answer correctness (correct=1)",
        },
        artifact_path,
    )
    loaded = joblib.load(artifact_path)
    prediction = loaded["pipeline"].predict(test_x.iloc[[0]])
    probability = loaded["pipeline"].predict_proba(test_x.iloc[[0]])[0, 1]
    assert int(prediction[0]) in {0, 1}
    assert 0 <= float(probability) <= 1
