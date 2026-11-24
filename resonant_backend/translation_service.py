"""Replaceable translation boundary; Braille verification stays separate."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Protocol

import requests


class TranslationUnavailable(RuntimeError):
    """The configured translation provider did not return usable text."""


@dataclass(frozen=True)
class TranslationResult:
    original_text: str
    translated_text: str
    source_language: str
    target_language: str
    provider: str


class TranslationProvider(Protocol):
    name: str

    def translate(
        self, text: str, *, source_language: str, target_language: str,
    ) -> TranslationResult: ...


class OllamaTranslationProvider:
    """Local model adapter. It translates text only and never chooses Braille."""

    name = "ollama_local"

    def __init__(
        self,
        *,
        endpoint: str,
        model: str,
        timeout_seconds: int,
        post: Callable = requests.post,
    ):
        self.endpoint = endpoint
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.post = post

    def translate(
        self, text: str, *, source_language: str, target_language: str,
    ) -> TranslationResult:
        if not text.strip() or len(text) > 500:
            raise ValueError("translation_text_invalid")
        try:
            response = self.post(
                self.endpoint,
                json={
                    "model": self.model,
                    "messages": [{
                        "role": "user",
                        "content": (
                            f"Translate the following text from {source_language} "
                            f"to {target_language}. Return only the translated "
                            "text in the target language's normal script. Do not "
                            "explain, transliterate, or provide any Braille pattern.\n"
                            f"Text: {text}"
                        ),
                    }],
                    "stream": False,
                },
                timeout=(3, self.timeout_seconds),
            )
            response.raise_for_status()
            translated = response.json().get("message", {}).get("content", "")
        except (requests.RequestException, ValueError, AttributeError, TypeError) as error:
            raise TranslationUnavailable("translation_provider_unavailable") from error
        translated = translated.strip() if isinstance(translated, str) else ""
        if not translated or len(translated) > 500:
            raise TranslationUnavailable("translation_provider_empty_or_invalid")
        return TranslationResult(
            original_text=text,
            translated_text=translated,
            source_language=source_language,
            target_language=target_language,
            provider=self.name,
        )
