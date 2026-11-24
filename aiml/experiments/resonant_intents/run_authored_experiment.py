"""Smoke-test baseline for assistant-authored Resonant Tutor intent examples.

Run from aiml/: python experiments/resonant_intents/run_authored_experiment.py
Results are not generalization evidence and are not production model artifacts.
"""
import json
from pathlib import Path
import sys

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))
from evaluation.classification import evaluate_classifier
from models.intent_baselines import build_intent_models

DATA = ROOT / "data" / "authored" / "resonant_tutor_intents_authored.csv"
REPORT_DIR = ROOT / "reports" / "resonant_intents"
EXPECTED_COUNTS = {"train": 5, "validation": 1, "test": 2}


def run():
    frame = pd.read_csv(DATA, keep_default_na=False)
    required = {"text", "intent", "language", "split", "data_origin", "authoring_note"}
    if not required.issubset(frame.columns) or frame.empty:
        raise ValueError("authored intent file is empty or missing required columns")
    if set(frame["data_origin"]) != {"assistant_authored"}:
        raise ValueError("only explicitly assistant-authored examples are allowed")
    if set(frame["language"]) != {"English"}:
        raise ValueError("this initial authored experiment supports English examples only")
    if frame["text"].str.strip().eq("").any() or frame.duplicated(["text", "intent"]).any():
        raise ValueError("empty or duplicate authored examples found")
    labels = sorted(frame["intent"].unique())
    for label, group in frame.groupby("intent"):
        if group["split"].value_counts().to_dict() != EXPECTED_COUNTS:
            raise ValueError(f"unexpected split counts for {label}")
    splits = {name: frame[frame["split"] == name] for name in EXPECTED_COUNTS}
    if set(splits["train"]["intent"]) != set(labels):
        raise ValueError("each intent must appear in training")

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    results = {
        "dataset": str(DATA.relative_to(ROOT)),
        "data_origin": "assistant_authored_only",
        "rows": len(frame),
        "languages": sorted(frame["language"].unique()),
        "class_counts": frame["intent"].value_counts().sort_index().to_dict(),
        "split_counts_per_class": EXPECTED_COUNTS,
        "limitations": [
            "All examples were authored by the same assistant for code demonstration.",
            "No examples are real learner queries and no educator/community review is claimed.",
            "One validation and two test examples per class are far too few for stable metrics.",
            "Results are a pipeline smoke test only; no trained artifact is exported.",
            "Intent labels never supply or validate Braille cell values.",
        ],
        "models": {},
    }
    for name, model in build_intent_models().items():
        model.fit(splits["train"]["text"], splits["train"]["intent"])
        model_results = {}
        for split_name in ("validation", "test"):
            part = splits[split_name]
            evaluation = evaluate_classifier(model, part["text"], part["intent"], labels)
            model_results[split_name] = {
                "accuracy": evaluation["accuracy"],
                "macro_f1": evaluation["macro_f1"],
                "predictions": evaluation["predictions"].tolist(),
                "truth": part["intent"].tolist(),
            }
        results["models"][name] = model_results
    (REPORT_DIR / "metrics.json").write_text(
        json.dumps(results, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    lines = [
        "# Resonant Tutor authored-intent pipeline smoke test", "",
        "**Not generalization evidence.** All examples are assistant-authored English demonstrations, not learner data. The fixed per-class split has only one validation and two test examples. No model artifact is produced and nothing is connected to FastAPI.",
        "", f"- Rows: {len(frame)} across {len(labels)} intents.",
        "- Split: five train, one validation, two test per category; split assignment is designed to test code paths, not estimate out-of-sample quality.",
        "- Label taxonomy: [RESONANT_INTENT_TAXONOMY.md](../../data/RESONANT_INTENT_TAXONOMY.md).",
        "", "| Model | Validation accuracy | Validation macro F1 | Test accuracy | Test macro F1 |", "|---|---:|---:|---:|---:|",
    ]
    for name, scores in results["models"].items():
        lines.append(
            f"| {name} | {scores['validation']['accuracy']:.3f} | {scores['validation']['macro_f1']:.3f} | {scores['test']['accuracy']:.3f} | {scores['test']['macro_f1']:.3f} |"
        )
    (REPORT_DIR / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return results


if __name__ == "__main__":
    print(json.dumps(run(), indent=2, ensure_ascii=False))
