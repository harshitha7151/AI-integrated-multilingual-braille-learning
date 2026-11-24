"""Grouped splitting and complete held-out metrics for binary outcomes."""

from __future__ import annotations

from typing import Any

import numpy as np
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    brier_score_loss,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_recall_fscore_support,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import GroupShuffleSplit


def learner_grouped_split(
    groups,
    *,
    test_size: float,
    seed: int,
) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    groups = np.asarray(groups)
    if len(groups) == 0:
        raise ValueError("grouped split requires at least one row")
    if len(np.unique(groups)) < 2:
        raise ValueError("grouped split requires at least two learners")
    splitter = GroupShuffleSplit(
        n_splits=1,
        test_size=test_size,
        random_state=seed,
    )
    train_index, test_index = next(splitter.split(np.zeros(len(groups)), groups=groups))
    train_groups = set(groups[train_index].tolist())
    test_groups = set(groups[test_index].tolist())
    overlap = train_groups & test_groups
    if overlap:
        raise AssertionError("learner-grouped split leaked learners across partitions")
    return (
        train_index,
        test_index,
        {
            "method": "GroupShuffleSplit by learner_id",
            "test_size_requested": float(test_size),
            "random_seed": int(seed),
            "train_learners": len(train_groups),
            "test_learners": len(test_groups),
            "learner_overlap": len(overlap),
        },
    )


def evaluate_binary_outcome(model, features, truth) -> dict[str, Any]:
    truth = np.asarray(truth, dtype=int)
    if truth.size == 0 or set(np.unique(truth)) - {0, 1}:
        raise ValueError("truth must be a non-empty binary target")
    predictions = np.asarray(model.predict(features), dtype=int)
    probabilities = np.asarray(model.predict_proba(features), dtype=float)[:, 1]
    has_both_classes = len(np.unique(truth)) == 2
    macro = precision_recall_fscore_support(
        truth, predictions, average="macro", zero_division=0
    )
    weighted = precision_recall_fscore_support(
        truth, predictions, average="weighted", zero_division=0
    )
    return {
        "rows": int(len(truth)),
        "positive_rate": float(truth.mean()),
        "accuracy": float(accuracy_score(truth, predictions)),
        "precision_correct": float(
            precision_score(truth, predictions, zero_division=0)
        ),
        "recall_correct": float(recall_score(truth, predictions, zero_division=0)),
        "f1_correct": float(f1_score(truth, predictions, zero_division=0)),
        "macro_precision": float(macro[0]),
        "macro_recall": float(macro[1]),
        "macro_f1": float(macro[2]),
        "weighted_precision": float(weighted[0]),
        "weighted_recall": float(weighted[1]),
        "weighted_f1": float(weighted[2]),
        "roc_auc": float(roc_auc_score(truth, probabilities))
        if has_both_classes
        else None,
        "pr_auc": float(average_precision_score(truth, probabilities))
        if has_both_classes
        else None,
        "brier_score": float(brier_score_loss(truth, probabilities)),
        "confusion_matrix": confusion_matrix(
            truth, predictions, labels=[0, 1]
        ).tolist(),
        "classification_report": classification_report(
            truth,
            predictions,
            labels=[0, 1],
            target_names=["incorrect", "correct"],
            output_dict=True,
            zero_division=0,
        ),
        "predictions": predictions,
        "probabilities": probabilities,
    }
