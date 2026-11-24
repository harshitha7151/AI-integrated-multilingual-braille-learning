import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from translation_service import (
    OllamaTranslationProvider,
    TranslationUnavailable,
)


class TranslationServiceTests(unittest.TestCase):
    def test_provider_preserves_original_and_requested_language_metadata(self):
        class Response:
            def raise_for_status(self):
                pass

            def json(self):
                return {"message": {"content": "ಹಲ"}}

        post = Mock(return_value=Response())
        result = OllamaTranslationProvider(
            endpoint="http://127.0.0.1:11434/api/chat",
            model="configured-local-model",
            timeout_seconds=9,
            post=post,
        ).translate("hello", source_language="English", target_language="Kannada")

        self.assertEqual(result.original_text, "hello")
        self.assertEqual(result.translated_text, "ಹಲ")
        self.assertEqual(result.source_language, "English")
        self.assertEqual(result.target_language, "Kannada")
        self.assertEqual(result.provider, "ollama_local")
        prompt = post.call_args.kwargs["json"]["messages"][0]["content"]
        self.assertIn("Do not", prompt)
        self.assertIn("Braille pattern", prompt)

    def test_provider_failure_is_explicit(self):
        provider = OllamaTranslationProvider(
            endpoint="http://127.0.0.1:11434/api/chat",
            model="configured-local-model",
            timeout_seconds=9,
            post=lambda *args, **kwargs: (_ for _ in ()).throw(requests.Timeout()),
        )
        with self.assertRaisesRegex(TranslationUnavailable, "translation_provider_unavailable"):
            provider.translate("hello", source_language="English", target_language="Hindi")

    def test_empty_input_is_rejected_before_provider_call(self):
        provider = OllamaTranslationProvider(
            endpoint="http://127.0.0.1:11434/api/chat",
            model="configured-local-model",
            timeout_seconds=9,
            post=lambda *args, **kwargs: self.fail("provider should not be called"),
        )
        with self.assertRaisesRegex(ValueError, "translation_text_invalid"):
            provider.translate(" ", source_language="English", target_language="Hindi")


if __name__ == "__main__":
    unittest.main()
