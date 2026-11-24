import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from knowledge_base import retrieve_evidence


class RetrievalEvaluationTests(unittest.TestCase):
    def test_localized_intro_retrieval_is_language_scoped(self):
        cases = [
            ("ब्रेल क्या है?", "Hindi", "hindi-braille-intro"),
            ("ಆರು ಚುಕ್ಕೆಗಳ ವ್ಯವಸ್ಥೆ ಹೇಗೆ ಕೆಲಸ ಮಾಡುತ್ತದೆ?", "Kannada", "kannada-braille-intro"),
            ("Explain the six-dot Braille cell layout", "English", "english-six-dot-cell"),
        ]
        for question, language, expected in cases:
            with self.subTest(language=language):
                found = retrieve_evidence(question, language=language)
                self.assertTrue(found)
                self.assertEqual(found[0]["id"], expected)
                self.assertEqual(found[0].get("language", "English"), language)

    def test_existing_course_words_have_engine_generated_reading_practice(self):
        cases = [
            ("How do I read CAT?", "English", "english-word-CAT", "CAT"),
            ("कमल शब्द पढ़ने का अभ्यास", "Hindi", "hindi-word-कमल", "कमल"),
            ("ಮನೆ ಪದ ಓದುವ ಅಭ್ಯಾಸ", "Kannada", "kannada-word-ಮನೆ", "ಮನೆ"),
        ]
        for question, language, expected_id, target in cases:
            with self.subTest(language=language):
                found = retrieve_evidence(question, language=language)
                self.assertTrue(found)
                self.assertEqual(found[0]["id"], expected_id)
                self.assertEqual(found[0]["examples"][0]["text"], target)

    """Small deterministic retrieval set; this does not evaluate an LLM."""

    def test_reference_queries_retrieve_expected_scope_only(self):
        cases = [
            ("Explain the six-dot Braille cell layout", "english-six-dot-cell"),
            ("Why does letter B use that pattern?", "english-letter-b"),
            ("What does UEB say about contractions?", "resonant-english-scope"),
            ("Can you teach Hindi Bharati Braille?", "resonant-language-scope"),
            ("Explain the Braille pattern for C", "english-letter-c"),
        ]
        for question, expected in cases:
            with self.subTest(question=question):
                result = retrieve_evidence(question)
                self.assertEqual([item["id"] for item in result], [expected])

    def test_short_followup_resolves_from_immediately_available_user_history(self):
        result = retrieve_evidence(
            "Why?", history=[{"role": "user", "content": "Explain the six-dot Braille cell layout"}]
        )
        self.assertEqual([item["id"] for item in result], ["english-six-dot-cell"])

    def test_unrepresented_topic_does_not_get_invented_retrieval(self):
        result = retrieve_evidence("Explain music notation")
        self.assertEqual(result, [])


if __name__ == "__main__":
    unittest.main()
