import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "experiments" / "retrieval"))

from run_evaluation import _metrics


def test_retrieval_metrics_use_first_gold_rank():
    cases = [
        ({"language": "English", "gold_id": "doc-a"}, ["doc-a", "doc-b"]),
        ({"language": "Hindi", "gold_id": "doc-c"}, ["doc-b", "doc-c"]),
        ({"language": "Kannada", "gold_id": "doc-d"}, ["doc-a", "doc-b"]),
    ]
    scores = _metrics("unit", cases)
    assert scores["precision_at_1"] == 1 / 3
    assert scores["recall_at_5"] == 2 / 3
    assert scores["mean_reciprocal_rank"] == (1 + 0.5 + 0) / 3
