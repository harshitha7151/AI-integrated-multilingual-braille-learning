from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from adaptive_mastery import BKTParameters
from adaptive_policy import (
    binary_entropy,
    contextual_bandit_ranking,
    expected_information_gain,
    forgetting_risk,
    rank_supported_skills,
)


class AdaptivePolicyTests(unittest.TestCase):
    def test_information_gain_is_entropy_reduction_and_peaks_away_from_edges(self):
        params = BKTParameters()
        self.assertEqual(binary_entropy(0), 0)
        self.assertEqual(binary_entropy(1), 0)
        self.assertGreater(expected_information_gain(0.5, params), 0)
        self.assertLess(
            expected_information_gain(0.01, params),
            expected_information_gain(0.5, params),
        )

    def test_forgetting_risk_grows_with_elapsed_time_but_never_claims_historyless_risk(self):
        early = forgetting_risk(0.8, 0)
        later = forgetting_risk(0.8, 28)
        self.assertAlmostEqual(early, 0.2)
        self.assertGreater(later, early)
        with self.assertRaises(ValueError):
            forgetting_risk(0.8, -1)

    def test_ranker_prefers_due_repeated_error_within_only_given_candidates(self):
        now = datetime.now(timezone.utc)
        ranked = rank_supported_skills(
            ["taught-a", "taught-b"],
            [
                {
                    "skill_id": "taught-a", "mastery": 0.25,
                    "attempts": 5, "updated_at": now - timedelta(days=1),
                    "next_review_at": now + timedelta(days=1),
                },
                {
                    "skill_id": "taught-b", "mastery": 0.75,
                    "attempts": 4, "updated_at": now - timedelta(days=30),
                    "next_review_at": now - timedelta(days=1),
                },
            ],
            [{"skill_id": "taught-b", "error_count": 3}],
            now=now,
        )
        self.assertEqual(ranked[0]["skill_id"], "taught-b")
        self.assertTrue(ranked[0]["review_due"])
        self.assertEqual({item["skill_id"] for item in ranked}, {"taught-a", "taught-b"})

    def test_unpracticed_skill_has_no_forgetting_estimate_and_ranking_is_stable(self):
        candidates = ["taught-b", "taught-a"]
        first = rank_supported_skills(candidates, [], [], now=datetime(2026, 1, 1, tzinfo=timezone.utc))
        again = rank_supported_skills(candidates, [], [], now=datetime(2026, 1, 1, tzinfo=timezone.utc))
        self.assertEqual(first, again)
        self.assertEqual(first[0]["forgetting_risk_estimate"], None)
        self.assertEqual({item["skill_id"] for item in first}, set(candidates))

    def test_contextual_bandit_uses_only_persisted_rewards_and_has_cold_start(self):
        candidates = [
            {"skill_id": "a", "mastery": .4, "score": .8,
             "information_gain_bits": .2, "forgetting_risk_estimate": .1,
             "review_due": False, "error_count": 1},
            {"skill_id": "b", "mastery": .4, "score": .7,
             "information_gain_bits": .2, "forgetting_risk_estimate": .1,
             "review_due": False, "error_count": 1},
        ]
        self.assertIsNone(contextual_bandit_ranking(candidates, []))
        decisions = [
            {
                "succeeded": True,
                "evidence": {
                    "eligible_skill_scores": candidates,
                    "selected_skill_for_next_exercise": candidates[0],
                },
            }
            for _ in range(5)
        ]
        first = contextual_bandit_ranking(candidates, decisions)
        second = contextual_bandit_ranking(candidates, decisions)
        self.assertEqual(first, second)
        self.assertEqual(first[0]["skill_id"], "a")
        self.assertEqual(first[0]["bandit_observation_count"], 5)


if __name__ == "__main__":
    unittest.main()
