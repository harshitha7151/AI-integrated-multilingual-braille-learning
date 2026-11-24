"""Validated adaptive question selection with optional constrained AI phrasing."""

from __future__ import annotations

import hashlib
import json
import os
from threading import Lock
from time import monotonic
from uuid import uuid4

from psycopg.types.json import Jsonb
import requests

from braille_mapping_registry import (
    HINDI_CURRICULUM_CHARACTERS,
    KANNADA_CURRICULUM_CHARACTERS,
    mapping_for_skill,
)


QUESTION_VERSION = "resonant-adaptive-question-bank-v1"
CURRICULUM_VERSION = "flutter-catalog-v1"
_ENGLISH = tuple("abcdefghijklmnopqrstuvwxyz")
_AI_CALLS: dict[str, float] = {}
_AI_LOCK = Lock()


def _pool(language: str) -> tuple[str, ...]:
    if language == "English":
        return _ENGLISH
    if language == "Hindi":
        return HINDI_CURRICULUM_CHARACTERS
    if language == "Kannada":
        return KANNADA_CURRICULUM_CHARACTERS
    raise ValueError("adaptive_question_language_invalid")


def _prompt(language: str, target: str, dots: list[int], variant: int) -> str:
    joined = ", ".join(map(str, dots))
    if language == "Hindi":
        prompts = (
            f"भारती ब्रेल बिंदु {joined} किस अक्षर को दर्शाते हैं?",
            f"बिंदु {joined} वाला सही हिंदी अक्षर चुनें।",
            f"सुनिश्चित करें: भारती ब्रेल में बिंदु {joined} किस वर्ण के हैं?",
        )
    elif language == "Kannada":
        prompts = (
            f"ಭಾರತಿ ಬ್ರೈಲ್ ಚುಕ್ಕೆಗಳು {joined} ಯಾವ ಅಕ್ಷರವನ್ನು ಸೂಚಿಸುತ್ತವೆ?",
            f"ಚುಕ್ಕೆಗಳು {joined} ಇರುವ ಸರಿಯಾದ ಕನ್ನಡ ಅಕ್ಷರವನ್ನು ಆರಿಸಿ.",
            f"ಪರಿಶೀಲಿಸಿ: ಭಾರತಿ ಬ್ರೈಲ್‌ನಲ್ಲಿ {joined} ಚುಕ್ಕೆಗಳು ಯಾವ ಅಕ್ಷರಕ್ಕೆ?",
        )
    else:
        prompts = (
            f"Which uncontracted English letter uses dots {joined}?",
            f"Choose the English letter represented by Braille dots {joined}.",
            f"Check the pattern: dots {joined} represent which English letter?",
        )
    return prompts[variant % len(prompts)]


def _stable_options(
    *,
    learner_id: str,
    target: str,
    language: str,
    difficulty: int,
    variant: int,
) -> list[str]:
    pool = [item for item in _pool(language) if item != target]
    digest = hashlib.sha256(
        f"{learner_id}|{language}|{target}|{difficulty}|{variant}".encode("utf-8")
    ).digest()
    start = int.from_bytes(digest[:4], "big") % len(pool)
    rotated = pool[start:] + pool[:start]
    option_count = min(len(pool) + 1, max(2, difficulty + 1))
    options = [target, *rotated[: option_count - 1]]
    rotation = digest[4] % len(options)
    return options[rotation:] + options[:rotation]


def _base_question(
    *,
    learner_id: str,
    skill_id: str,
    lesson_id: str,
    language: str,
    difficulty: int,
    recent_question_ids: set[str],
) -> dict:
    mapping = mapping_for_skill(skill_id, language)
    if mapping is None or mapping.get("lesson_id") != lesson_id:
        raise ValueError("adaptive_question_skill_not_in_validated_curriculum")
    if len(mapping["braille_cells"]) != 1:
        raise ValueError("adaptive_question_multicell_not_supported")
    target = mapping["character"]
    dots = mapping["dot_positions"][0]
    selected_variant = 0
    for variant in range(12):
        candidate_id = f"{QUESTION_VERSION}:{skill_id}:d{difficulty}:v{variant}"
        if candidate_id not in recent_question_ids:
            selected_variant = variant
            break
    question_id = f"{QUESTION_VERSION}:{skill_id}:d{difficulty}:v{selected_variant}"
    return {
        "question_instance_id": uuid4(),
        "question_id": question_id,
        "skill_id": skill_id,
        "lesson_id": lesson_id,
        "language": language,
        "difficulty": difficulty,
        "question_type": "letter_recognition",
        "question_text": _prompt(language, target, dots, selected_variant),
        "options": _stable_options(
            learner_id=learner_id,
            target=target,
            language=language,
            difficulty=difficulty,
            variant=selected_variant,
        ),
        "answer": target,
        "expected_response": {
            "choice": target,
            "cells": mapping["braille_cells"],
        },
        "question_source": "validated_bank",
        "question_version": QUESTION_VERSION,
        "mapping_version": mapping["mapping_version"],
        "curriculum_version": CURRICULUM_VERSION,
        "generation_model": None,
        "generation_failure": None,
        "validation_status": "validated",
    }


def validate_ai_candidate(candidate: object, base: dict) -> dict:
    """Accept phrasing/options only; authoritative answer/cells never change."""
    if not isinstance(candidate, dict):
        raise ValueError("adaptive_ai_question_not_object")
    if candidate.get("language") != base["language"]:
        raise ValueError("adaptive_ai_question_language_mismatch")
    if candidate.get("skill_id") != base["skill_id"]:
        raise ValueError("adaptive_ai_question_skill_mismatch")
    if int(candidate.get("difficulty", -1)) != base["difficulty"]:
        raise ValueError("adaptive_ai_question_difficulty_mismatch")
    if candidate.get("answer") != base["answer"]:
        raise ValueError("adaptive_ai_question_answer_mismatch")
    text = candidate.get("question_text")
    options = candidate.get("options")
    if not isinstance(text, str) or not 10 <= len(text.strip()) <= 600:
        raise ValueError("adaptive_ai_question_text_invalid")
    if not isinstance(options, list) or not 2 <= len(options) <= 8:
        raise ValueError("adaptive_ai_question_options_invalid")
    if len(set(options)) != len(options) or base["answer"] not in options:
        raise ValueError("adaptive_ai_question_options_invalid")
    pool = set(_pool(base["language"]))
    if any(not isinstance(option, str) or option not in pool for option in options):
        raise ValueError("adaptive_ai_question_option_not_verified")
    return {
        **base,
        "question_text": text.strip(),
        "options": options,
        "question_source": "ai_generated_validated",
        "generation_model": candidate.get("generation_model") or "configured-ollama",
        "validation_status": "validated",
    }


def _ai_candidate(base: dict, learner_key: str) -> dict:
    enabled = os.getenv("RESONANT_ADAPTIVE_AI_QUESTIONS", "false").lower() in {
        "1", "true", "yes"
    }
    if not enabled:
        raise RuntimeError("ai_generation_disabled")
    cooldown = max(1.0, float(os.getenv("RESONANT_ADAPTIVE_AI_COOLDOWN_SECONDS", "20")))
    with _AI_LOCK:
        previous = _AI_CALLS.get(learner_key, 0.0)
        now = monotonic()
        if now - previous < cooldown:
            raise RuntimeError("ai_generation_rate_limited")
        _AI_CALLS[learner_key] = now
    model = os.getenv("RESONANT_OLLAMA_MODEL", "qwen2.5:0.5b")
    url = os.getenv("RESONANT_OLLAMA_URL", "http://localhost:11434").rstrip("/") + "/api/chat"
    timeout = min(10.0, max(1.0, float(os.getenv("RESONANT_ADAPTIVE_AI_TIMEOUT_SECONDS", "4"))))
    prompt = {
        "task": "Rephrase one validated Braille recognition question as strict JSON.",
        "constraints": {
            "language": base["language"],
            "skill_id": base["skill_id"],
            "difficulty": base["difficulty"],
            "answer": base["answer"],
            "verified_options": base["options"],
            "do_not_change_braille_mapping": True,
        },
        "schema": {
            "language": "string",
            "skill_id": "string",
            "difficulty": "integer",
            "question_text": "string",
            "options": "array of strings",
            "answer": "string",
        },
    }
    response = requests.post(
        url,
        json={
            "model": model,
            "stream": False,
            "format": "json",
            "messages": [{"role": "user", "content": json.dumps(prompt, ensure_ascii=False)}],
        },
        timeout=timeout,
    )
    response.raise_for_status()
    payload = response.json()
    content = payload.get("message", {}).get("content")
    candidate = json.loads(content)
    candidate["generation_model"] = model
    return candidate


def select_adaptive_question(
    *,
    learner_id: str,
    skill_id: str,
    lesson_id: str,
    language: str,
    difficulty: int,
    recent_question_ids: set[str] | None = None,
    generated_candidate: object | None = None,
    try_ai: bool = False,
) -> dict:
    difficulty = max(1, min(5, int(difficulty)))
    base = _base_question(
        learner_id=learner_id,
        skill_id=skill_id,
        lesson_id=lesson_id,
        language=language,
        difficulty=difficulty,
        recent_question_ids=recent_question_ids or set(),
    )
    if generated_candidate is None and try_ai:
        try:
            generated_candidate = _ai_candidate(base, learner_id)
        except Exception as error:
            return {
                **base,
                "question_source": "deterministic_fallback",
                "generation_failure": type(error).__name__,
                "validation_status": "fallback_after_rejection",
            }
    if generated_candidate is not None:
        try:
            return validate_ai_candidate(generated_candidate, base)
        except (TypeError, ValueError) as error:
            return {
                **base,
                "question_source": "deterministic_fallback",
                "generation_failure": str(error)[:160],
                "validation_status": "fallback_after_rejection",
            }
    return base


def recent_question_ids(connection, *, learner_id, skill_id: str, limit: int = 8) -> set[str]:
    rows = connection.execute(
        """
        SELECT question_payload->>'question_id' AS question_id
        FROM resonant.adaptive_question_instances
        WHERE learner_id = %s AND skill_id = %s
        ORDER BY created_at DESC
        LIMIT %s
        """,
        (learner_id, skill_id, max(1, min(20, limit))),
    ).fetchall()
    return {str(dict(row).get("question_id")) for row in rows if dict(row).get("question_id")}


def persist_question(connection, *, learner_id, prediction_id, question: dict) -> None:
    payload = {
        key: value
        for key, value in question.items()
        if key not in {"expected_response"}
    }
    connection.execute(
        """
        INSERT INTO resonant.adaptive_question_instances (
            question_instance_id, learner_id, prediction_id, skill_id,
            lesson_id, language, difficulty, question_type, question_source,
            question_version, mapping_version, curriculum_version,
            question_payload, expected_response, generation_model,
            generation_failure, validation_status
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s, %s, %s
        )
        """,
        (
            question["question_instance_id"],
            learner_id,
            prediction_id,
            question["skill_id"],
            question["lesson_id"],
            question["language"],
            question["difficulty"],
            question["question_type"],
            question["question_source"],
            question["question_version"],
            question["mapping_version"],
            question["curriculum_version"],
            Jsonb(payload),
            Jsonb(question["expected_response"]),
            question["generation_model"],
            question["generation_failure"],
            question["validation_status"],
        ),
    )

