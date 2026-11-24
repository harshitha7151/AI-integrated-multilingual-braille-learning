"""Transactional persistence helpers for learner learning records."""

from database import get_connection
from psycopg.types.json import Jsonb
from learning_error_service import analyze_response
from uuid import uuid4
from adaptive_mastery import (
    BKTParameters,
    review_interval_days,
    sql_mastery_update_expression,
    update_mastery,
)


def _validated_skill_observations(attempt):
    submitted = getattr(attempt, "submitted_response", None)
    if not isinstance(submitted, dict):
        return []
    observations = submitted.get("skill_observations", [])
    if not isinstance(observations, list) or len(observations) > 128:
        raise ValueError("invalid_skill_observations")

    language = attempt.language
    prefix = {
        "English": "english-letter-",
        "Hindi": "hi-bharati-",
        "Kannada": "kn-bharati-",
    }[language]
    expected = getattr(attempt, "expected_response", None)
    target = expected.get("text") if isinstance(expected, dict) else None
    validated = []
    for item in observations:
        if not isinstance(item, dict):
            raise ValueError("invalid_skill_observation")
        character = item.get("character")
        skill_id = item.get("skill_id")
        correct = item.get("correct")
        if (
            not isinstance(character, str)
            or not character
            or len(character) > 16
            or not isinstance(skill_id, str)
            or len(skill_id) > 120
            or skill_id != prefix + (character.lower() if language == "English" else character)
            or not isinstance(correct, bool)
            or not isinstance(target, str)
            or (character.lower() not in target.lower() if language == "English" else character not in target)
        ):
            raise ValueError("invalid_skill_observation")
        validated.append({"skill_id": skill_id, "correct": correct})
    return validated


def update_skill_progress(
    connection,
    *,
    learner_id,
    skill_id,
    language,
    correct,
    response_time_ms,
):
    """Persist measured counts, BKT mastery, and the next spaced review."""
    correct_value = int(correct)
    parameters = BKTParameters.from_environment()
    initial_mastery = update_mastery(
        parameters.prior_knowledge, correct, parameters,
    )
    initial_interval = review_interval_days(initial_mastery, correct)
    updated_mastery = sql_mastery_update_expression(parameters)
    next_review = (
        "CASE WHEN EXCLUDED.correct_count = 0 THEN interval '0 days' "
        f"WHEN ({updated_mastery}) < 0.45 THEN interval '1 day' "
        f"WHEN ({updated_mastery}) < 0.65 THEN interval '3 days' "
        f"WHEN ({updated_mastery}) < 0.85 THEN interval '7 days' "
        "ELSE interval '14 days' END"
    )
    connection.execute(
        """
        INSERT INTO resonant.skill_progress (
            learner_id, skill_id, language, attempts, correct_count,
            mastery, average_response_ms, next_review_at, updated_at
        ) VALUES (
            %s, %s, %s, 1, %s, %s,
            %s, now() + (%s * interval '1 day'), now()
        )
        ON CONFLICT (learner_id, skill_id) DO UPDATE SET
            attempts = resonant.skill_progress.attempts + 1,
            correct_count = resonant.skill_progress.correct_count + EXCLUDED.correct_count,
            language = EXCLUDED.language,
            mastery = {updated_mastery},
            average_response_ms = (
                resonant.skill_progress.average_response_ms
                * resonant.skill_progress.attempts + EXCLUDED.average_response_ms
            ) / (resonant.skill_progress.attempts + 1),
            next_review_at = now() + {next_review},
            updated_at = now()
        """.format(updated_mastery=updated_mastery, next_review=next_review),
        (
            learner_id,
            skill_id,
            language,
            correct_value,
            initial_mastery,
            response_time_ms,
            initial_interval,
        ),
    )


def create_learner(username, language, teacher_id=None):
    with get_connection() as connection:
        row = connection.execute(
            """
            INSERT INTO resonant.learners
                (learner_id, username, preferred_language, teacher_id)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (username) DO UPDATE
            SET preferred_language = EXCLUDED.preferred_language
            WHERE resonant.learners.teacher_id
                IS NOT DISTINCT FROM EXCLUDED.teacher_id
            RETURNING learner_id, username, preferred_language, created_at
            """,
            (uuid4(), username, language, teacher_id),
        ).fetchone()
        if row is None:
            raise ValueError("username_conflict")
        return dict(row)


def get_learner(learner_id):
    with get_connection() as connection:
        row = connection.execute(
            """
            SELECT learner_id, username, preferred_language, created_at
            FROM resonant.learners WHERE learner_id = %s
            """,
            (learner_id,),
        ).fetchone()
        return dict(row) if row else None


def record_practice_attempt(attempt):
    """Insert once by submission UUID and update mastery in the same transaction."""
    input_status = getattr(attempt, "input_status", "valid")
    technical_failure_code = getattr(attempt, "technical_failure_code", None)
    session_id = getattr(attempt, "session_id", None)
    question_id = getattr(attempt, "question_id", None)
    character_target = getattr(attempt, "character_target", None)
    difficulty = getattr(attempt, "difficulty", 1)
    expected_response = getattr(attempt, "expected_response", None)
    submitted_response = getattr(attempt, "submitted_response", None)
    mapping_version = getattr(attempt, "mapping_version", "unspecified")
    curriculum_version = getattr(
        attempt,
        "curriculum_version",
        "flutter-catalog-v1",
    )
    intervention_type = getattr(attempt, "intervention_type", None)
    feedback_type = getattr(attempt, "feedback_type", None)

    if input_status == "technical_failure" and not technical_failure_code:
        raise ValueError("technical_failure_code_required")
    if input_status != "valid" and attempt.outcome == "correct":
        raise ValueError("nonlearning_input_cannot_be_correct")
    skill_observations = _validated_skill_observations(attempt)
    persisted_submitted_response = submitted_response
    if isinstance(expected_response, dict) and isinstance(submitted_response, dict):
        analysis = analyze_response(
            expected_response,
            submitted_response,
            input_status=input_status,
            technical_failure_code=technical_failure_code,
        )
        # Preserve the learner's exact cell input while adding a deterministic,
        # reproducible classification alongside it for later adaptive review.
        persisted_submitted_response = {
            **submitted_response,
            "error_analysis": analysis,
        }
    with get_connection() as connection:
        row = connection.execute(
            """
            INSERT INTO resonant.practice_attempts (
                submission_id, learner_id, exercise_id, skill_id, language,
                exercise_type, outcome, response_time_ms, hint_used,
                attempt_number, session_id, question_id, character_target,
                difficulty, expected_response, submitted_response,
                input_status, technical_failure_code, mapping_version,
                curriculum_version, intervention_type, feedback_type
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s
            )
            ON CONFLICT (submission_id) DO NOTHING
            RETURNING submission_id, attempt_id, learner_id, exercise_id,
                skill_id, language, exercise_type, outcome, response_time_ms,
                hint_used, attempt_number, session_id, question_id,
                character_target, difficulty, expected_response,
                submitted_response, input_status, technical_failure_code,
                mapping_version, curriculum_version, intervention_type,
                feedback_type, created_at
            """,
            (
                attempt.submission_id,
                attempt.learner_id,
                attempt.exercise_id,
                attempt.skill_id,
                attempt.language,
                attempt.exercise_type,
                attempt.outcome,
                attempt.response_time_ms,
                attempt.hint_used,
                attempt.attempt_number,
                session_id,
                question_id,
                character_target,
                difficulty,
                Jsonb(expected_response) if expected_response is not None else None,
                Jsonb(persisted_submitted_response)
                if persisted_submitted_response is not None else None,
                input_status,
                technical_failure_code,
                mapping_version,
                curriculum_version,
                intervention_type,
                feedback_type,
            ),
        ).fetchone()

        if row is None:
            existing = connection.execute(
                """
                SELECT submission_id, attempt_id, learner_id, exercise_id,
                    skill_id, language, exercise_type, outcome, response_time_ms,
                    hint_used, attempt_number, session_id, question_id,
                    character_target, difficulty, expected_response,
                    submitted_response, input_status, technical_failure_code,
                    mapping_version, curriculum_version, intervention_type,
                    feedback_type, created_at
                FROM resonant.practice_attempts WHERE submission_id = %s
                """,
                (attempt.submission_id,),
            ).fetchone()
            return {**dict(existing), "duplicate": True}

        if input_status == "valid" and attempt.outcome in {"correct", "incorrect"}:
            update_skill_progress(
                connection,
                learner_id=attempt.learner_id,
                skill_id=attempt.skill_id,
                language=attempt.language,
                correct=attempt.outcome == "correct",
                response_time_ms=attempt.response_time_ms,
            )
            for observation in skill_observations:
                update_skill_progress(
                    connection,
                    learner_id=attempt.learner_id,
                    skill_id=observation["skill_id"],
                    language=attempt.language,
                    correct=observation["correct"],
                    response_time_ms=attempt.response_time_ms,
                )
            from resonant_ml_service import resolve_previous_prediction

            resolve_previous_prediction(
                connection,
                learner_id=attempt.learner_id,
                skill_id=attempt.skill_id,
                submission_id=attempt.submission_id,
                observed_incorrect=attempt.outcome == "incorrect",
                observed_at=dict(row).get("created_at"),
            )
        return {**dict(row), "duplicate": False}


def record_quiz_result(result):
    with get_connection() as connection:
        row = connection.execute(
            """
            INSERT INTO resonant.quiz_results (
                submission_id, learner_id, quiz_id, language,
                score, max_score, duration_ms
            ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (submission_id) DO NOTHING
            RETURNING submission_id, quiz_result_id, learner_id, quiz_id,
                language, score, max_score, duration_ms, completed_at
            """,
            (
                result.submission_id,
                result.learner_id,
                result.quiz_id,
                result.language,
                result.score,
                result.max_score,
                result.duration_ms,
            ),
        ).fetchone()
        if row is not None:
            return {**dict(row), "duplicate": False}
        existing = connection.execute(
            """
            SELECT submission_id, quiz_result_id, learner_id, quiz_id,
                language, score, max_score, duration_ms, completed_at
            FROM resonant.quiz_results WHERE submission_id = %s
            """,
            (result.submission_id,),
        ).fetchone()
        return {**dict(existing), "duplicate": True}


def get_skill_progress(learner_id):
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT skill_id, language, attempts, correct_count, mastery,
                average_response_ms, next_review_at, updated_at
            FROM resonant.skill_progress
            WHERE learner_id = %s
            ORDER BY skill_id
            """,
            (learner_id,),
        ).fetchall()
        return [dict(row) for row in rows]
