import importlib.util
from pathlib import Path

import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / "data" / "authored" / "resonant_tutor_intents_authored.csv"
SCRIPT = ROOT / "experiments" / "resonant_intents" / "run_authored_experiment.py"


def test_authored_intent_examples_have_explicit_provenance_and_fixed_split_counts():
    rows = pd.read_csv(CSV, keep_default_na=False)
    assert set(rows["data_origin"]) == {"assistant_authored"}
    assert set(rows["language"]) == {"English"}
    for _, group in rows.groupby("intent"):
        assert group["split"].value_counts().to_dict() == {
            "train": 5, "validation": 1, "test": 2
        }


def test_authored_experiment_executes_without_exporting_a_model_artifact(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("authored_experiment", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(module, "REPORT_DIR", tmp_path)
    results = module.run()
    assert results["data_origin"] == "assistant_authored_only"
    assert len(results["models"]) == 3
    assert (tmp_path / "REPORT.md").is_file()
    assert not list(tmp_path.glob("*.joblib"))
