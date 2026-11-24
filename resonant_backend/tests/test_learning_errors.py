import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault(
    "RESONANT_JWT_SECRET",
    "resonant-test-only-jwt-secret-never-use-in-production",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from learning_error_service import analyze_response


class LearningErrorTests(unittest.TestCase):
    def test_missing_and_extra_dots_are_recorded_exactly(self):
        result = analyze_response({"cells": [3]}, {"cells": [9]})
        self.assertEqual(result["category"], "dot_substitution")
        self.assertEqual(result["missing_dots"], [{"cell_index": 0, "dots": [2]}])
        self.assertEqual(result["extra_dots"], [{"cell_index": 0, "dots": [4]}])
        self.assertTrue(result["counts_for_learning"])

    def test_multiple_dot_error_is_distinct_from_one_dot_difference(self):
        result = analyze_response({"cells": [7]}, {"cells": [56]})
        self.assertEqual(result["category"], "multiple_dot_error")
        self.assertGreater(
            sum(len(item["dots"]) for item in result["missing_dots"] + result["extra_dots"]),
            2,
        )

    def test_technical_failure_never_counts_as_a_learner_error(self):
        result = analyze_response(
            {"cells": [3]},
            {},
            input_status="technical_failure",
            technical_failure_code="pointer_cancelled",
        )
        self.assertEqual(result["category"], "technical_input_failure")
        self.assertFalse(result["counts_for_learning"])
        self.assertEqual(result["technical_failure_code"], "pointer_cancelled")

    def test_invalid_technical_status_requires_a_bounded_reason(self):
        with self.assertRaisesRegex(ValueError, "technical_failure_code_required"):
            analyze_response(
                {"cells": [3]},
                {},
                input_status="technical_failure",
            )


if __name__ == "__main__":
    unittest.main()

