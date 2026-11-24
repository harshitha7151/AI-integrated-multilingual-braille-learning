from datetime import datetime, timezone
import unittest

from adaptive_mastery import BKTParameters
from benchmark_adaptive import (
    bkt_prequential_predictions,
    build_component_rows,
    classification_metrics,
)


class AdaptiveBenchmarkTests(unittest.TestCase):
    def test_bkt_is_prequential_and_state_isolated_by_learner_and_skill(self):
        timestamp = datetime(2026, 1, 1, tzinfo=timezone.utc)
        rows = [
            {"learner_id": "one", "skill_id": "a", "outcome": "incorrect",
             "created_at": timestamp, "attempt_id": 1},
            {"learner_id": "one", "skill_id": "a", "outcome": "correct",
             "created_at": timestamp, "attempt_id": 2},
            {"learner_id": "two", "skill_id": "a", "outcome": "correct",
             "created_at": timestamp, "attempt_id": 1},
        ]
        actual, predicted, probabilities = bkt_prequential_predictions(
            rows, BKTParameters()
        )
        self.assertEqual(actual, [1, 0, 0])
        self.assertEqual(len(predicted), 3)
        self.assertEqual(len(probabilities), 3)
        # A fresh learner starts from the same prior rather than inheriting
        # another learner's posterior.
        self.assertEqual(probabilities[0], probabilities[2])

    def test_binary_metrics_use_incorrect_as_positive_and_report_both_classes(self):
        result = classification_metrics([1, 1, 0, 0], [1, 0, 0, 0])
        self.assertEqual(result["sample_count"], 4)
        self.assertEqual(result["confusion_matrix"], [[2, 0], [1, 1]])
        self.assertAlmostEqual(result["accuracy"], 0.75)
        self.assertAlmostEqual(result["precision"], 1.0)
        self.assertAlmostEqual(result["recall"], 0.5)
        self.assertAlmostEqual(result["f1"], 2 / 3)
        self.assertIn("Incorrect / error", result["classification_report"])

    def test_empty_labels_do_not_become_fabricated_zero_metrics(self):
        self.assertIsNone(classification_metrics([], []))
        rows = build_component_rows(None, None)
        bkt = next(row for row in rows if row["component"].startswith("BKT"))
        self.assertEqual(bkt["status"], "unavailable")
        self.assertIsNone(bkt["accuracy"])


if __name__ == "__main__":
    unittest.main()
