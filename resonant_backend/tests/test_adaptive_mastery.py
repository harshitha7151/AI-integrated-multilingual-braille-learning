import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from adaptive_mastery import (
    BKTParameters,
    review_interval_days,
    update_mastery,
)


class BayesianKnowledgeTracingTests(unittest.TestCase):
    def setUp(self):
        self.parameters = BKTParameters()

    def test_correct_answer_increases_mastery_estimate(self):
        updated = update_mastery(0.2, True, self.parameters)
        self.assertGreater(updated, 0.2)
        self.assertAlmostEqual(updated, 0.5858823529)

    def test_incorrect_answer_reduces_mastery_estimate(self):
        updated = update_mastery(0.7, False, self.parameters)
        self.assertLess(updated, 0.7)

    def test_repeated_responses_are_deterministic_and_accumulate(self):
        first = update_mastery(0.2, True, self.parameters)
        second = update_mastery(first, True, self.parameters)
        self.assertGreater(second, first)
        self.assertEqual(
            second,
            update_mastery(first, True, self.parameters),
        )

    def test_probability_boundaries_remain_finite(self):
        self.assertAlmostEqual(
            update_mastery(0.0, True, self.parameters), 0.12,
        )
        self.assertEqual(update_mastery(1.0, False, self.parameters), 1.0)
        with self.assertRaisesRegex(ValueError, "between 0 and 1"):
            update_mastery(1.1, True, self.parameters)

    def test_configuration_is_replaceable_through_environment(self):
        with patch.dict(os.environ, {
            "RESONANT_BKT_PRIOR": "0.35",
            "RESONANT_BKT_LEARN": "0.2",
            "RESONANT_BKT_GUESS": "0.25",
            "RESONANT_BKT_SLIP": "0.08",
        }, clear=False):
            parameters = BKTParameters.from_environment()
        self.assertEqual(parameters, BKTParameters(0.35, 0.2, 0.25, 0.08))

    def test_review_schedule_brings_errors_back_and_spaces_successes(self):
        self.assertEqual(review_interval_days(0.9, False), 0)
        self.assertEqual(review_interval_days(0.2, True), 1)
        self.assertEqual(review_interval_days(0.5, True), 3)
        self.assertEqual(review_interval_days(0.7, True), 7)
        self.assertEqual(review_interval_days(0.9, True), 14)


if __name__ == "__main__":
    unittest.main()
