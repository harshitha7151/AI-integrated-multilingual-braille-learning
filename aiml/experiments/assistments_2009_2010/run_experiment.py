"""Train and evaluate genuine answer-outcome models on ASSISTments 2009-10."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import sys
import time

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import scipy
import sklearn
from sklearn.calibration import calibration_curve
from sklearn.metrics import ConfusionMatrixDisplay

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from data.assistments_2009 import (  # noqa: E402
    DATASET_ID,
    DATASET_PAGE,
    dataset_profile,
    load_assistments_2009,
)
from evaluation.educational_outcome import (  # noqa: E402
    evaluate_binary_outcome,
    learner_grouped_split,
)
from features.assistments_history import (  # noqa: E402
    CATEGORICAL_FEATURES,
    FEATURE_COLUMNS,
    GROUP_COLUMN,
    NUMERIC_FEATURES,
    TARGET_COLUMN,
    build_point_in_time_examples,
)
from models.educational_outcome import (  # noqa: E402
    build_models,
    random_forest_feature_importance,
)


SEED = 20261122
MODEL_VERSION = "assistments-rf-v1"
EXPERIMENT_ID = "assistments2009-grouped-unseen-learners-v1"
DEFAULT_INPUT = (
    ROOT
    / "data"
    / "raw"
    / "assistments_2009_2010"
    / "skill_builder_data_corrected_collapsed.csv"
)
DEFAULT_REPORT_DIR = ROOT / "reports" / "assistments_2009_2010"
DEFAULT_ARTIFACT = ROOT / "artifacts" / "assistments_2009_rf_v1.joblib"


def _json_safe(value):
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    if isinstance(value, (np.integer,)):
        return int(value)
    if isinstance(value, (np.floating,)):
        return float(value)
    if isinstance(value, np.ndarray):
        return value.tolist()
    return value


def _write_json(path: Path, value) -> None:
    path.write_text(json.dumps(_json_safe(value), indent=2) + "\n", encoding="utf-8")


def _display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def _plot_confusion(name: str, matrix, output: Path) -> None:
    fig, axis = plt.subplots(figsize=(5, 4))
    display = ConfusionMatrixDisplay(
        confusion_matrix=np.asarray(matrix),
        display_labels=["incorrect", "correct"],
    )
    display.plot(ax=axis, colorbar=False, cmap="Blues")
    axis.set_title(name.replace("_", " ").title())
    fig.tight_layout()
    fig.savefig(output, dpi=160)
    plt.close(fig)


def _plot_calibration(name: str, truth, probabilities, output: Path) -> None:
    observed, predicted = calibration_curve(
        truth, probabilities, n_bins=10, strategy="quantile"
    )
    fig, axis = plt.subplots(figsize=(6, 6))
    axis.plot([0, 1], [0, 1], linestyle="--", color="gray", label="ideal")
    axis.plot(predicted, observed, marker="o", label=name.replace("_", " "))
    axis.set(
        xlim=(0, 1),
        ylim=(0, 1),
        xlabel="Mean predicted probability",
        ylabel="Observed first-attempt correctness",
        title=f"Calibration — {name.replace('_', ' ').title()}",
    )
    axis.legend()
    fig.tight_layout()
    fig.savefig(output, dpi=160)
    plt.close(fig)


def _plot_model_comparison(model_reports: dict, output: Path) -> None:
    names = list(model_reports)
    metrics = ["accuracy", "macro_f1", "roc_auc"]
    values = np.asarray(
        [
            [
                model_reports[name][metric]
                if model_reports[name][metric] is not None
                else 0.0
                for metric in metrics
            ]
            for name in names
        ]
    )
    x = np.arange(len(names))
    width = 0.24
    fig, axis = plt.subplots(figsize=(9, 5))
    for index, metric in enumerate(metrics):
        axis.bar(x + (index - 1) * width, values[:, index], width, label=metric)
    axis.set_ylim(0, 1)
    axis.set_xticks(x, [name.replace("_", "\n") for name in names])
    axis.set_ylabel("Held-out score")
    axis.set_title("ASSISTments grouped unseen-learner evaluation")
    axis.legend()
    fig.tight_layout()
    fig.savefig(output, dpi=160)
    plt.close(fig)


def _report_markdown(report: dict) -> str:
    dataset = report["dataset"]
    split = report["split"]
    random_forest = report["models"]["random_forest"]
    sanitization = report["feature_engineering"]["sanitization"]
    importance = report["random_forest_top_feature_importance"]
    lines = [
        "# ASSISTments 2009–2010 educational outcome experiment",
        "",
        "This report contains measured results from the genuine corrected public Skill Builder dataset. It is not a Braille dataset and the model does not predict Braille mastery.",
        "",
        "## Dataset",
        "",
        f"- Records loaded: **{dataset['rows_loaded']:,}**.",
        f"- Learners: **{dataset['unique_learners']:,}**; questions: **{dataset['unique_questions']:,}**; non-null skill IDs: **{dataset['unique_skills_non_null']:,}**.",
        f"- Correct target rate: **{dataset['target']['rates']['1']:.4f}**.",
        f"- Source SHA-256: `{dataset['sha256']}`.",
        "- Target: first-attempt correctness as documented by ASSISTments.",
        "- Raw answer text and all learner/question/class/teacher identifiers are excluded from model features.",
        f"- Rows excluded: **{sanitization['rows_excluded']}**; missing skill IDs mapped to an explicit category: **{sanitization['missing_skill_mapped_to_explicit_category']:,}**.",
        "",
        "## Evaluation design",
        "",
        f"- Split: {split['method']}, seed `{split['random_seed']}`.",
        f"- Train: **{split['train_rows']:,} rows / {split['train_learners']:,} learners**.",
        f"- Test: **{split['test_rows']:,} rows / {split['test_learners']:,} learners**.",
        f"- Learner overlap: **{split['learner_overlap']}**.",
        "- A test learner's strictly earlier observed interactions may inform that learner's later point-in-time features, matching sequential deployment; no future or current outcome is used.",
        "- Model configurations were fixed before test evaluation; the test set was not used for tuning.",
        "",
        "## Actual held-out results",
        "",
        "| Model | Accuracy | Precision (correct) | Recall (correct) | F1 (correct) | Macro F1 | ROC-AUC | PR-AUC | Brier |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]

    def format_optional_metric(value):
        return "N/A" if value is None else f"{value:.4f}"

    for name, metrics in report["models"].items():
        lines.append(
            f"| {name.replace('_', ' ').title()} | {metrics['accuracy']:.4f} | {metrics['precision_correct']:.4f} | {metrics['recall_correct']:.4f} | {metrics['f1_correct']:.4f} | {metrics['macro_f1']:.4f} | {format_optional_metric(metrics['roc_auc'])} | {format_optional_metric(metrics['pr_auc'])} | {metrics['brier_score']:.4f} |"
        )
    lines += [
        "",
        "Random Forest confusion matrix (`[[true incorrect, false correct], [false incorrect, true correct]]`): "
        f"`{random_forest['confusion_matrix']}`.",
        "",
        "## Random Forest feature importance",
        "",
        "Impurity-based top features from the fitted pipeline:",
        "",
    ]
    for item in importance[:5]:
        lines.append(f"- `{item['feature']}`: {item['importance']:.6f}.")
    lines += [
        "",
        f"Artifact: `{report['artifact']['path']}` ({report['artifact']['bytes']:,} bytes; SHA-256 `{report['artifact']['sha256']}`).",
        "",
        "## Interpretation limits",
        "",
        "- The model estimates an educational first-attempt answer outcome in historical middle-school mathematics interactions.",
        "- It was not trained on Resonant records, Braille tasks, blind learners, Hindi, or Kannada learning data.",
        "- Grouped evaluation measures generalization to held-out learner identities while allowing earlier observed interactions to inform later predictions.",
        "- Impurity-based Random Forest feature importance is descriptive, can favor high-cardinality variables, and does not establish causality.",
        "- The endpoint is experimental and cannot override Resonant's deterministic prerequisites, remediation caps, or progression rules.",
        "",
    ]
    return "\n".join(lines)


def run(
    input_path: Path = DEFAULT_INPUT,
    *,
    report_dir: Path = DEFAULT_REPORT_DIR,
    artifact_path: Path = DEFAULT_ARTIFACT,
    seed: int = SEED,
    test_size: float = 0.2,
) -> dict:
    started_at = datetime.now(timezone.utc)
    report_dir.mkdir(parents=True, exist_ok=True)
    artifact_path.parent.mkdir(parents=True, exist_ok=True)

    raw = load_assistments_2009(input_path, verify_known_hash=True)
    profile = dataset_profile(raw, path=input_path)
    examples, sanitization = build_point_in_time_examples(raw)
    train_index, test_index, split = learner_grouped_split(
        examples[GROUP_COLUMN], test_size=test_size, seed=seed
    )
    train = examples.iloc[train_index]
    test = examples.iloc[test_index]
    split.update(
        {
            "train_rows": int(len(train)),
            "test_rows": int(len(test)),
            "train_positive_rate": float(train[TARGET_COLUMN].mean()),
            "test_positive_rate": float(test[TARGET_COLUMN].mean()),
        }
    )
    if train[TARGET_COLUMN].nunique() != 2 or test[TARGET_COLUMN].nunique() != 2:
        raise ValueError("both grouped partitions must contain both target classes")

    x_train = train.loc[:, list(FEATURE_COLUMNS)]
    y_train = train[TARGET_COLUMN].astype(int)
    x_test = test.loc[:, list(FEATURE_COLUMNS)]
    y_test = test[TARGET_COLUMN].astype(int)
    fitted_models = {}
    model_reports = {}
    for name, model in build_models(seed).items():
        fit_started = time.perf_counter()
        model.fit(x_train, y_train)
        fit_seconds = time.perf_counter() - fit_started
        evaluated = evaluate_binary_outcome(model, x_test, y_test)
        evaluated.pop("predictions")
        probabilities = evaluated.pop("probabilities")
        evaluated["fit_seconds"] = float(fit_seconds)
        model_reports[name] = evaluated
        fitted_models[name] = model
        _write_json(report_dir / f"{name}_classification_report.json", evaluated)
        pd.DataFrame(
            evaluated["confusion_matrix"],
            index=["actual_incorrect", "actual_correct"],
            columns=["predicted_incorrect", "predicted_correct"],
        ).to_csv(report_dir / f"{name}_confusion_matrix.csv")
        _plot_confusion(
            name,
            evaluated["confusion_matrix"],
            report_dir / f"{name}_confusion_matrix.png",
        )
        _plot_calibration(
            name,
            y_test,
            probabilities,
            report_dir / f"{name}_calibration.png",
        )

    model_configurations = {
        name: model.named_steps["model"].get_params(deep=False)
        for name, model in fitted_models.items()
    }

    _plot_model_comparison(model_reports, report_dir / "model_comparison.png")
    random_forest = fitted_models["random_forest"]
    feature_names, importance_values = random_forest_feature_importance(random_forest)
    importance = pd.DataFrame(
        {"feature": feature_names, "importance": importance_values}
    ).sort_values("importance", ascending=False, kind="stable")
    importance.to_csv(report_dir / "random_forest_feature_importance.csv", index=False)
    top_importance = importance.head(20).sort_values("importance")
    fig, axis = plt.subplots(figsize=(9, 7))
    axis.barh(top_importance["feature"], top_importance["importance"])
    axis.set_xlabel("Mean decrease in impurity importance")
    axis.set_title("Random Forest feature importance (top 20)")
    fig.tight_layout()
    fig.savefig(report_dir / "random_forest_feature_importance.png", dpi=160)
    plt.close(fig)

    completed_at = datetime.now(timezone.utc)
    software = {
        "python": platform.python_version(),
        "pandas": pd.__version__,
        "scipy": scipy.__version__,
        "scikit_learn": sklearn.__version__,
        "joblib": joblib.__version__,
    }
    artifact = {
        "artifact_format_version": 1,
        "pipeline": random_forest,
        "feature_columns": list(FEATURE_COLUMNS),
        "numeric_features": list(NUMERIC_FEATURES),
        "categorical_features": list(CATEGORICAL_FEATURES),
        "model_version": MODEL_VERSION,
        "experiment_id": EXPERIMENT_ID,
        "dataset_id": DATASET_ID,
        "dataset_sha256": profile["sha256"],
        "prediction_target": "first-attempt answer correctness (correct=1)",
        "training_date_utc": completed_at.isoformat(),
        "random_seed": seed,
        "training_configuration": {
            "test_size": float(test_size),
            "models": model_configurations,
        },
        "software": software,
        "split": split,
        "held_out_metrics": model_reports["random_forest"],
        "limitations": [
            "Not trained on Braille or Resonant learner data.",
            "Experimental educational outcome estimate only.",
            "Must not override deterministic Resonant learning safeguards.",
        ],
    }
    joblib.dump(artifact, artifact_path, compress=3)
    artifact_sha256 = hashlib.sha256(artifact_path.read_bytes()).hexdigest()

    sample_features = x_test.iloc[[0]]
    sample_probability = float(random_forest.predict_proba(sample_features)[0, 1])
    sample_prediction = int(random_forest.predict(sample_features)[0])
    sample_request = _json_safe(sample_features.iloc[0].to_dict())
    sample_response = {
        "prediction": sample_prediction,
        "probability_correct": sample_probability,
        "model_version": MODEL_VERSION,
        "experiment_id": EXPERIMENT_ID,
        "dataset_id": DATASET_ID,
        "prediction_target": artifact["prediction_target"],
        "experimental": True,
        "learning_action": None,
        "scope": (
            "Experimental educational outcome estimate; not a Braille mastery "
            "score or a Resonant learning action."
        ),
    }
    _write_json(report_dir / "sample_prediction_request.json", sample_request)
    _write_json(report_dir / "sample_prediction_response.json", sample_response)

    report = {
        "experiment_id": EXPERIMENT_ID,
        "model_version": MODEL_VERSION,
        "research_question": (
            "Can a model estimate first-attempt correctness from strictly prior "
            "learner interactions and current question/skill metadata?"
        ),
        "prediction_target": artifact["prediction_target"],
        "dataset": profile,
        "feature_engineering": {
            "features": list(FEATURE_COLUMNS),
            "numeric_features": list(NUMERIC_FEATURES),
            "categorical_features": list(CATEGORICAL_FEATURES),
            "learner_and_question_ids_in_model_matrix": False,
            "current_outcome_derived_fields_in_model_matrix": False,
            "sanitization": sanitization,
        },
        "split": split,
        "model_configurations": model_configurations,
        "models": model_reports,
        "random_forest_top_feature_importance": _json_safe(
            importance.head(20).to_dict(orient="records")
        ),
        "artifact": {
            "path": _display_path(artifact_path),
            "bytes": int(artifact_path.stat().st_size),
            "sha256": artifact_sha256,
            "format": "joblib containing a fitted scikit-learn Pipeline",
        },
        "software": software,
        "started_at_utc": started_at.isoformat(),
        "completed_at_utc": completed_at.isoformat(),
        "source_page": DATASET_PAGE,
        "sample": {
            "kind": "held-out test row features; no learner identifier retained",
            "observed_target": int(y_test.iloc[0]),
            "request_file": "sample_prediction_request.json",
            "response_file": "sample_prediction_response.json",
        },
    }
    _write_json(report_dir / "dataset_profile.json", profile)
    _write_json(report_dir / "metrics.json", report)
    _write_json(
        report_dir / "experiment_metadata.json",
        {
            key: report[key]
            for key in (
                "experiment_id",
                "model_version",
                "prediction_target",
                "split",
                "model_configurations",
                "artifact",
                "software",
                "started_at_utc",
                "completed_at_utc",
            )
        },
    )
    (report_dir / "REPORT.md").write_text(_report_markdown(report), encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--report-dir", type=Path, default=DEFAULT_REPORT_DIR)
    parser.add_argument("--artifact", type=Path, default=DEFAULT_ARTIFACT)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--test-size", type=float, default=0.2)
    arguments = parser.parse_args()
    result = run(
        arguments.input,
        report_dir=arguments.report_dir,
        artifact_path=arguments.artifact,
        seed=arguments.seed,
        test_size=arguments.test_size,
    )
    print(
        json.dumps(
            {
                "experiment_id": result["experiment_id"],
                "dataset_rows": result["dataset"]["rows_loaded"],
                "split": result["split"],
                "models": {
                    name: {
                        key: values[key]
                        for key in (
                            "accuracy",
                            "precision_correct",
                            "recall_correct",
                            "f1_correct",
                            "macro_f1",
                            "roc_auc",
                            "brier_score",
                        )
                    }
                    for name, values in result["models"].items()
                },
                "artifact": result["artifact"],
                "report": _display_path(DEFAULT_REPORT_DIR / "REPORT.md"),
            },
            indent=2,
        )
    )
