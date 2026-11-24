"""Actual, separate experimental AIML artifact inspection and inference."""

from __future__ import annotations

from functools import lru_cache
import json
from pathlib import Path
from typing import Any

import joblib
import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[1]
AIML_ROOT = REPO_ROOT / "aiml"
REPORT_PATH = AIML_ROOT / "reports" / "intent_clinc150" / "metrics.json"
MODEL_FILES = {
    "tfidf_logistic_regression": "tfidf_logistic_regression.joblib",
    "tfidf_linear_svm": "tfidf_linear_svm.joblib",
    "tfidf_calibrated_linear_svm": "tfidf_calibrated_linear_svm.joblib",
}


class ExperimentalArtifactUnavailable(RuntimeError):
    pass


def dashboard_catalog() -> dict[str, Any]:
    metrics = json.loads(REPORT_PATH.read_text(encoding="utf-8")) if REPORT_PATH.exists() else {}
    counts = metrics.get("counts", {})
    models = []
    for name, filename in MODEL_FILES.items():
        artifact = AIML_ROOT / "artifacts" / filename
        models.append({
            "id": name,
            "available": artifact.is_file(),
            "artifact_bytes": artifact.stat().st_size if artifact.is_file() else None,
            "live_application": False,
            "kind": "experimental CLINC150 text classifier",
            "test_metrics": metrics.get("models", {}).get(name, {}).get("test", {}),
        })
    return {
        "live_application": {
            "intent_resolution": "Deterministic Flutter command parser and validated action controller",
            "braille": "Deterministic language-specific mapping and validation engines",
            "recommendations": (
                "Learner-facing deterministic candidate policy uses BKT skill state, "
                "due review, response-error evidence, expected information gain, and "
                "an exponential-decay forgetting-risk estimate. LinUCB uses only "
                "persisted completed recommendation outcomes after five observations; "
                "otherwise the cold-start policy is deterministic. Offline benchmark "
                "models are not the live recommender."
            ),
        },
        "experiments": {
            "dataset": metrics.get("provenance", {}).get("dataset", "CLINC150"),
            "source": metrics.get("provenance", {}).get("source_url"),
            "license": metrics.get("provenance", {}).get("license"),
            "split_counts": {
                "train": counts.get("train_rows_after_leakage_filter"),
                "validation": counts.get("validation_rows"),
                "test": counts.get("test_rows"),
                "classes": counts.get("class_count"),
            },
            "features": "TfidfVectorizer: lowercase, strip_accents=unicode, word uni/bi-grams, sublinear_tf; trained in pipeline on train split.",
            "limitations": "English generic-assistant benchmark only; not Resonant data and not used for live Tutor navigation.",
            "models": models,
        },
    }


@lru_cache(maxsize=3)
def _load_pipeline(model_id: str):
    filename = MODEL_FILES.get(model_id)
    if filename is None:
        raise ValueError("Unknown experimental model.")
    artifact = AIML_ROOT / "artifacts" / filename
    if not artifact.is_file():
        raise ExperimentalArtifactUnavailable("The selected experiment artifact is missing.")
    try:
        bundle = joblib.load(artifact)
        # The reproducible training scripts store model metadata beside the
        # fitted pipeline. Dashboard inference must use that trained pipeline.
        pipeline = bundle.get("model") if isinstance(bundle, dict) else bundle
        if not hasattr(pipeline, "named_steps"):
            raise TypeError("Artifact does not contain a fitted pipeline.")
        return pipeline
    except Exception as error:
        raise ExperimentalArtifactUnavailable("The selected experiment artifact could not be loaded.") from error


def compare_intent(text: str, model_ids: list[str]) -> dict[str, Any]:
    if not text.strip() or len(text) > 1000:
        raise ValueError("Enter text containing at most 1000 characters.")
    if not model_ids or len(model_ids) > 3 or len(set(model_ids)) != len(model_ids):
        raise ValueError("Select one or more unique available models.")
    results = []
    for model_id in model_ids:
        if model_id not in MODEL_FILES:
            raise ValueError("Unknown experimental model.")
        pipeline = _load_pipeline(model_id)
        vectorizer = pipeline.named_steps["tfidf"]
        classifier = pipeline.named_steps["classifier"]
        matrix = vectorizer.transform([text])
        feature_names = vectorizer.get_feature_names_out()
        row = matrix.tocsr()
        features = [
            {"term": str(feature_names[index]), "weight": float(weight)}
            for index, weight in sorted(
                zip(row.indices, row.data), key=lambda pair: pair[1], reverse=True
            )[:15]
        ]
        prediction = str(pipeline.predict([text])[0])
        class_names = [str(value) for value in classifier.classes_]
        scores: dict[str, Any]
        if hasattr(classifier, "predict_proba"):
            values = classifier.predict_proba(matrix)[0]
            score_kind = "calibrated_probability" if model_id.endswith("calibrated_linear_svm") else "class_probability"
            score_map = dict(zip(class_names, (float(value) for value in values)))
        else:
            values = classifier.decision_function(matrix)[0]
            score_kind = "raw_decision_margin"
            score_map = dict(zip(class_names, (float(value) for value in values)))
        scores = {
            "kind": score_kind,
            "top_classes": [
                {"class": label, "score": score}
                for label, score in sorted(score_map.items(), key=lambda item: item[1], reverse=True)[:5]
            ],
        }
        results.append({
            "model_id": model_id,
            "prediction": prediction,
            "scores": scores,
            "features": features,
            "vocabulary_size": len(feature_names),
            "experimental": True,
            "controls_live_application": False,
        })
    return {"input": text, "results": results}
