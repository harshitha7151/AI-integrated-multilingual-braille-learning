import json
import zipfile

import joblib
import pandas as pd
import pytest

from data.clinc150 import load_clinc150_zip, remove_train_text_leakage
from evaluation.classification import evaluate_classifier
from evaluation.classification import (
    calibration_summary,
    oos_threshold_metrics,
    select_oos_threshold,
    selective_risk,
)
from models.intent_baselines import build_intent_models


def _write_clinc_fixture(path):
    payload = {
        "train": [[f"train example {i}", f"intent_{i}"] for i in range(150)],
        "val": [[f"validation example {i}", f"intent_{i}"] for i in range(150)],
        "test": [[f"test example {i}", f"intent_{i}"] for i in range(150)],
        "oos_train": [["train outside", "oos"]],
        "oos_val": [["validation outside", "oos"]],
        "oos_test": [["test outside", "oos"]],
    }
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("clinc150_uci/data_full.json", json.dumps(payload))


def test_clinc_loader_preserves_source_split_and_oos_label(tmp_path):
    archive = tmp_path / "fixture.zip"
    _write_clinc_fixture(archive)
    splits = load_clinc150_zip(archive)
    assert {name: len(frame) for name, frame in splits.items()} == {
        "train": 151,
        "validation": 151,
        "test": 151,
    }
    assert set(splits["train"]["split"]) == {"train"}
    assert splits["test"].iloc[-1]["intent"] == "__out_of_scope__"


def test_training_overlap_filter_preserves_evaluation_rows():
    train = pd.DataFrame({"text": ["repeated text", "train only"], "intent": ["a", "b"]})
    validation = pd.DataFrame({"text": ["Repeated Text"], "intent": ["a"]})
    test = pd.DataFrame({"text": ["test only"], "intent": ["b"]})
    filtered, stats = remove_train_text_leakage(train, validation, test)
    assert filtered["text"].tolist() == ["train only"]
    assert stats["training_rows_removed"] == 1
    assert stats["validation_rows_unchanged"] == 1
    assert stats["test_rows_unchanged"] == 1


def test_tfidf_baselines_fit_predict_and_serialize(tmp_path):
    train_x = [
        "write the letter a", "show letter a", "encode a", "explain six dots",
        "teach braille cell", "what is braille",
    ]
    train_y = ["mapping", "mapping", "mapping", "concept", "concept", "concept"]
    for name, model in build_intent_models(seed=17).items():
        model.fit(train_x, train_y)
        result = evaluate_classifier(
            model,
            ["letter a dots", "six dot braille"],
            ["mapping", "concept"],
            ["concept", "mapping"],
        )
        assert set(model.predict(["how to write a"])) <= {"mapping", "concept"}
        assert 0.0 <= result["accuracy"] <= 1.0
        assert result["confusion_matrix"].shape == (2, 2)
        assert name in {"tfidf_logistic_regression", "tfidf_linear_svm", "tfidf_calibrated_linear_svm"}
        artifact = tmp_path / f"{name}.joblib"
        joblib.dump({"model": model, "seed": 17}, artifact)
        loaded = joblib.load(artifact)
        assert loaded["model"].predict(["letter a dots"]).tolist() == model.predict(["letter a dots"]).tolist()


def test_probability_evaluation_reports_calibration_selective_risk_and_validation_oos_threshold():
    labels = ["braille", "__out_of_scope__"]
    validation_probabilities = [[0.9, 0.1], [0.55, 0.45], [0.2, 0.8], [0.1, 0.9]]
    validation_truth = ["braille", "__out_of_scope__", "braille", "__out_of_scope__"]
    calibration = calibration_summary(validation_probabilities, validation_truth, labels)
    assert 0 <= calibration["expected_calibration_error"] <= 1
    assert calibration["reliability_bins"]
    risk = selective_risk(validation_probabilities, validation_truth, labels)
    assert [row["requested_coverage"] for row in risk] == [0.5, 0.8, 1.0]
    selected = select_oos_threshold(
        validation_probabilities, validation_truth, labels, "__out_of_scope__"
    )
    test_metrics = oos_threshold_metrics(
        validation_probabilities, validation_truth, labels, "__out_of_scope__",
        selected["threshold"],
    )
    assert test_metrics["f1"] == pytest.approx(0.8)


def test_probability_evaluation_rejects_invalid_probability_rows():
    with pytest.raises(ValueError, match="sum to one"):
        calibration_summary([[0.3, 0.3]], ["a"], ["a", "b"])
