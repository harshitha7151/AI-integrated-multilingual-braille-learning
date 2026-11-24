"""Train and evaluate intent baselines on CLINC150's source-provided splits.

Run from the aiml directory after placing the official UCI archive at
data/raw/clinc150.zip: ``python experiments/intent_clinc150/run_experiment.py``.
The UCI archive includes CC BY 3.0 terms; retain attribution if redistributing.
"""

import hashlib
import json
from pathlib import Path
import sys

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.metrics import ConfusionMatrixDisplay

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from data.clinc150 import load_clinc150_zip, remove_train_text_leakage
from evaluation.classification import (
    calibration_summary,
    evaluate_classifier,
    oos_threshold_metrics,
    select_oos_threshold,
    selective_risk,
)
from models.intent_baselines import build_intent_models


SEED = 20261120
ARCHIVE = ROOT / "data" / "raw" / "clinc150.zip"
REPORTS = ROOT / "reports" / "intent_clinc150"
ARTIFACTS = ROOT / "artifacts"
OOS_LABEL = "__out_of_scope__"


def _dump_json(path: Path, payload) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _save_confusion(name, matrix, labels):
    csv = REPORTS / f"{name}_test_confusion_matrix.csv"
    pd.DataFrame(matrix, index=labels, columns=labels).to_csv(csv, index_label="true_intent")
    fig, axis = plt.subplots(figsize=(12, 10))
    ConfusionMatrixDisplay(matrix, display_labels=None).plot(
        ax=axis, colorbar=True, include_values=False, cmap="Blues"
    )
    axis.set_title(f"CLINC150 test confusion matrix — {name}\n151 labels; see CSV for label order")
    axis.set_xlabel("Predicted class")
    axis.set_ylabel("True class")
    axis.set_xticks([])
    axis.set_yticks([])
    fig.tight_layout()
    fig.savefig(REPORTS / f"{name}_test_confusion_matrix.png", dpi=160)
    plt.close(fig)


def _save_confidence_figures(name, calibration, risk):
    bins = calibration["reliability_bins"]
    if bins:
        fig, axis = plt.subplots(figsize=(6, 6))
        axis.plot([0, 1], [0, 1], linestyle="--", color="gray", label="perfect calibration")
        axis.plot(
            [row["mean_confidence"] for row in bins],
            [row["accuracy"] for row in bins],
            marker="o",
            label="model",
        )
        axis.set(xlim=(0, 1), ylim=(0, 1), xlabel="Mean predicted confidence",
                 ylabel="Observed accuracy", title=f"CLINC150 test reliability — {name}")
        axis.legend()
        fig.tight_layout()
        fig.savefig(REPORTS / f"{name}_test_reliability.png", dpi=160)
        plt.close(fig)
        pd.DataFrame(bins).to_csv(REPORTS / f"{name}_test_reliability_bins.csv", index=False)
    fig, axis = plt.subplots(figsize=(6, 4))
    axis.plot(
        [row["actual_coverage"] for row in risk],
        [row["risk"] for row in risk],
        marker="o",
    )
    axis.set(xlim=(0, 1), ylim=(0, 1), xlabel="Coverage retained by confidence rank",
             ylabel="Classification error rate", title=f"CLINC150 test risk–coverage — {name}")
    fig.tight_layout()
    fig.savefig(REPORTS / f"{name}_test_risk_coverage.png", dpi=160)
    plt.close(fig)


def _top_confusions(matrix, labels, limit=10):
    counts = matrix.copy()
    np.fill_diagonal(counts, 0)
    pairs = [
        (int(counts[row, column]), labels[row], labels[column])
        for row, column in zip(*np.nonzero(counts))
    ]
    return [
        {"true_intent": truth, "predicted_intent": prediction, "count": count}
        for count, truth, prediction in sorted(pairs, reverse=True)[:limit]
    ]


def run():
    if not ARCHIVE.is_file():
        raise FileNotFoundError(f"Expected benchmark archive: {ARCHIVE}")
    REPORTS.mkdir(parents=True, exist_ok=True)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    archive_sha = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
    splits = load_clinc150_zip(ARCHIVE)
    train = splits["train"]
    validation = splits["validation"]
    test = splits["test"]
    train, leakage = remove_train_text_leakage(train, validation, test)
    labels = sorted(train["intent"].unique())
    if len(labels) != 151 or OOS_LABEL not in labels:
        raise ValueError("expected all 150 intents and the OOS class in training data")

    metric_summary = {
        "provenance": {
            "dataset": "CLINC150 data_full.json from UCI archive",
            "source_url": "https://archive.ics.uci.edu/static/public/570/clinc150.zip",
            "paper_url": "https://aclanthology.org/D19-1131/",
            "official_repository": "https://github.com/clinc/oos-eval",
            "archive_sha256": archive_sha,
            "archive_bytes": ARCHIVE.stat().st_size,
            "license": "CC BY 3.0 according to the included UCI archive LICENSE; UCI catalog page lists CC BY 4.0, so preserve the archive terms and verify before redistribution.",
            "downloaded": True,
        },
        "task": "English 150-way in-scope intent classification plus one explicit OOS class; benchmark only, not Resonant Braille intent data.",
        "seed": SEED,
        "split": "official CLINC train/validation/test with OOS train/validation/test combined; training-only exact-text overlaps with validation/test removed; evaluation partitions unchanged",
        "counts": {
            "official_train_rows": len(splits["train"]),
            "train_rows_after_leakage_filter": len(train),
            "validation_rows": len(validation),
            "test_rows": len(test),
            "class_count": len(labels),
            "class_counts_train": train["intent"].value_counts().sort_index().to_dict(),
            "class_counts_validation": validation["intent"].value_counts().sort_index().to_dict(),
            "class_counts_test": test["intent"].value_counts().sort_index().to_dict(),
            "training_overlap_filter": leakage,
        },
        "models": {},
    }

    for name, model in build_intent_models(SEED).items():
        model.fit(train["text"], train["intent"])
        model_report = {}
        for split_name, frame in (("validation", validation), ("test", test)):
            result = evaluate_classifier(model, frame["text"], frame["intent"], labels)
            probabilities = (
                model.predict_proba(frame["text"])
                if hasattr(model, "predict_proba")
                else None
            )
            model_report[split_name] = {
                key: result[key]
                for key in (
                    "accuracy",
                    "macro_precision",
                    "macro_recall",
                    "macro_f1",
                    "weighted_precision",
                    "weighted_recall",
                    "weighted_f1",
                )
            }
            _dump_json(REPORTS / f"{name}_{split_name}_class_report.json", result["class_report"])
            if probabilities is not None:
                model_report[split_name]["top_label_calibration"] = calibration_summary(
                    probabilities, frame["intent"], labels
                )
                model_report[split_name]["selective_risk"] = selective_risk(
                    probabilities, frame["intent"], labels
                )
            else:
                model_report[split_name]["uncertainty_note"] = (
                    "Unavailable: raw LinearSVC margins are not calibrated probabilities."
                )
            if split_name == "validation" and probabilities is not None:
                model_report["validation_selected_oos_threshold"] = select_oos_threshold(
                    probabilities, frame["intent"], labels, OOS_LABEL
                )
            if split_name == "test":
                _save_confusion(name, result["confusion_matrix"], labels)
                if probabilities is not None:
                    _save_confidence_figures(
                        name,
                        model_report[split_name]["top_label_calibration"],
                        model_report[split_name]["selective_risk"],
                    )
                oos_metrics = result["class_report"][OOS_LABEL]
                model_report["test_error_analysis"] = {
                    "top_confusion_pairs": _top_confusions(
                        result["confusion_matrix"], labels
                    ),
                    "out_of_scope_precision": oos_metrics["precision"],
                    "out_of_scope_recall": oos_metrics["recall"],
                    "out_of_scope_f1": oos_metrics["f1-score"],
                    "validation_threshold_oos": (
                        oos_threshold_metrics(
                            probabilities, frame["intent"], labels, OOS_LABEL,
                            model_report["validation_selected_oos_threshold"]["threshold"],
                        )
                        if "validation_selected_oos_threshold" in model_report
                        else None
                    ),
                }
                errors = frame.loc[result["predictions"] != frame["intent"], ["text", "intent"]].copy()
                errors["prediction"] = result["predictions"][result["predictions"] != frame["intent"].to_numpy()]
                errors.head(250).to_csv(REPORTS / f"{name}_test_errors_sample.csv", index=False)

        model_report["estimator"] = model.__class__.__name__
        metric_summary["models"][name] = model_report
        joblib.dump(
            {
                "model": model,
                "labels": labels,
                "model_name": name,
                "seed": SEED,
                "dataset": "CLINC150 UCI data_full.json",
                "archive_sha256": archive_sha,
                "split_policy": metric_summary["split"],
            },
            ARTIFACTS / f"{name}.joblib",
        )

    _dump_json(REPORTS / "metrics.json", metric_summary)
    lines = [
        "# CLINC150 intent classification experiment",
        "",
        "This is a public English virtual-assistant benchmark experiment. It is not Resonant user data and does not validate Braille tutoring intents.",
        "",
        f"- Dataset: CLINC150 `data_full.json`; {metric_summary['counts']['class_count']} classes including explicit OOS.",
        f"- Archive SHA-256: `{archive_sha}`.",
        f"- Official rows: train {len(splits['train'])}, validation {len(validation)}, test {len(test)}.",
        f"- Exact text duplicates removed from training only: {leakage['training_rows_removed']} rows; validation/test remained unchanged.",
        f"- Seed: {SEED}; features: word TF-IDF uni/bi-grams; vectorizer fit inside each sklearn Pipeline on training text only.",
        "- Models: Logistic Regression, Linear SVM, and sigmoid-calibrated Linear SVM (3-fold calibration internal to training only). Hyperparameters were fixed; test results were not used for selection.",
        "- Confidence: top-label expected calibration error (ECE), fixed-bin reliability summaries, and accuracy/risk at confidence-ranked 50%, 80%, and 100% coverage. ECE depends on binning and is descriptive.",
        "- OOS: reports argmax OOS metrics plus a validation-selected OOS probability threshold and held-out test precision/recall/F1. This benchmark threshold is not a production safety policy.",
        "- License observed in downloaded archive: CC BY 3.0. The UCI catalog lists CC BY 4.0; check the authoritative terms before any redistribution.",
        "- Full per-class reports, confusion matrices, error samples and metrics are in this report folder.",
        "",
        "## Validation and test metrics",
        "",
        "| Model | Split | Accuracy | Macro precision | Macro recall | Macro F1 | Weighted F1 |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for name, report in metric_summary["models"].items():
        for split_name in ("validation", "test"):
            values = report[split_name]
            lines.append(
                f"| {name} | {split_name} | {values['accuracy']:.4f} | {values['macro_precision']:.4f} | {values['macro_recall']:.4f} | {values['macro_f1']:.4f} | {values['weighted_f1']:.4f} |"
            )
    lines += [
        "", "## Confidence and OOS operating points", "",
        "| Model | Test top-label ECE | Test accuracy at 50% coverage | OOS threshold selected on validation | Test OOS precision | Test OOS recall | Test OOS F1 |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for name, report in metric_summary["models"].items():
        ece = report["test"].get("top_label_calibration", {}).get("expected_calibration_error")
        selective = report["test"].get("selective_risk", [])
        coverage50 = next((row["accuracy"] for row in selective if row["requested_coverage"] == 0.5), None)
        threshold = report.get("validation_selected_oos_threshold")
        test_oos = report["test_error_analysis"].get("validation_threshold_oos")
        format_value = lambda value: "N/A" if value is None else f"{value:.4f}"
        lines.append(
            f"| {name} | {format_value(ece)} | {format_value(coverage50)} | "
            f"{format_value(threshold['threshold'] if threshold else None)} | "
            f"{format_value(test_oos['precision'] if test_oos else None)} | "
            f"{format_value(test_oos['recall'] if test_oos else None)} | "
            f"{format_value(test_oos['f1'] if test_oos else None)} |"
        )
    lines += ["", "## Error analysis", ""]
    for name, report in metric_summary["models"].items():
        summary = report["test_error_analysis"]
        lines.append(
            f"- **{name} OOS:** precision {summary['out_of_scope_precision']:.3f}, recall {summary['out_of_scope_recall']:.3f}, F1 {summary['out_of_scope_f1']:.3f}."
        )
        threshold_metrics = summary["validation_threshold_oos"]
        if threshold_metrics is not None:
            lines.append(
                f"  Validation-selected threshold test OOS metrics: precision {threshold_metrics['precision']:.3f}, "
                f"recall {threshold_metrics['recall']:.3f}, F1 {threshold_metrics['f1']:.3f} "
                f"(threshold {threshold_metrics['threshold']:.4f})."
            )
        else:
            lines.append("  Probability-threshold OOS analysis unavailable for uncalibrated SVM margins.")
        for split_name in ("validation", "test"):
            if "top_label_calibration" in report[split_name]:
                ece = report[split_name]["top_label_calibration"]["expected_calibration_error"]
                lines.append(f"- **{name} {split_name} confidence:** top-label ECE {ece:.4f}; selective risk bins are in metrics.json.")
            else:
                lines.append(f"- **{name} {split_name} confidence:** not available from uncalibrated margins.")
        pairs = summary["top_confusion_pairs"][:5]
        if pairs:
            lines.append(
                "  Largest non-diagonal class confusions: "
                + "; ".join(
                    f"{pair['true_intent']} → {pair['predicted_intent']} ({pair['count']})"
                    for pair in pairs
                )
                + "."
            )
    lines += [
        "",
        "## Interpretation limits",
        "",
        "CLINC150 utterances were crowd-authored for generic assistant intents, are English-only, and are single-intent. Resonant's multilingual Braille questions require their own reviewed training/evaluation set. The OOS label is benchmark-specific; it must not become a policy for encoding Braille. Exact string overlap was found between the official training data and held-out partitions, so overlapping training rows were excluded before fitting; evaluation rows and official split membership were preserved. No deployed tutor behavior uses these models.",
        "",
    ]
    (REPORTS / "REPORT.md").write_text("\n".join(lines), encoding="utf-8")
    return metric_summary


if __name__ == "__main__":
    results = run()
    print(json.dumps({
        "archive_sha256": results["provenance"]["archive_sha256"],
        "split_counts": {
            "train_after_filter": results["counts"]["train_rows_after_leakage_filter"],
            "validation": results["counts"]["validation_rows"],
            "test": results["counts"]["test_rows"],
        },
        "models": {
            name: values["test"] for name, values in results["models"].items()
        },
        "report": str(REPORTS / "REPORT.md"),
    }, indent=2))
