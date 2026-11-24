"""Train qualification-gated Resonant future-attempt error baselines.

The runner accepts only an approved, pseudonymized Resonant export accompanied
by a provenance manifest. It uses the production feature schema, a learner-
grouped forward-time evaluation, and never promotes an artifact unless both
configured gates and an explicit human review identifier are present.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from sklearn.calibration import calibration_curve
from sklearn.metrics import ConfusionMatrixDisplay, confusion_matrix

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from evaluation.binary import evaluate_binary
from features.mastery_events import (
    FEATURE_COLUMNS,
    FEATURE_SCHEMA_VERSION,
    TARGET_COLUMN,
    build_next_attempt_examples,
    grouped_chronological_split,
)
from models.mastery_baselines import build_mastery_models


FORBIDDEN_INPUT_COLUMNS = {
    "name",
    "username",
    "phone",
    "email",
    "batch",
    "teacher_id",
    "password",
    "password_hash",
    "code_hash",
    "learner_code",
    "audio",
    "transcript",
}
SEED = 20261121
ARTIFACT_KIND = "resonant_next_attempt"
TRAINING_DATA_KIND = "consented_resonant_events"
PREDICTION_TASK = "probability_of_incorrect_future_attempt"


def _load_provenance(path: Path | None, data_hash: str) -> dict:
    if path is None or not path.is_file():
        raise ValueError("authorized provenance manifest is required")
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("provenance manifest must be a JSON object")
    required = {
        "authorization_id",
        "data_origin",
        "research_eligible",
        "pseudonymization_method",
        "export_as_of",
        "source_sha256",
    }
    missing = sorted(required - set(payload))
    if missing:
        raise ValueError("provenance manifest is missing: " + ", ".join(missing))
    if payload["data_origin"] != TRAINING_DATA_KIND:
        raise ValueError("training data must be labelled consented_resonant_events")
    if payload["research_eligible"] is not True:
        raise ValueError("provenance manifest does not authorize research use")
    if not str(payload["authorization_id"]).strip():
        raise ValueError("authorization_id cannot be blank")
    if "hmac" not in str(payload["pseudonymization_method"]).lower():
        raise ValueError("learner identifiers must use a documented HMAC pseudonym")
    if payload["source_sha256"] != data_hash:
        raise ValueError("provenance source_sha256 does not match the input CSV")
    export_time = pd.to_datetime(payload["export_as_of"], utc=True, errors="coerce")
    if pd.isna(export_time):
        raise ValueError("provenance export_as_of must be a valid UTC timestamp")
    return payload


def _language_qualification(
    test: pd.DataFrame,
    *,
    minimum_rows: int,
    minimum_learners: int,
) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for language, rows in test.groupby("language", sort=True):
        learners = int(rows["learner_id"].nunique())
        class_count = int(rows[TARGET_COLUMN].nunique())
        result[str(language)] = {
            "rows": int(len(rows)),
            "learners": learners,
            "both_classes_present": class_count == 2,
            "eligible": (
                len(rows) >= minimum_rows
                and learners >= minimum_learners
                and class_count == 2
            ),
        }
    return result


def _qualification(
    metrics: dict,
    *,
    train: pd.DataFrame,
    test: pd.DataFrame,
    minimum_train_rows: int,
    minimum_test_rows: int,
    minimum_train_learners: int,
    minimum_test_learners: int,
    minimum_roc_auc: float,
    maximum_brier: float,
    minimum_language_test_rows: int,
    minimum_language_test_learners: int,
    approved_by: str | None,
) -> dict:
    languages = _language_qualification(
        test,
        minimum_rows=minimum_language_test_rows,
        minimum_learners=minimum_language_test_learners,
    )
    gates = {
        "minimum_train_rows": len(train) >= minimum_train_rows,
        "minimum_test_rows": len(test) >= minimum_test_rows,
        "minimum_train_learners": (
            train["learner_id"].nunique() >= minimum_train_learners
        ),
        "minimum_test_learners": (
            test["learner_id"].nunique() >= minimum_test_learners
        ),
        "both_train_classes": train[TARGET_COLUMN].nunique() == 2,
        "both_test_classes": test[TARGET_COLUMN].nunique() == 2,
        "minimum_roc_auc": (
            metrics["roc_auc"] is not None
            and metrics["roc_auc"] >= minimum_roc_auc
        ),
        "maximum_brier": metrics["brier_score"] <= maximum_brier,
        "at_least_one_language_qualified": any(
            item["eligible"] for item in languages.values()
        ),
    }
    automated_gates_passed = all(gates.values())
    reviewer = (approved_by or "").strip()
    return {
        "passed": automated_gates_passed and bool(reviewer),
        "automated_gates_passed": automated_gates_passed,
        "human_review_required": not bool(reviewer),
        "approved_by": reviewer or None,
        "gates": gates,
        "thresholds": {
            "minimum_train_rows": minimum_train_rows,
            "minimum_test_rows": minimum_test_rows,
            "minimum_train_learners": minimum_train_learners,
            "minimum_test_learners": minimum_test_learners,
            "minimum_roc_auc": minimum_roc_auc,
            "maximum_brier": maximum_brier,
            "minimum_language_test_rows": minimum_language_test_rows,
            "minimum_language_test_learners": minimum_language_test_learners,
        },
        "languages": languages,
    }


def run(
    input_path: Path,
    cutoff: str,
    minimum_rows: int = 100,
    *,
    provenance_path: Path | None = None,
    minimum_test_rows: int | None = None,
    minimum_train_learners: int = 20,
    minimum_test_learners: int = 10,
    minimum_roc_auc: float = 0.60,
    maximum_brier: float = 0.25,
    minimum_language_test_rows: int = 50,
    minimum_language_test_learners: int = 5,
    test_fraction: float = 0.20,
    qualification_approved_by: str | None = None,
    promote_qualified: bool = False,
) -> dict:
    if not input_path.is_file():
        raise FileNotFoundError(f"input CSV not found: {input_path}")
    raw = pd.read_csv(input_path)
    present_sensitive = sorted(FORBIDDEN_INPUT_COLUMNS & set(raw.columns))
    if present_sensitive:
        raise ValueError(
            "input includes forbidden personal/sensitive columns: "
            + ", ".join(present_sensitive)
        )
    data_hash = hashlib.sha256(input_path.read_bytes()).hexdigest()
    provenance = _load_provenance(provenance_path, data_hash)
    examples = build_next_attempt_examples(raw)
    train, test = grouped_chronological_split(
        examples,
        cutoff,
        seed=SEED,
        test_fraction=test_fraction,
    )
    configured_test_rows = minimum_test_rows or max(20, minimum_rows // 5)
    if len(train) < minimum_rows or len(test) < configured_test_rows:
        raise ValueError(
            "insufficient rows for the configured gate: "
            f"train={len(train)}, test={len(test)}, "
            f"minimum_train={minimum_rows}, minimum_test={configured_test_rows}"
        )
    if train[TARGET_COLUMN].nunique() != 2 or test[TARGET_COLUMN].nunique() != 2:
        raise ValueError(
            "both learner-grouped chronological partitions must contain correct and incorrect labels"
        )
    train_learners = int(train["learner_id"].nunique())
    test_learners = int(test["learner_id"].nunique())
    if train_learners < minimum_train_learners or test_learners < minimum_test_learners:
        raise ValueError(
            "insufficient learner diversity for configured gates: "
            f"train={train_learners}, test={test_learners}"
        )

    report = {
        "source": {
            "kind": TRAINING_DATA_KIND,
            "sha256": data_hash,
            "rows": len(raw),
            "authorization_id": provenance["authorization_id"],
            "pseudonymization_method": provenance["pseudonymization_method"],
            "export_as_of": provenance["export_as_of"],
            "pii_columns_rejected": sorted(FORBIDDEN_INPUT_COLUMNS),
        },
        "target": PREDICTION_TASK,
        "target_definition": (
            "Observed incorrect outcome of a future eligible attempt; not latent mastery"
        ),
        "feature_schema_version": FEATURE_SCHEMA_VERSION,
        "feature_columns": list(FEATURE_COLUMNS),
        "excluded_metadata": [
            "learner_id",
            "prediction_time",
            "target_submission_id",
        ],
        "split": {
            "method": "learner-grouped chronological holdout",
            "cutoff_utc": pd.to_datetime(cutoff, utc=True).isoformat(),
            "seed": SEED,
            "test_fraction": test_fraction,
            "train_rows": len(train),
            "test_rows": len(test),
            "train_learners": train_learners,
            "test_learners": test_learners,
            "learner_overlap": len(
                set(train["learner_id"]) & set(test["learner_id"])
            ),
            "train_incorrect_rate": float(train[TARGET_COLUMN].mean()),
            "test_incorrect_rate": float(test[TARGET_COLUMN].mean()),
        },
        "models": {},
        "limitations": [
            "Qualification gates are configurable engineering safeguards, not proof of educational effectiveness.",
            "The target is a future observed error and may be affected by practice selection, hints, and other confounding.",
            "Each language is qualified separately; unevaluated languages remain in deterministic cold-start mode.",
            "A retrospective model result does not demonstrate improved learning from an intervention.",
        ],
    }
    output = ROOT / "reports" / "mastery_prediction"
    artifact_dir = ROOT / "artifacts"
    output.mkdir(parents=True, exist_ok=True)
    artifact_dir.mkdir(parents=True, exist_ok=True)
    feature_train = train.loc[:, list(FEATURE_COLUMNS)]
    feature_test = test.loc[:, list(FEATURE_COLUMNS)]
    y_train = train[TARGET_COLUMN].astype(int)
    y_test = test[TARGET_COLUMN].astype(int)
    qualified_candidates: list[tuple[str, float, Path, dict]] = []

    for name, model in build_mastery_models(SEED).items():
        model.fit(feature_train, y_train)
        metrics = evaluate_binary(model, feature_test, y_test)
        qualification = _qualification(
            metrics,
            train=train,
            test=test,
            minimum_train_rows=minimum_rows,
            minimum_test_rows=configured_test_rows,
            minimum_train_learners=minimum_train_learners,
            minimum_test_learners=minimum_test_learners,
            minimum_roc_auc=minimum_roc_auc,
            maximum_brier=maximum_brier,
            minimum_language_test_rows=minimum_language_test_rows,
            minimum_language_test_learners=minimum_language_test_learners,
            approved_by=qualification_approved_by,
        )
        report["models"][name] = {
            **metrics,
            "qualification": qualification,
        }
        probabilities = model.predict_proba(feature_test)[:, 1]
        observed, predicted = calibration_curve(
            y_test,
            probabilities,
            n_bins=10,
            strategy="quantile",
        )
        fig, axis = plt.subplots(figsize=(6, 6))
        axis.plot([0, 1], [0, 1], linestyle="--", color="gray", label="ideal")
        axis.plot(predicted, observed, marker="o", label=name)
        axis.set(
            xlim=(0, 1),
            ylim=(0, 1),
            xlabel="Mean predicted probability of incorrect response",
            ylabel="Observed incorrect-response rate",
            title=f"Calibration — {name}",
        )
        axis.legend()
        fig.tight_layout()
        fig.savefig(output / f"{name}_calibration.png", dpi=160)
        plt.close(fig)
        fig, axis = plt.subplots(figsize=(5, 4))
        ConfusionMatrixDisplay(
            confusion_matrix(y_test, model.predict(feature_test), labels=[0, 1]),
            display_labels=["correct", "incorrect"],
        ).plot(ax=axis, colorbar=False, cmap="Blues")
        axis.set_title(name)
        fig.tight_layout()
        fig.savefig(output / f"{name}_confusion_matrix.png", dpi=160)
        plt.close(fig)

        model_version = (
            f"resonant-next-attempt-v2-{name}-"
            f"{data_hash[:12]}-{report['split']['cutoff_utc'][:10]}"
        )
        supported_languages = sorted(
            language
            for language, detail in qualification["languages"].items()
            if detail["eligible"]
        )
        artifact = {
            "artifact_kind": ARTIFACT_KIND,
            "model": model,
            "model_type": name,
            "model_version": model_version,
            "prediction_task": PREDICTION_TASK,
            "feature_schema_version": FEATURE_SCHEMA_VERSION,
            "feature_columns": list(FEATURE_COLUMNS),
            "incorrect_class_label": 1,
            "training_data_kind": TRAINING_DATA_KIND,
            "qualified_for_inference": qualification["passed"],
            "qualification": qualification,
            "supported_languages": supported_languages,
            "evaluation_metrics": metrics,
            "dataset_provenance": report["source"],
            "trained_at": datetime.now(timezone.utc).isoformat(),
        }
        artifact_path = artifact_dir / f"mastery_{name}.joblib"
        joblib.dump(artifact, artifact_path)
        if qualification["passed"]:
            qualified_candidates.append(
                (name, metrics["brier_score"], artifact_path, artifact)
            )

    promoted = None
    if promote_qualified:
        if not qualified_candidates:
            raise ValueError(
                "promotion requested but no model passed automated gates and explicit human review"
            )
        _, _, _, artifact = min(qualified_candidates, key=lambda item: item[1])
        promoted_path = artifact_dir / "resonant_next_attempt_v2.joblib"
        joblib.dump(artifact, promoted_path)
        promoted = {
            "path": str(promoted_path),
            "model_version": artifact["model_version"],
            "supported_languages": artifact["supported_languages"],
        }
    report["promoted_artifact"] = promoted

    (output / "metrics.json").write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    lines = [
        "# Resonant future-attempt error prediction report",
        "",
        f"- Source CSV SHA-256: `{data_hash}` ({len(raw)} rows).",
        f"- Authorization: `{provenance['authorization_id']}`.",
        f"- Target: {report['target_definition']}.",
        f"- Feature schema: `{FEATURE_SCHEMA_VERSION}`.",
        f"- Split: learner-grouped chronological holdout at {report['split']['cutoff_utc']}; learner overlap is 0.",
        f"- Train: {len(train)} examples / {train_learners} learners; test: {len(test)} examples / {test_learners} learners.",
        "- No result is a claim of latent mastery, educational effectiveness, or multilingual generalization.",
        "",
        "| Model | Accuracy | Precision | Recall | F1 | ROC-AUC | PR-AUC | Brier | Qualified |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for name, values in report["models"].items():
        metric = lambda value: "N/A" if value is None else f"{value:.4f}"
        lines.append(
            f"| {name} | {values['accuracy']:.4f} | {values['precision']:.4f} | "
            f"{values['recall']:.4f} | {values['f1']:.4f} | "
            f"{metric(values['roc_auc'])} | {metric(values['pr_auc'])} | "
            f"{values['brier_score']:.4f} | {values['qualification']['passed']} |"
        )
    lines += [
        "",
        "## Limitations",
        "",
        *[f"- {item}" for item in report["limitations"]],
        "",
    ]
    (output / "REPORT.md").write_text("\n".join(lines), encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--provenance", type=Path, required=True)
    parser.add_argument("--cutoff", required=True)
    parser.add_argument("--minimum-rows", type=int, default=100)
    parser.add_argument("--minimum-test-rows", type=int)
    parser.add_argument("--minimum-train-learners", type=int, default=20)
    parser.add_argument("--minimum-test-learners", type=int, default=10)
    parser.add_argument("--minimum-roc-auc", type=float, default=0.60)
    parser.add_argument("--maximum-brier", type=float, default=0.25)
    parser.add_argument("--minimum-language-test-rows", type=int, default=50)
    parser.add_argument("--minimum-language-test-learners", type=int, default=5)
    parser.add_argument("--test-fraction", type=float, default=0.20)
    parser.add_argument("--qualification-approved-by")
    parser.add_argument("--promote-qualified", action="store_true")
    arguments = parser.parse_args()
    result = run(
        arguments.input,
        arguments.cutoff,
        arguments.minimum_rows,
        provenance_path=arguments.provenance,
        minimum_test_rows=arguments.minimum_test_rows,
        minimum_train_learners=arguments.minimum_train_learners,
        minimum_test_learners=arguments.minimum_test_learners,
        minimum_roc_auc=arguments.minimum_roc_auc,
        maximum_brier=arguments.maximum_brier,
        minimum_language_test_rows=arguments.minimum_language_test_rows,
        minimum_language_test_learners=arguments.minimum_language_test_learners,
        test_fraction=arguments.test_fraction,
        qualification_approved_by=arguments.qualification_approved_by,
        promote_qualified=arguments.promote_qualified,
    )
    print(
        json.dumps(
            {
                "rows": result["split"]["train_rows"]
                + result["split"]["test_rows"],
                "split": result["split"],
                "models": {
                    key: {
                        metric: value[metric]
                        for metric in (
                            "accuracy",
                            "f1",
                            "roc_auc",
                            "pr_auc",
                            "brier_score",
                        )
                    }
                    for key, value in result["models"].items()
                },
                "promoted_artifact": result["promoted_artifact"],
                "report": str(
                    ROOT / "reports" / "mastery_prediction" / "REPORT.md"
                ),
            },
            indent=2,
        )
    )
