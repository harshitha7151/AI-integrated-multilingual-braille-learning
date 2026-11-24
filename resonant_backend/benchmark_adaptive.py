"""Read-only, outcome-grounded benchmark for Resonant adaptive components.

Run from resonant_backend with ``py -3.12 benchmark_adaptive.py``.  The module
never writes to PostgreSQL.  It scores only predictions paired with later
observed outcomes and records unsupported metrics as unavailable.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
import sys
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)

from adaptive_mastery import BKTParameters, update_mastery
from database import get_connection


POSITIVE_LABEL = 1  # An incorrect next response / observed error.
CLASS_LABELS = [0, 1]
CLASS_NAMES = ["Correct / no error", "Incorrect / error"]
DEFAULT_OUTPUT = Path(__file__).resolve().parent / "benchmark_results"


COMPONENTS = {
    "BKT next-response prediction": (
        "Prequential classification of the next valid response using only prior "
        "same-learner/same-skill responses and configured BKT parameters."
    ),
    "Qualified Resonant ML next-response model": (
        "Resolved predictions from valid qualified-model rows, thresholded at "
        "P(incorrect) >= 0.5; positive class is incorrect."
    ),
    "Error classification": (
        "Deterministic response-difference taxonomy; no independent human-labeled "
        "category set is stored for classifier evaluation."
    ),
    "Forgetting-risk estimation": (
        "Heuristic exponential-decay estimate; no independently labeled forgetting "
        "or later-recall outcome is paired with risk estimates."
    ),
    "Information-gain selection": (
        "Ranking signal; classification metrics do not evaluate ranking quality, "
        "and counterfactual relevance labels are not stored."
    ),
    "LinUCB contextual bandit": (
        "Contextual ranking with persisted binary outcomes; policy value needs a "
        "logged exploration/propensity or counterfactual comparison design."
    ),
    "Adaptive difficulty": (
        "Rule-based difficulty choice; no independent target difficulty labels or "
        "validated outcome benchmark is stored."
    ),
    "Constraint-based assessment selection": (
        "Selects and validates curriculum-bounded content; validation status is not "
        "an independent ground-truth label for selection quality."
    ),
}


def _table_exists(connection: Any, qualified_name: str) -> bool:
    schema, table = qualified_name.split(".", 1)
    row = connection.execute(
        "SELECT to_regclass(%s) AS relation", (f"{schema}.{table}",)
    ).fetchone()
    return bool(row and row["relation"])


def load_benchmark_data() -> tuple[list[dict], list[dict], str]:
    """Load minimal labels/predictions from a read-only database transaction."""
    practice: list[dict] = []
    assessment: list[dict] = []
    model_predictions: list[dict] = []
    try:
        with get_connection() as connection:
            connection.execute("SET TRANSACTION READ ONLY")
            has_practice = _table_exists(connection, "resonant.practice_attempts")
            has_assessment_attempts = _table_exists(
                connection, "resonant.assessment_attempts"
            ) and _table_exists(connection, "resonant.assessment_questions")
            has_predictions = _table_exists(connection, "resonant.ml_predictions")

            if has_practice:
                practice = connection.execute(
                    """
                    SELECT learner_id, skill_id, outcome, created_at, attempt_id
                    FROM resonant.practice_attempts
                    WHERE outcome IN ('correct', 'incorrect')
                      AND input_status = 'valid'
                    ORDER BY created_at, attempt_id
                    """
                ).fetchall()
            if has_assessment_attempts:
                assessment = connection.execute(
                    """
                    SELECT a.learner_id, q.skill_id,
                           CASE WHEN a.correct THEN 'correct' ELSE 'incorrect' END AS outcome,
                           a.created_at, a.attempt_id
                    FROM resonant.assessment_attempts AS a
                    JOIN resonant.assessment_questions AS q
                      ON q.assessment_id = a.assessment_id
                     AND q.question_id = a.question_id
                    WHERE a.counts_for_learning = TRUE
                      AND a.input_status = 'valid'
                    ORDER BY a.created_at, a.attempt_id
                    """
                ).fetchall()
            if has_predictions:
                model_predictions = connection.execute(
                    """
                    SELECT probability_incorrect, observed_incorrect
                    FROM resonant.ml_predictions
                    WHERE prediction_source = 'qualified_model'
                      AND validity_status = 'valid'
                      AND observed_incorrect IS NOT NULL
                      AND probability_incorrect IS NOT NULL
                    ORDER BY predicted_at, prediction_id
                    """
                ).fetchall()
        return (
            [dict(row) for row in practice] + [dict(row) for row in assessment],
            [dict(row) for row in model_predictions],
            "connected; read-only transaction",
        )
    except Exception as error:  # Keep connection strings/details out of reports.
        if isinstance(error, RuntimeError) and "RESONANT_DATABASE_URL" in str(error):
            status = "unavailable: RESONANT_DATABASE_URL is not configured"
        else:
            status = f"unavailable: database read failed ({type(error).__name__})"
        return [], [], status


def bkt_prequential_predictions(
    observations: list[dict], parameters: BKTParameters
) -> tuple[list[int], list[int], list[float]]:
    """Predict each response before updating BKT with that response.

    State is isolated by learner and skill.  It is an outcome-prediction
    benchmark, not an evaluation of the latent mastery probability itself.
    """
    state: dict[tuple[str, str], float] = defaultdict(
        lambda: parameters.prior_knowledge
    )
    actual: list[int] = []
    predicted: list[int] = []
    p_incorrect_values: list[float] = []
    ordered = sorted(
        observations,
        key=lambda row: (
            row.get("created_at") or datetime.min.replace(tzinfo=timezone.utc),
            str(row.get("learner_id", "")),
            str(row.get("skill_id", "")),
            int(row.get("attempt_id") or 0),
        ),
    )
    for row in ordered:
        outcome = row.get("outcome")
        learner = row.get("learner_id")
        skill = row.get("skill_id")
        if outcome not in {"correct", "incorrect"} or learner is None or not skill:
            continue
        key = (str(learner), str(skill))
        mastery_before = state[key]
        probability_correct = (
            mastery_before * (1.0 - parameters.slip_probability)
            + (1.0 - mastery_before) * parameters.guess_probability
        )
        probability_incorrect = 1.0 - probability_correct
        actual_incorrect = int(outcome == "incorrect")
        actual.append(actual_incorrect)
        predicted.append(int(probability_incorrect >= 0.5))
        p_incorrect_values.append(probability_incorrect)
        state[key] = update_mastery(
            mastery_before, outcome == "correct", parameters
        )
    return actual, predicted, p_incorrect_values


def classification_metrics(
    actual: list[int], predicted: list[int]
) -> dict[str, Any] | None:
    if not actual:
        return None
    return {
        "sample_count": len(actual),
        "accuracy": float(accuracy_score(actual, predicted)),
        "precision": float(
            precision_score(actual, predicted, pos_label=POSITIVE_LABEL, zero_division=0)
        ),
        "recall": float(
            recall_score(actual, predicted, pos_label=POSITIVE_LABEL, zero_division=0)
        ),
        "f1": float(
            f1_score(actual, predicted, pos_label=POSITIVE_LABEL, zero_division=0)
        ),
        "confusion_matrix": confusion_matrix(
            actual, predicted, labels=CLASS_LABELS
        ).tolist(),
        "classification_report": classification_report(
            actual,
            predicted,
            labels=CLASS_LABELS,
            target_names=CLASS_NAMES,
            output_dict=True,
            zero_division=0,
        ),
    }


def _format_metric(value: Any) -> str:
    return "N/A" if value is None or pd.isna(value) else f"{float(value):.4f}"


def build_component_rows(
    bkt_result: dict | None, model_result: dict | None
) -> list[dict]:
    evaluable = {
        "BKT next-response prediction": bkt_result,
        "Qualified Resonant ML next-response model": model_result,
    }
    rows = []
    for component, method in COMPONENTS.items():
        result = evaluable.get(component)
        if result is None:
            reason = (
                "No eligible outcome records were available."
                if component in evaluable
                else method
            )
            rows.append({
                "component": component,
                "status": "unavailable",
                "sample_count": 0,
                "positive_class": "incorrect",
                "threshold": 0.5 if component in evaluable else None,
                "accuracy": None,
                "precision": None,
                "recall": None,
                "f1": None,
                "method_or_limitation": reason,
            })
        else:
            rows.append({
                "component": component,
                "status": "evaluated",
                "sample_count": result["sample_count"],
                "positive_class": "incorrect",
                "threshold": 0.5,
                "accuracy": result["accuracy"],
                "precision": result["precision"],
                "recall": result["recall"],
                "f1": result["f1"],
                "method_or_limitation": method,
            })
    return rows


def _plot_metrics(rows: list[dict], output: Path) -> None:
    frame = pd.DataFrame(rows)
    available = frame[frame["status"] == "evaluated"]
    fig, ax = plt.subplots(figsize=(10, 5.5))
    if available.empty:
        ax.text(0.5, 0.55, "No eligible labeled predictions in the database",
                ha="center", va="center", fontsize=13)
        ax.text(0.5, 0.43, "Metrics are unavailable; no zero scores are inferred.",
                ha="center", va="center", fontsize=10)
        ax.set_axis_off()
    else:
        columns = ["accuracy", "precision", "recall", "f1"]
        values = available[columns].to_numpy(dtype=float)
        x = np.arange(len(columns))
        width = 0.8 / len(available)
        for index, (_, row) in enumerate(available.iterrows()):
            ax.bar(x - 0.4 + width / 2 + index * width, values[index], width,
                   label=f"{row['component']} (n={row['sample_count']})")
        ax.set_xticks(x, ["Accuracy", "Precision", "Recall", "F1-score"])
        ax.set_ylim(0, 1.05)
        ax.set_ylabel("Score")
        ax.legend(loc="best", fontsize=8)
        ax.grid(axis="y", alpha=0.2)
    ax.set_title("Resonant outcome-prediction metrics (positive class: incorrect)")
    fig.tight_layout()
    fig.savefig(output, dpi=180)
    plt.close(fig)


def _plot_confusion_matrices(
    results: dict[str, dict | None], output: Path
) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(12, 4.6))
    entries = [
        ("Error classification", None),
        ("BKT next-response", results.get("bkt")),
        ("Qualified ML next-response", results.get("model")),
    ]
    for ax, (title, result) in zip(axes, entries):
        ax.set_title(title, fontsize=10)
        if result is None:
            ax.text(0.5, 0.5,
                    "Unavailable\n(no independent labeled set)" if title.startswith("Error")
                    else "Unavailable\n(no resolved predictions)",
                    ha="center", va="center", wrap=True)
            ax.set_axis_off()
            continue
        matrix = np.asarray(result["confusion_matrix"])
        ax.imshow(matrix, cmap="Blues")
        for (row, column), value in np.ndenumerate(matrix):
            ax.text(column, row, str(value), ha="center", va="center")
        ax.set_xticks([0, 1], ["Pred. correct", "Pred. incorrect"], rotation=20)
        ax.set_yticks([0, 1], ["Actual correct", "Actual incorrect"])
    fig.suptitle("Confusion matrices; error taxonomy has no independent ground truth")
    fig.tight_layout()
    fig.savefig(output, dpi=180)
    plt.close(fig)


def _plot_metric_table(rows: list[dict], output: Path) -> None:
    headers = ["Component", "n", "Accuracy", "Precision", "Recall", "F1", "Status"]
    cells = [[
        row["component"],
        str(row["sample_count"]),
        _format_metric(row["accuracy"]),
        _format_metric(row["precision"]),
        _format_metric(row["recall"]),
        _format_metric(row["f1"]),
        row["status"],
    ] for row in rows]
    fig, ax = plt.subplots(figsize=(14, max(4, 0.48 * len(rows) + 1.5)))
    ax.axis("off")
    table = ax.table(cellText=cells, colLabels=headers, loc="center", cellLoc="left")
    table.auto_set_font_size(False)
    table.set_fontsize(8)
    table.scale(1, 1.45)
    ax.set_title("Component-wise metric availability and results", pad=18)
    fig.tight_layout()
    fig.savefig(output, dpi=180, bbox_inches="tight")
    plt.close(fig)


def _classification_report_rows(name: str, result: dict | None) -> list[dict]:
    if result is None:
        return [{"component": name, "class": "unavailable", "precision": None,
                 "recall": None, "f1_score": None, "support": 0}]
    return [
        {"component": name, "class": class_name,
         "precision": values.get("precision"),
         "recall": values.get("recall"),
         "f1_score": values.get("f1-score"),
         "support": values.get("support")}
        for class_name, values in result["classification_report"].items()
        if isinstance(values, dict)
    ]


def _write_report(
    path: Path,
    *,
    rows: list[dict],
    results: dict[str, dict | None],
    data_status: str,
    bkt_parameters: BKTParameters,
) -> None:
    table = pd.DataFrame(rows)
    display = table[["component", "status", "sample_count", "accuracy", "precision", "recall", "f1"]].copy()
    for metric in ("accuracy", "precision", "recall", "f1"):
        display[metric] = display[metric].map(_format_metric)
    lines = [
        "# Resonant Adaptive AIML Benchmark",
        "",
        f"Generated (UTC): {datetime.now(timezone.utc).isoformat()}",
        f"Database status: {data_status}",
        "Database access: read-only transaction; no schema or row changes performed.",
        "",
        "## Results",
        "",
        "| Component | Status | N | Accuracy | Precision | Recall | F1 |",
        "|---|---|---:|---:|---:|---:|---:|",
        *[
            "| " + " | ".join(str(value).replace("|", "\\|") for value in row) + " |"
            for row in display.itertuples(index=False, name=None)
        ],
        "",
        "## Methods and interpretation",
        "",
        "- Positive class is an incorrect response. Binary predictions use a predeclared threshold of 0.5.",
        "- Precision = TP/(TP+FP), recall = TP/(TP+FN), F1 = harmonic mean of precision and recall; accuracy = (TP+TN)/N. Undefined precision/recall edge cases use sklearn zero_division=0; read class support alongside the scores.",
        "- BKT is evaluated prequentially: each correctness probability is computed before incorporating that response, with state isolated by learner and skill. The state is then updated using the existing configured BKT transition.",
        f"- BKT parameters: prior={bkt_parameters.prior_knowledge}, learning={bkt_parameters.learning_probability}, guess={bkt_parameters.guess_probability}, slip={bkt_parameters.slip_probability}.",
        "- The qualified ML model is evaluated only on valid, resolved persisted predictions paired with observed outcomes. Its probability is thresholded at 0.5; fallback predictions are excluded.",
        "- Mastery estimates are latent-state probabilities, not accuracy labels. This benchmark does not claim mastery probability calibration or mastery classification accuracy.",
        "- Error labels are produced by deterministic response analysis; no independent human annotation is persisted, so classifier accuracy/precision/recall/F1 and its confusion matrix are unavailable.",
        "- Information gain is a ranking signal. LinUCB uses observed binary rewards, but no logged propensities/randomized control or counterfactual outcomes support an unbiased policy-value comparison. Classification metrics are not applied to either ranking policy.",
        "- Forgetting risk is an exponential-decay heuristic without an independent forgetting/recall label. Difficulty and constraint selection have no independent target labels. Their classification metrics are unavailable.",
        "- The assessment selection component selects existing curriculum content subject to validation; this is not arbitrary assessment generation.",
        "",
        "## Limitations",
        "",
        "Results are descriptive for observed attempts/predictions only. They do not establish causal learning gains, generalization to new learners, or statistical significance. Class counts and metrics should be interpreted with each component's sample size and class distribution.",
        "",
        "## Files",
        "",
        "- `component_metrics.csv`: component-wise metrics, sample sizes, statuses, methods and unavailability explanations.",
        "- `classification_report.csv`: per-class precision, recall, F1 and support for evaluable classifiers; explicit unavailable rows otherwise.",
        "- `accuracy_precision_recall_f1.png`: chart of evaluable classifiers or an unavailable-state message.",
        "- `confusion_matrices.png`: error-classification unavailable panel plus matrices for available outcome classifiers.",
        "- `component_metrics_table.png`: visual metric/status table.",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_benchmark(output: Path = DEFAULT_OUTPUT) -> dict[str, Any]:
    output.mkdir(parents=True, exist_ok=True)
    observations, model_rows, data_status = load_benchmark_data()
    parameters = BKTParameters.from_environment()

    bkt_actual, bkt_predicted, _ = bkt_prequential_predictions(observations, parameters)
    bkt_result = classification_metrics(bkt_actual, bkt_predicted)

    ml_actual = [int(row["observed_incorrect"]) for row in model_rows]
    ml_predicted = [
        int(float(row["probability_incorrect"]) >= 0.5) for row in model_rows
    ]
    ml_result = classification_metrics(ml_actual, ml_predicted)

    rows = build_component_rows(bkt_result, ml_result)
    metric_frame = pd.DataFrame(rows)
    metric_frame = metric_frame.astype(object).where(pd.notna(metric_frame), "N/A")
    metric_frame.to_csv(output / "component_metrics.csv", index=False)
    reports = (
        _classification_report_rows("BKT next-response prediction", bkt_result)
        + _classification_report_rows("Qualified Resonant ML next-response model", ml_result)
        + _classification_report_rows("Error classification", None)
    )
    report_frame = pd.DataFrame(reports)
    report_frame = report_frame.astype(object).where(pd.notna(report_frame), "N/A")
    report_frame.to_csv(output / "classification_report.csv", index=False)
    _plot_metrics(rows, output / "accuracy_precision_recall_f1.png")
    _plot_confusion_matrices(
        {"bkt": bkt_result, "model": ml_result},
        output / "confusion_matrices.png",
    )
    _plot_metric_table(rows, output / "component_metrics_table.png")
    _write_report(
        output / "benchmark_report.md",
        rows=rows,
        results={"bkt": bkt_result, "model": ml_result},
        data_status=data_status,
        bkt_parameters=parameters,
    )
    return {
        "output": output,
        "database_status": data_status,
        "bkt_sample_count": len(bkt_actual),
        "qualified_model_sample_count": len(ml_actual),
        "metrics": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT,
        help="Output directory (default: resonant_backend/benchmark_results)",
    )
    args = parser.parse_args()
    try:
        result = run_benchmark(args.output)
    except Exception as error:
        # Do not reveal environment secrets or database connection strings.
        print(f"Benchmark failed: {type(error).__name__}", file=sys.stderr)
        return 1
    print(f"Database: {result['database_status']}")
    print(f"BKT outcome samples: {result['bkt_sample_count']}")
    print(f"Qualified model outcome samples: {result['qualified_model_sample_count']}")
    print(f"Artifacts: {result['output'].resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
