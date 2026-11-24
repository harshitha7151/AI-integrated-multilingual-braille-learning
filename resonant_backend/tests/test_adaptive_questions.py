import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault(
    "RESONANT_JWT_SECRET",
    "resonant-test-only-jwt-secret-never-use-in-production",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from adaptive_question_service import select_adaptive_question


class AdaptiveQuestionTests(unittest.TestCase):
    def test_validated_question_varies_and_keeps_authoritative_answer(self):
        first = select_adaptive_question(
            learner_id="learner-1",
            skill_id="english-letter-a",
            lesson_id="letter-a",
            language="English",
            difficulty=2,
        )
        second = select_adaptive_question(
            learner_id="learner-1",
            skill_id="english-letter-a",
            lesson_id="letter-a",
            language="English",
            difficulty=2,
            recent_question_ids={first["question_id"]},
        )
        self.assertNotEqual(first["question_id"], second["question_id"])
        self.assertEqual(first["expected_response"], {"choice": "a", "cells": [1]})
        self.assertIn("a", first["options"])
        self.assertEqual(len(first["options"]), 3)

    def test_hindi_and_kannada_questions_use_verified_mapping_records(self):
        hindi = select_adaptive_question(
            learner_id="learner-1",
            skill_id="hi-bharati-अ",
            lesson_id="hi-char-अ",
            language="Hindi",
            difficulty=1,
        )
        kannada = select_adaptive_question(
            learner_id="learner-1",
            skill_id="kn-bharati-ಅ",
            lesson_id="kn-char-ಅ",
            language="Kannada",
            difficulty=1,
        )
        self.assertEqual(hindi["expected_response"]["cells"], [1])
        self.assertEqual(kannada["expected_response"]["cells"], [1])

    def test_invalid_ai_content_is_rejected_to_validated_fallback(self):
        question = select_adaptive_question(
            learner_id="learner-1",
            skill_id="english-letter-a",
            lesson_id="letter-a",
            language="English",
            difficulty=2,
            generated_candidate={
                "language": "English",
                "skill_id": "english-letter-a",
                "difficulty": 2,
                "question_text": "Choose the right letter for this pattern.",
                "options": ["a", "b"],
                "answer": "z",
            },
        )
        self.assertEqual(question["question_source"], "deterministic_fallback")
        self.assertEqual(question["answer"], "a")
        self.assertEqual(question["expected_response"]["cells"], [1])

    def test_prerequisite_or_unknown_skill_cannot_create_question(self):
        with self.assertRaisesRegex(ValueError, "validated_curriculum"):
            select_adaptive_question(
                learner_id="learner-1",
                skill_id="english-letter-z",
                lesson_id="letter-a",
                language="English",
                difficulty=1,
            )


if __name__ == "__main__":
    unittest.main()

