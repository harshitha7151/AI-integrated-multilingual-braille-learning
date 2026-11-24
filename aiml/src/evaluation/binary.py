"""Metrics for the observed binary next-answer target."""

from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    brier_score_loss,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)


def evaluate_binary(model, features, truth):
    truth = list(map(int, truth))
    if not truth or set(truth) - {0, 1}:
        raise ValueError("truth must be a non-empty binary sequence")
    predictions = model.predict(features)
    probabilities = model.predict_proba(features)[:, 1]
    has_both_classes = len(set(truth)) == 2
    return {
        "rows": len(truth),
        "positive_rate": sum(truth) / len(truth),
        "accuracy": float(accuracy_score(truth, predictions)),
        "precision": float(precision_score(truth, predictions, zero_division=0)),
        "recall": float(recall_score(truth, predictions, zero_division=0)),
        "f1": float(f1_score(truth, predictions, zero_division=0)),
        "roc_auc": float(roc_auc_score(truth, probabilities)) if has_both_classes else None,
        "pr_auc": float(average_precision_score(truth, probabilities)) if has_both_classes else None,
        "brier_score": float(brier_score_loss(truth, probabilities)),
        "prevalence_baseline_brier": float(
            brier_score_loss(truth, [sum(truth) / len(truth)] * len(truth))
        ),
        "calibration_bins": _calibration_bins(probabilities, truth),
    }


def _calibration_bins(probabilities, truth, bins=10):
    buckets = [[] for _ in range(bins)]
    for probability, outcome in zip(probabilities, truth):
        index = min(bins - 1, int(float(probability) * bins))
        buckets[index].append((float(probability), int(outcome)))
    return [
        {
            "bin": index,
            "count": len(values),
            "mean_probability": sum(p for p, _ in values) / len(values),
            "observed_rate": sum(y for _, y in values) / len(values),
        }
        for index, values in enumerate(buckets)
        if values
    ]
