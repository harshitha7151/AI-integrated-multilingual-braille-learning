
import os
from typing import Literal
from uuid import UUID

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import requests
from psycopg.errors import ForeignKeyViolation

from database import get_connection
from progress_service import (
    create_learner as save_learner,
    get_learner as load_learner,
    get_skill_progress,
    record_practice_attempt,
    record_quiz_result,
)
from verified_braille import (
    contains_unverified_dot_claim,
    is_pattern_question,
    requested_english_word,
    verify_client_examples,
    verified_single_letter,
    verified_uncontracted_word,
    verified_uncontracted_word_details,
)
from knowledge_base import (
    evidence_for_letter,
    format_evidence,
    has_braille_scope,
    requested_english_letter,
    retrieve_evidence,
    source_references,
)


app = FastAPI(title="Resonant AI Braille Tutor")

# Development CORS so the Flutter web build opened from a phone can call the API.
# Restrict RESONANT_CORS_ORIGINS (comma-separated) before any real deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in os.getenv("RESONANT_CORS_ORIGINS", "*").split(",")],
    allow_methods=["*"],
    allow_headers=["*"],
)

OLLAMA_BASE_URL = os.getenv("RESONANT_OLLAMA_URL", "http://localhost:11434").rstrip("/")
OLLAMA_URL = f"{OLLAMA_BASE_URL}/api/chat"
MODEL_NAME = os.getenv("RESONANT_OLLAMA_MODEL", "qwen2.5:0.5b")
AI_ENABLED = os.getenv("RESONANT_AI_ENABLED", "true").strip().lower() not in {"0", "false", "no"}
TUTOR_FALLBACK = (
    "The conversational model is offline. I can still answer Braille questions "
    "covered by Resonant's verified references, or explain a verified English "
    "letter or word. I will not guess about unsupported rules."
)


# -------------------------
# Request models
# -------------------------

class TutorQuestion(BaseModel):
    question: str = Field(min_length=1, max_length=2000)
    language: Literal["English"] = "English"
    lesson_context: str = Field(default="", max_length=600)
    history: list["TutorTurn"] = Field(default_factory=list, max_length=8)
    verified_examples: list["TutorExampleInput"] = Field(default_factory=list, max_length=4)


class TutorTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=2000)


class TutorExampleInput(BaseModel):
    text: str = Field(min_length=1, max_length=32)
    cells: list[int] = Field(min_length=1, max_length=64)


TutorQuestion.model_rebuild()


class LearnerCreate(BaseModel):
    username: str = Field(min_length=1, max_length=100)
    preferred_language: Literal["English", "Hindi", "Kannada"] = "English"


class PracticeAttemptCreate(BaseModel):
    submission_id: UUID
    learner_id: UUID
    exercise_id: str = Field(min_length=1, max_length=120)
    skill_id: str = Field(min_length=1, max_length=120)
    language: Literal["English", "Hindi", "Kannada"]
    exercise_type: Literal[
        "dot_recognition", "letter_recognition", "listening",
        "braille_writing", "transcription", "quiz",
    ]
    outcome: Literal[
        "correct", "incorrect", "cancelled", "accidental_touch", "timeout",
    ]
    response_time_ms: int = Field(ge=0, le=3_600_000)
    hint_used: bool = False
    attempt_number: int = Field(ge=1, le=100_000)


class QuizResultCreate(BaseModel):
    submission_id: UUID
    learner_id: UUID
    quiz_id: str = Field(min_length=1, max_length=120)
    language: Literal["English", "Hindi", "Kannada"]
    score: int = Field(ge=0)
    max_score: int = Field(gt=0)
    duration_ms: int = Field(ge=0, le=86_400_000)


# -------------------------
# Home endpoint
# -------------------------

@app.get("/")
def home():
    return {
        "message": "Resonant AI Tutor is running!",
        "database": "PostgreSQL",
        "ai_model": MODEL_NAME,
    }


@app.get("/health")
def application_health():
    return {"status": "ok"}


@app.get("/health/ai")
def ai_health():
    if not AI_ENABLED:
        return {"status": "disabled", "model": MODEL_NAME}
    try:
        response = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=3)
        response.raise_for_status()
        available = any(
            model.get("name", "").split(":")[0] == MODEL_NAME.split(":")[0]
            for model in response.json().get("models", [])
        )
        return {
            "status": "available" if available else "model_missing",
            "model": MODEL_NAME,
        }
    except (requests.RequestException, ValueError, AttributeError):
        return {"status": "unavailable", "model": MODEL_NAME}


# -------------------------
# AI Braille tutor
# -------------------------

@app.post("/ask")
def ask_tutor(data: TutorQuestion):
    if not AI_ENABLED:
        raise HTTPException(status_code=503, detail="AI tutoring is disabled.")

    verified_examples = verify_client_examples(data.verified_examples)
    requested_letter = requested_english_letter(data.question)
    requested_word = requested_english_word(data.question)
    if requested_word is None and len(data.question.split()) <= 5:
        previous_word_question = next((
            turn.content for turn in reversed(data.history)
            if turn.role == "user" and requested_english_word(turn.content)
        ), None)
        if previous_word_question:
            requested_word = requested_english_word(previous_word_question)
    word_details = None
    word_answer = None
    letter_examples = []
    word_evidence = []
    if is_pattern_question(data.question) or requested_word is not None:
        if requested_letter is not None:
            expected = verified_single_letter(requested_letter)
            if expected is None:
                expected = None
            if expected is not None:
                verified_examples = [expected]
                evidence = evidence_for_letter(requested_letter)
                letter_cell = expected["cells"][-1]
                letter_dots = [bit + 1 for bit in range(6) if letter_cell & (1 << bit)]
                dot_text = " and ".join(str(dot) for dot in letter_dots)
                if len(letter_dots) == 1:
                    dot_text += " only"
                letter_name = requested_letter.upper()
                position = {
                    1: "top-left", 2: "middle-left", 3: "bottom-left",
                    4: "top-right", 5: "middle-right", 6: "bottom-right",
                }
                if len(letter_dots) == 1:
                    position_text = position[letter_dots[0]]
                else:
                    position_text = "the six-dot cell"
                answer = (
                    f"The letter {letter_name} uses dot {dot_text}. "
                    f"In a six-dot Braille cell, that is {position_text}."
                )
                if requested_letter.isupper():
                    answer += (
                        f" For uppercase {letter_name}, select the capital sign "
                        "(dot 6) first, then the letter cell."
                    )
                return {
                    "answer": answer,
                    "source": "verified_engine",
                    "verified_examples": verified_examples,
                    "sources": source_references(evidence),
                }
        if requested_word is not None:
            word_details = verified_uncontracted_word_details(requested_word)
            if word_details is None:
                return {
                    "answer": (
                        f"I can't verify every character in {requested_word} with "
                        "the current uncontracted English subset, so I won't guess."
                    ),
                    "source": "unsupported_example",
                    "verified_examples": [],
                    "letter_examples": [],
                    "sources": [],
                }
            expected = {"text": requested_word, "cells": word_details["cells"]}
            verified_examples = [expected]
            letter_examples = word_details["letter_examples"]
            positions = {
                1: "top-left", 2: "middle-left", 3: "bottom-left",
                4: "top-right", 5: "middle-right", 6: "bottom-right",
            }
            letter_descriptions = []
            for letter in letter_examples:
                dots = letter["dots"]
                positioned_dots = [
                    f"dot {dot} at {positions[dot]}" for dot in dots
                ]
                if len(positioned_dots) == 1:
                    dot_text = positioned_dots[0]
                elif len(positioned_dots) == 2:
                    dot_text = f"{positioned_dots[0]} and {positioned_dots[1]}"
                else:
                    dot_text = (
                        f"{', '.join(positioned_dots[:-1])}, "
                        f"and {positioned_dots[-1]}"
                    )
                letter_descriptions.append(f"{letter['letter']}: {dot_text}")
            capitalization = ""
            if requested_word.isupper():
                capitalization = (
                    " Since the word is all capitals, use the capital-word "
                    "indicator first: dot 6 twice."
                )
            elif any(character.isupper() for character in requested_word):
                capitalization = (
                    " Each uppercase letter has a capital sign, dot 6, before "
                    "its letter cell."
                )
            word_answer = (
                f"The verified, uncontracted English Braille spelling of "
                f"{requested_word} uses {len(expected['cells'])} cells: "
                f"{'; '.join(letter_descriptions)}.{capitalization} "
                "The letters are written as separate cells, without contractions."
            )
            for character in set(requested_word.lower()):
                word_evidence.extend(evidence_for_letter(character))
        if word_details is not None:
            return {
                "answer": (
                    f"Let's look at {requested_word} one letter at a time. "
                    f"{word_answer}"
                ),
                "source": "verified_engine",
                "verified_examples": verified_examples,
                "letter_examples": letter_examples,
                "sources": source_references(word_evidence),
            }
        if word_details is None:
            if not verified_examples:
                return {
                    "answer": (
                        "I can explain Braille concepts, but I cannot verify that specific "
                        "character with the current English Braille subset. I will not guess its pattern."
                    ),
                    "source": "unsupported_example",
                    "verified_examples": [],
                    "sources": [],
                }
            return {
                "answer": (
                    "I checked this example with Resonant's deterministic uncontracted "
                    "English Braille verifier. The verified pattern is shown separately."
                ),
                "source": "verified_engine",
                "verified_examples": verified_examples,
                "sources": [{"title": "ICEB, Rules of Unified English Braille, Third Edition (2024)", "url": "https://iceb.org/publications/ueb/"}],
            }

    history = [turn.model_dump() for turn in data.history]
    evidence = word_evidence or retrieve_evidence(
        data.question,
        history=history,
        lesson_context=data.lesson_context,
    )
    if has_braille_scope(data.question) and not evidence:
        return {
            "answer": (
                "I don't have verified Resonant evidence for that Braille rule or "
                "language, so I won't guess. I can help with the six-dot layout "
                "and the uncontracted English letters currently in the verified subset."
            ),
            "source": "unsupported_knowledge",
            "verified_examples": verified_examples,
            "sources": [],
        }

    history_text = "\n".join(
        f"{turn['role']}: {turn['content']}" for turn in history[-6:]
    )
    evidence_text = format_evidence(evidence)
    examples_text = "\n".join(
        f"{example['text']}: verified cell sequence {example['cells']}"
        for example in verified_examples
    ) or "(No lesson example was supplied.)"

    prompt = f"""
You are Resonant, a patient AI Braille tutor
for blind and low-vision learners.

Teach in English.
Use simple language and short explanations.
Be encouraging and respectful.
Teach the current concept before testing it. Offer a hint or gently explain
mistakes when asked. Never state Braille cell patterns, dot lists, or character
translations; the deterministic verifier handles exact encodings.
Use only the verified evidence below for Braille-specific factual claims. If it
does not support an answer, say that the rule is outside Resonant's verified
subset. Do not invent a source or claim you used a tool you did not use.
If a verified example is supplied, explain it without changing its cell values.
Do not state a dot sequence yourself; the verified example is returned separately.
Do not claim to see or feel the learner's actions.

Current lesson context: {data.lesson_context or 'General Braille learning.'}
Previous turns in this open conversation (not saved):
{history_text or '(No previous turns.)'}
Verified retrieved evidence (only this evidence may support Braille facts):
{evidence_text or '(No Braille evidence retrieved.)'}
Verified lesson examples:
{examples_text}
For a verified word question, explain the word gently and briefly. The final
exact letter-by-letter dot explanation is generated separately from the
verified engine and must remain authoritative.
Learner's question: {data.question}
"""

    def offline_answer() -> dict:
        if word_answer:
            answer = word_answer
            response_source = "verified_engine_fallback"
        elif evidence:
            verified_notes = " ".join(
                str(item.get("content", "")) for item in evidence[:2]
                if item.get("content")
            )
            answer = f"Here is a verified note for your question. {verified_notes}"
            response_source = "verified_knowledge_fallback"
        else:
            answer = TUTOR_FALLBACK
            response_source = "fallback"
        return {
            "answer": answer,
            "source": response_source,
            "verified_examples": verified_examples,
            "letter_examples": letter_examples,
            "sources": source_references(evidence),
        }

    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": MODEL_NAME,
            "messages": [
                    {
                        "role": "system",
                        "content": (
                            "You are a patient, structured Braille teacher. "
                            "Teach concepts, examples, hints, and mistakes clearly. "
                            "Use retrieved evidence for Braille facts. Never invent "
                            "cell mappings; exact encodings are handled by the "
                            "deterministic verifier."
                        ),
                    },
                    {
                        "role": "user",
                        "content": prompt,
                    },
                ],
                "stream": False,
            },
            timeout=(3, 20),
        )

        response.raise_for_status()
        answer = response.json().get("message", {}).get("content")
        if not isinstance(answer, str) or not answer.strip():
            return {
                "answer": f"{TUTOR_FALLBACK} {word_answer or ''}".strip(),
                "source": "verified_engine_fallback" if word_details else "fallback",
                "verified_examples": verified_examples,
                "letter_examples": letter_examples,
                "sources": source_references(evidence),
            }

        if contains_unverified_dot_claim(answer):
            return {
                "answer": word_answer or (
                    "I want to keep Braille patterns accurate. I can explain the "
                    "lesson, and the deterministic verifier will provide any supported pattern."
                ),
                "source": "verified_engine_fallback" if word_details else "safe_fallback",
                "verified_examples": verified_examples,
                "letter_examples": letter_examples,
                "sources": source_references(evidence),
            }

        final_answer = f"{answer.strip()} {word_answer}".strip() if word_answer else answer.strip()
        return {
            "answer": final_answer,
            "source": "ollama_rag_verified_engine" if word_details else "ollama_rag" if evidence else "ollama",
            "verified_examples": verified_examples,
            "letter_examples": letter_examples,
            "sources": source_references(evidence),
        }

    except requests.RequestException:
        return offline_answer()
    except (ValueError, AttributeError, TypeError):
        return offline_answer()


# -------------------------
# Create or retrieve learner
# -------------------------

@app.post("/learners")
def create_learner(data: LearnerCreate):
    username = data.username.strip()
    language = data.preferred_language.strip()

    if not username:
        raise HTTPException(
            status_code=422,
            detail="Username cannot be empty.",
        )

    if not language:
        raise HTTPException(
            status_code=422,
            detail="Preferred language cannot be empty.",
        )

    try:
        return save_learner(username, language)

    except Exception as error:
        # Log the detailed error in your development terminal.
        # Avoid writing SQL parameters or connection details to logs.
        print(f"Database operation failed ({type(error).__name__}).")

        raise HTTPException(
            status_code=500,
            detail="Could not save learner to the database.",
        ) from error


@app.get("/learners/{learner_id}")
def learner_profile(learner_id: UUID):
    try:
        learner = load_learner(learner_id)
        if learner is None:
            raise HTTPException(status_code=404, detail="Learner was not found.")
        return learner
    except HTTPException:
        raise
    except Exception as error:
        print(f"Database operation failed ({type(error).__name__}).")
        raise HTTPException(status_code=503, detail="Learner data is unavailable.") from error


@app.post("/practice/attempts")
def create_practice_attempt(data: PracticeAttemptCreate):
    try:
        return record_practice_attempt(data)
    except ForeignKeyViolation as error:
        raise HTTPException(status_code=404, detail="Learner was not found.") from error
    except Exception as error:
        print(f"Practice attempt could not be recorded ({type(error).__name__}).")
        raise HTTPException(status_code=503, detail="Practice data is unavailable.") from error


@app.get("/learners/{learner_id}/progress")
def learner_progress(learner_id: UUID):
    try:
        if load_learner(learner_id) is None:
            raise HTTPException(status_code=404, detail="Learner was not found.")
        return {"learner_id": learner_id, "skills": get_skill_progress(learner_id)}
    except HTTPException:
        raise
    except Exception as error:
        print(f"Progress query failed ({type(error).__name__}).")
        raise HTTPException(status_code=503, detail="Progress data is unavailable.") from error


@app.post("/quizzes/results")
def create_quiz_result(data: QuizResultCreate):
    if data.score > data.max_score:
        raise HTTPException(status_code=422, detail="Score cannot exceed maximum score.")
    try:
        return record_quiz_result(data)
    except ForeignKeyViolation as error:
        raise HTTPException(status_code=404, detail="Learner was not found.") from error
    except Exception as error:
        print(f"Quiz result could not be recorded ({type(error).__name__}).")
        raise HTTPException(status_code=503, detail="Quiz data is unavailable.") from error


# -------------------------
# Check database connection
# -------------------------

@app.get("/health/database")
def database_health():
    try:
        with get_connection() as conn:
            row = conn.execute(
                """
                SELECT current_database() AS database_name
                """
            ).fetchone()

            return {
                "status": "connected",
                "database": row["database_name"],
            }

    except Exception as error:
        print(f"Database health check failed ({type(error).__name__}).")

        raise HTTPException(
            status_code=503,
            detail="Database connection failed.",
        ) from error
