"""Deterministic, explicit classification metrics for saved reports."""

from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    precision_recall_fscore_support,
)
import numpy as np


def evaluate_classifier(model, texts, truth, labels):
    predictions = model.predict(texts)
    macro = precision_recall_fscore_support(
        truth, predictions, average="macro", zero_division=0
    )
    weighted = precision_recall_fscore_support(
        truth, predictions, average="weighted", zero_division=0
    )
    return {
        "accuracy": float(accuracy_score(truth, predictions)),
        "macro_precision": float(macro[0]),
        "macro_recall": float(macro[1]),
        "macro_f1": float(macro[2]),
        "weighted_precision": float(weighted[0]),
        "weighted_recall": float(weighted[1]),
        "weighted_f1": float(weighted[2]),
        "class_report": classification_report(
            truth,
            predictions,
            labels=labels,
            output_dict=True,
            zero_division=0,
        ),
        "confusion_matrix": confusion_matrix(truth, predictions, labels=labels),
        "predictions": predictions,
    }


def calibration_summary(probabilities, truth, labels, *, bins=10):
    """Return top-label ECE and reliability bins; probabilities must align with labels."""
    probabilities = np.asarray(probabilities, dtype=float)
    truth = np.asarray(truth)
    if probabilities.ndim != 2 or probabilities.shape != (len(truth), len(labels)):
        raise ValueError("probability matrix must be rows x labels")
    if not np.isfinite(probabilities).all() or (probabilities < 0).any():
        raise ValueError("probabilities must be finite and non-negative")
    totals = probabilities.sum(axis=1)
    if not np.allclose(totals, 1.0, atol=1e-5):
        raise ValueError("each probability row must sum to one")
    top_indices = probabilities.argmax(axis=1)
    confidence = probabilities[np.arange(len(truth)), top_indices]
    predictions = np.asarray(labels)[top_indices]
    correct = predictions == truth
    edges = np.linspace(0.0, 1.0, bins + 1)
    reliability = []
    ece = 0.0
    for index in range(bins):
        mask = (confidence >= edges[index]) & (
            confidence <= edges[index + 1] if index == bins - 1 else confidence < edges[index + 1]
        )
        count = int(mask.sum())
        if not count:
            continue
        mean_confidence = float(confidence[mask].mean())
        accuracy = float(correct[mask].mean())
        ece += count / len(truth) * abs(mean_confidence - accuracy)
        reliability.append({"lower": float(edges[index]), "upper": float(edges[index + 1]),
                            "count": count, "mean_confidence": mean_confidence,
                            "accuracy": accuracy})
    return {"expected_calibration_error": float(ece), "reliability_bins": reliability}


def selective_risk(probabilities, truth, labels, *, coverages=(0.5, 0.8, 1.0)):
    """Accuracy/error among highest-confidence examples at requested coverage."""
    probabilities = np.asarray(probabilities, dtype=float)
    truth = np.asarray(truth)
    top_indices = probabilities.argmax(axis=1)
    confidence = probabilities[np.arange(len(truth)), top_indices]
    correct = np.asarray(labels)[top_indices] == truth
    order = np.argsort(-confidence, kind="stable")
    rows = []
    for coverage in coverages:
        if not 0 < coverage <= 1:
            raise ValueError("coverage values must be in (0, 1]")
        size = max(1, int(np.ceil(len(truth) * coverage)))
        accuracy = float(correct[order[:size]].mean())
        rows.append({"requested_coverage": float(coverage), "actual_coverage": size / len(truth),
                     "selected": size, "accuracy": accuracy, "risk": 1.0 - accuracy})
    return rows


def select_oos_threshold(probabilities, truth, labels, oos_label):
    """Select OOS probability threshold by validation binary F1; ties favor higher precision."""
    probabilities = np.asarray(probabilities, dtype=float)
    truth_oos = np.asarray(truth) == oos_label
    oos_index = list(labels).index(oos_label)
    oos_probability = probabilities[:, oos_index]
    order = np.argsort(-oos_probability, kind="stable")
    sorted_probability = oos_probability[order]
    sorted_truth = truth_oos[order]
    cumulative_tp = np.cumsum(sorted_truth)
    cumulative_fp = np.cumsum(~sorted_truth)
    # Only evaluate thresholds at the end of tied-score groups, plus reject-all.
    group_ends = np.r_[np.flatnonzero(np.diff(sorted_probability) != 0), len(order) - 1]
    tp = cumulative_tp[group_ends]
    fp = cumulative_fp[group_ends]
    fn = int(truth_oos.sum()) - tp
    precision_values = np.divide(tp, tp + fp, out=np.zeros_like(tp, dtype=float), where=(tp + fp) != 0)
    recall_values = np.divide(tp, tp + fn, out=np.zeros_like(tp, dtype=float), where=(tp + fn) != 0)
    f1_values = np.divide(
        2 * precision_values * recall_values,
        precision_values + recall_values,
        out=np.zeros_like(precision_values),
        where=(precision_values + recall_values) != 0,
    )
    thresholds = sorted_probability[group_ends]
    # Reject-all is a legitimate operating point and must be considered.
    precision_values = np.r_[precision_values, 0.0]
    recall_values = np.r_[recall_values, 0.0]
    f1_values = np.r_[f1_values, 0.0]
    thresholds = np.r_[thresholds, np.nextafter(sorted_probability[0], np.inf)]
    scored = list(zip(f1_values.tolist(), precision_values.tolist(), thresholds.tolist(), recall_values.tolist()))
    f1, precision, threshold, recall = max(scored, key=lambda row: (row[0], row[1], row[2]))
    return {"threshold": threshold, "validation_precision": precision,
            "validation_recall": recall, "validation_f1": f1}


def oos_threshold_metrics(probabilities, truth, labels, oos_label, threshold):
    from sklearn.metrics import precision_recall_fscore_support

    probabilities = np.asarray(probabilities, dtype=float)
    truth_oos = np.asarray(truth) == oos_label
    predicted_oos = probabilities[:, list(labels).index(oos_label)] >= threshold
    precision, recall, f1, _ = precision_recall_fscore_support(
        truth_oos, predicted_oos, average="binary", zero_division=0
    )
    return {"precision": float(precision), "recall": float(recall), "f1": float(f1),
            "threshold": float(threshold)}
