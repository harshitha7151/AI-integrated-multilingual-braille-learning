"""Validated, transactional persistence for lesson assessments.

The service stores structured responses only. Braille targets are checked
against Resonant's deterministic English or Bharati forward tables before any
assessment is accepted.
"""

from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from psycopg.types.json import Jsonb

from adaptive_question_service import (
    persist_question,
    recent_question_ids,
    select_adaptive_question,
)
from adaptive_policy import contextual_bandit_ranking, rank_supported_skills
from bharati_verified import bitmasks as bharati_bitmasks, encode as encode_bharati
from database import get_connection
from learning_error_service import analyze_response, response_cells
from progress_service import update_skill_progress
from resonant_ml_service import (
    build_prediction,
    hybridize_decision,
    persist_prediction,
    resolve_previous_prediction,
)
from verified_braille import (
    verified_single_letter,
    verified_uncontracted_text,
    verified_uncontracted_word,
)


def _cells(response: dict) -> list[int] | None:
    return response_cells(response)


def categorize_error(expected: dict, submitted: dict) -> str:
    """Return a deterministic, bounded error category for analytics."""
    return analyze_response(expected, submitted)["category"]


def _verified_cells(target: str, language: str) -> list[int] | None:
    if language == "English":
        verified = (
            verified_single_letter(target)
            if len(target) == 1
            else verified_uncontracted_word(target)
            or verified_uncontracted_text(target)
        )
        return verified["cells"] if verified else None
    encoded = encode_bharati(target, language)
    return bharati_bitmasks(encoded) if encoded is not None else None


def validate_question(question, language: str) -> None:
    """Reject assessment targets that are not backed by a verified engine."""
    expected = question.expected_response
    target = expected.get("choice") or expected.get("text")
    if not isinstance(target, str) or not target:
        raise ValueError("assessment_expected_target_required")
    if question.options and target not in question.options:
        raise ValueError("assessment_answer_missing_from_options")
    if len(set(question.options)) != len(question.options):
        raise ValueError("assessment_options_must_be_unique")
    if any(
        _verified_cells(option, language) is None
        for option in question.options
    ):
        raise ValueError("assessment_option_not_verified")

    verified_cells = _verified_cells(target, language)
    if verified_cells is None:
        raise ValueError("assessment_target_not_verified")

    expected_cells = _cells(expected)
    if expected_cells is not None and expected_cells != verified_cells:
        raise ValueError("assessment_cells_do_not_match_verified_engine")

    input_status = getattr(question, "input_status", "valid")
    technical_failure_code = getattr(question, "technical_failure_code", None)
    if input_status != "valid":
        if question.correct:
            raise ValueError("nonlearning_input_cannot_be_correct")
        analyze_response(
            expected,
            question.submitted_response,
            input_status=input_status,
            technical_failure_code=technical_failure_code,
        )
        return

    submitted_cells = _cells(question.submitted_response)
    submitted_target = question.submitted_response.get(
        "choice"
    ) or question.submitted_response.get("text")
    cell_only_transcription = (
        question.exercise_type in {"transcription", "braille_writing"}
        and submitted_target is None
        and submitted_cells is not None
        and len(submitted_cells) > 0
    )
    if cell_only_transcription:
        response_is_correct = expected_cells == submitted_cells
    else:
        if not isinstance(submitted_target, str) or not submitted_target:
            raise ValueError("assessment_submitted_response_required")
        verified_submitted_cells = _verified_cells(submitted_target, language)
        if verified_submitted_cells is None:
            raise ValueError("assessment_submitted_target_not_verified")
        if submitted_cells is not None and submitted_cells != verified_submitted_cells:
            raise ValueError("assessment_submitted_cells_do_not_match_verified_engine")
        response_is_correct = target == submitted_target
        if expected_cells is not None and submitted_cells is not None:
            response_is_correct = response_is_correct and expected_cells == submitted_cells
    if response_is_correct != question.correct:
        raise ValueError("assessment_correctness_does_not_match_response")

    if question.skill_id.startswith("english-letter-"):
        skill_target = question.skill_id.removeprefix("english-letter-")
        if language != "English" or target.casefold() != skill_target.casefold():
            raise ValueError("assessment_target_does_not_match_skill")
    elif question.skill_id.startswith("hi-bharati-"):
        if language != "Hindi" or target != question.skill_id.removeprefix("hi-bharati-"):
            raise ValueError("assessment_target_does_not_match_skill")
    elif question.skill_id.startswith("kn-bharati-"):
        if language != "Kannada" or target != question.skill_id.removeprefix("kn-bharati-"):
            raise ValueError("assessment_target_does_not_match_skill")


def _as_float(value, default: float = 0.0) -> float:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (int, float)):
        return float(value)
    return default


def _adaptive_decision(
    assessment,
    progress_rows: list[dict],
    *,
    prior_progress_rows: list[dict] | None = None,
    history_row: dict | None = None,
    error_rows: list[dict] | None = None,
    prior_bandit_decisions: list[dict] | None = None,
    prior_remediation_count: int = 0,
) -> dict:
    """Choose an explainable action using deterministic assessment rules."""
    questions = assessment.questions
    eligible_questions = [
        question
        for question in questions
        if getattr(question, "input_status", "valid") == "valid"
    ]
    technical_count = sum(
        getattr(question, "input_status", "valid") == "technical_failure"
        for question in questions
    )
    invalid_input_count = len(questions) - len(eligible_questions) - technical_count
    score = sum(1 for question in eligible_questions if question.correct)
    max_score = len(eligible_questions)
    accuracy = score / max_score if max_score else 0.0
    wrong_answers = max_score - score
    repeated_attempts = sum(
        max(0, question.attempts - 1) for question in eligible_questions
    )
    hint_count = sum(1 for question in eligible_questions if question.hint_used)
    now = datetime.now(timezone.utc)

    def is_due(row):
        review_at = row.get("next_review_at")
        if review_at is None:
            return False
        if isinstance(review_at, str):
            try:
                review_at = datetime.fromisoformat(review_at)
            except ValueError:
                return False
        if review_at.tzinfo is None:
            review_at = review_at.replace(tzinfo=timezone.utc)
        return review_at <= now

    due_progress_rows = [row for row in progress_rows if is_due(row)]
    skill_candidates = list(dict.fromkeys(
        question.skill_id for question in eligible_questions
    ))
    selection_ranking = rank_supported_skills(
        skill_candidates,
        progress_rows,
        error_rows or [],
        now=now,
    )
    bandit_ranking = contextual_bandit_ranking(
        selection_ranking,
        prior_bandit_decisions or [],
    )
    if bandit_ranking is not None:
        selection_ranking = bandit_ranking
    selected_skill = selection_ranking[0] if selection_ranking else None
    weakest = next(
        (row for row in progress_rows
         if selected_skill and row.get("skill_id") == selected_skill["skill_id"]),
        None,
    )
    weakest_mastery = _as_float(weakest.get("mastery"), accuracy) if weakest else accuracy
    prior_rows = prior_progress_rows or []
    prior_weakest = min(
        prior_rows,
        key=lambda row: _as_float(row.get("mastery"), 1.0),
        default=None,
    )
    mastery_before = (
        _as_float(prior_weakest.get("mastery"), 0.0)
        if prior_weakest
        else 0.0
    )
    recommended_skill = (
        selected_skill["skill_id"] if selected_skill else questions[0].skill_id
    )
    prior_history = history_row or {}
    previous_assessment_count = int(prior_history.get("assessment_count") or 0)
    previous_average_accuracy = _as_float(
        prior_history.get("average_accuracy"),
        0.0,
    )
    repeated_error_count = sum(
        int(row.get("error_count") or 0) for row in (error_rows or [])
    )
    error_categories = sorted(
        {
            row.get("error_category")
            for row in (error_rows or [])
            if row.get("error_category")
        }
    )
    remediation_cycle = prior_remediation_count

    if not eligible_questions:
        action = "reassess"
        reason = (
            "No valid learning response was recorded. Technical, missing, or "
            "invalid input is not treated as a learner mistake; a supported "
            "reassessment is required."
        )
    elif accuracy < 0.5 and weakest_mastery < 0.35:
        if prior_remediation_count >= 2:
            action = "reassess"
            reason = (
                "The learner is still below the mastery threshold after two recorded "
                "remediation cycles. The same remediation will not be assigned again "
                "automatically; a supported reassessment is required."
            )
        else:
            action = "revisit_prerequisite"
            remediation_cycle += 1
            reason = (
                "The assessment showed a low score and the tested skill remains below "
                "the current mastery threshold, so prerequisite-safe teaching should be revisited."
            )
    elif accuracy < 0.6 or repeated_error_count >= 2:
        if prior_remediation_count >= 2:
            action = "reassess"
            reason = (
                "Repeated errors remain after the automatic remediation limit, so the "
                "learner stays on a supported reassessment instead of receiving the same lesson again."
            )
        else:
            action = "remedial_practice"
            remediation_cycle += 1
            reason = (
                "Incorrect or repeated error evidence indicates that focused, accessible "
                "practice is needed before another assessment opportunity."
            )
    elif accuracy < 1.0 or repeated_attempts > 0 or hint_count > 0:
        action = "reinforce"
        remediation_cycle += 1
        reason = (
            "The learner completed the assessment but needed additional attempts, a hint, "
            "or made an error, so short reinforcement is recommended."
        )
    else:
        action = "advance"
        reason = (
            "All questions were correct on the recorded attempt without a hint, so the "
            "next prerequisite-safe lesson is recommended."
        )

    current_difficulty = max(1, min(5, int(assessment.difficulty)))
    if action == "advance" and accuracy == 1.0 and not repeated_attempts and not hint_count:
        difficulty_after = min(5, current_difficulty + 1)
    elif accuracy < 0.5 or repeated_error_count >= 2:
        difficulty_after = max(1, current_difficulty - 1)
    else:
        difficulty_after = current_difficulty

    confidence = min(0.9, 0.55 + (0.08 * max_score))
    if repeated_attempts or hint_count:
        confidence = max(0.45, confidence - 0.1)
    evidence = {
        "score": score,
        "max_score": max_score,
        "accuracy": round(accuracy, 4),
        "wrong_answers": wrong_answers,
        "repeated_attempts": repeated_attempts,
        "hint_count": hint_count,
        "weakest_mastery": round(weakest_mastery, 4),
        "mastery_before": round(mastery_before, 4),
        "mastery_after": round(weakest_mastery, 4),
        "review_due": bool(due_progress_rows),
        "review_due_skills": sorted(
            row["skill_id"] for row in due_progress_rows
        ),
        "adaptive_selection_method": (
            "linucb_with_information_gain_forgetting_context"
            if bandit_ranking is not None
            else "information_gain_forget_risk_rules_cold_start"
        ),
        "bandit_observation_count": (
            bandit_ranking[0].get("bandit_observation_count", 0)
            if bandit_ranking else 0
        ),
        "eligible_skill_scores": selection_ranking,
        "selected_skill_for_next_exercise": selected_skill,
        "difficulty_policy": "bounded_one_step_outcome_rule",
        "difficulty_before": current_difficulty,
        "difficulty_after": difficulty_after,
        "previous_assessment_count": previous_assessment_count,
        "previous_average_accuracy": round(previous_average_accuracy, 4),
        "repeated_error_count": repeated_error_count,
        "repeated_error_categories": error_categories,
        "eligible_question_count": max_score,
        "technical_input_count": technical_count,
        "invalid_input_count": invalid_input_count,
        "remediation_cycle": remediation_cycle,
        "tested_skills": sorted({question.skill_id for question in eligible_questions}),
        "decision_method": "deterministic_rules",
        "rule_version": "backend-assessment-v2",
    }
    if due_progress_rows:
        reason += " A scheduled skill review is due, so the recommendation prioritizes that skill."
    return {
        "decision_id": uuid4(),
        "action": action,
        "recommended_skill_id": recommended_skill,
        "recommended_lesson_id": assessment.lesson_id,
        "reason": reason,
        "evidence": evidence,
        "confidence": round(confidence, 3),
        "expected_learning_objective": questions[0].learning_objective,
        "decision_method": "deterministic_rules",
        "status": "pending",
        "remediation_cycle": remediation_cycle,
        "mastery_before": round(mastery_before, 5),
        "mastery_after": round(weakest_mastery, 5),
        "difficulty_before": current_difficulty,
        "difficulty_after": difficulty_after,
    }


def _duplicate_assessment(connection, submission_id):
    row = connection.execute(
        """
        SELECT s.assessment_id, s.submission_id, s.learner_id, s.assessment_key,
               s.lesson_id, s.language, s.assessment_type, s.difficulty,
               s.generated_content_version, s.question_count, s.score,
               s.duration_ms, s.started_at, s.completed_at,
               d.decision_id, d.action, d.recommended_skill_id,
               d.recommended_lesson_id, d.reason, d.evidence, d.confidence,
               d.expected_learning_objective, d.decision_method, d.status,
               d.remediation_cycle, d.mastery_before, d.mastery_after,
               d.applied_at, d.completed_at, d.succeeded, d.prediction_id,
               d.question_instance_id, d.model_probability_incorrect,
               d.model_version, d.difficulty_before, d.difficulty_after,
               d.fallback_used
        FROM resonant.assessment_sessions s
        LEFT JOIN resonant.adaptive_decisions d
          ON d.assessment_id = s.assessment_id
        WHERE s.submission_id = %s
        """,
        (submission_id,),
    ).fetchone()
    if row is None:
        raise RuntimeError("assessment_submission_conflict_without_record")
    result = dict(row)
    decision = {
        "decision_id": result.pop("decision_id", None),
        "action": result.pop("action", None),
        "recommended_skill_id": result.pop("recommended_skill_id", None),
        "recommended_lesson_id": result.pop("recommended_lesson_id", None),
        "reason": result.pop("reason", None),
        "evidence": result.pop("evidence", None),
        "confidence": result.pop("confidence", None),
        "expected_learning_objective": result.pop(
            "expected_learning_objective",
            None,
        ),
        "decision_method": result.pop("decision_method", None),
        "status": result.pop("status", None),
        "remediation_cycle": result.pop("remediation_cycle", 0),
        "mastery_before": result.pop("mastery_before", None),
        "mastery_after": result.pop("mastery_after", None),
        "applied_at": result.pop("applied_at", None),
        "completed_at": result.pop("completed_at", None),
        "succeeded": result.pop("succeeded", None),
        "prediction_id": result.pop("prediction_id", None),
        "question_instance_id": result.pop("question_instance_id", None),
        "model_probability_incorrect": result.pop(
            "model_probability_incorrect", None
        ),
        "model_version": result.pop("model_version", None),
        "difficulty_before": result.pop("difficulty_before", None),
        "difficulty_after": result.pop("difficulty_after", None),
        "fallback_used": result.pop("fallback_used", True),
    }
    result["decision"] = decision
    result["duplicate"] = True
    return result


def record_assessment(learner_id, assessment) -> dict:
    """Persist a completed assessment and its learning updates atomically."""
    assessment_id = uuid4()
    eligible_questions = [
        question
        for question in assessment.questions
        if getattr(question, "input_status", "valid") == "valid"
    ]
    score = sum(1 for question in eligible_questions if question.correct)
    with get_connection() as connection:
        session = connection.execute(
            """
            INSERT INTO resonant.assessment_sessions (
                assessment_id, submission_id, learner_id, assessment_key,
                lesson_id, language, assessment_type, difficulty,
                generated_content_version, question_count,
                eligible_question_count, score, duration_ms, started_at,
                completed_at
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s
            )
            ON CONFLICT (submission_id) DO NOTHING
            RETURNING assessment_id, submission_id, learner_id, assessment_key,
                      lesson_id, language, assessment_type, difficulty,
                      generated_content_version, question_count,
                      eligible_question_count, score, duration_ms, started_at,
                      completed_at
            """,
            (
                assessment_id,
                assessment.submission_id,
                learner_id,
                assessment.assessment_key,
                assessment.lesson_id,
                assessment.language,
                assessment.assessment_type,
                assessment.difficulty,
                assessment.generated_content_version,
                len(assessment.questions),
                len(eligible_questions),
                score,
                assessment.duration_ms,
                assessment.started_at,
                assessment.completed_at,
            ),
        ).fetchone()
        if session is None:
            return _duplicate_assessment(connection, assessment.submission_id)

        skill_ids = sorted({question.skill_id for question in assessment.questions})
        prior_progress_rows = connection.execute(
            """
            SELECT skill_id, attempts, correct_count, mastery,
                   average_response_ms, next_review_at, updated_at
            FROM resonant.skill_progress
            WHERE learner_id = %s AND skill_id = ANY(%s)
            """,
            (learner_id, skill_ids),
        ).fetchall()
        history_row = connection.execute(
            """
            SELECT COUNT(*) AS assessment_count,
                   COALESCE(
                       AVG(
                           score::numeric /
                           NULLIF(eligible_question_count, 0)
                       ),
                       0
                   ) AS average_accuracy
            FROM resonant.assessment_sessions
            WHERE learner_id = %s AND lesson_id = %s AND assessment_id <> %s
            """,
            (learner_id, assessment.lesson_id, assessment_id),
        ).fetchone()
        remediation_row = connection.execute(
            """
            SELECT COUNT(*) AS remediation_count
            FROM resonant.adaptive_decisions d
            JOIN resonant.assessment_sessions s
              ON s.assessment_id = d.assessment_id
            WHERE d.learner_id = %s
              AND s.lesson_id = %s
              AND d.action IN (
                  'remediate', 'remedial_practice', 'revisit_prerequisite'
              )
            """,
            (learner_id, assessment.lesson_id),
        ).fetchone()
        prior_remediation_count = int(
            (dict(remediation_row).get("remediation_count") if remediation_row else 0)
            or 0
        )

        for order, question in enumerate(assessment.questions, start=1):
            input_status = getattr(question, "input_status", "valid")
            error_details = analyze_response(
                question.expected_response,
                question.submitted_response,
                input_status=input_status,
                technical_failure_code=getattr(
                    question,
                    "technical_failure_code",
                    None,
                ),
            )
            error_category = (
                None
                if error_details["category"] == "correct"
                else error_details["category"]
            )
            connection.execute(
                """
                INSERT INTO resonant.assessment_questions (
                    assessment_id, question_id, question_order, skill_id,
                    exercise_type, learning_objective, difficulty,
                    question_text, options, expected_response,
                    question_instance_id, question_source, question_version,
                    generation_model
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s
                )
                """,
                (
                    assessment_id,
                    question.question_id,
                    order,
                    question.skill_id,
                    question.exercise_type,
                    question.learning_objective,
                    question.difficulty,
                    question.question_text,
                    Jsonb(question.options),
                    Jsonb(question.expected_response),
                    getattr(question, "question_instance_id", None),
                    getattr(question, "question_source", "validated_catalog"),
                    getattr(question, "question_version", "flutter-catalog-v1"),
                    getattr(question, "generation_model", None),
                ),
            )
            connection.execute(
                """
                INSERT INTO resonant.assessment_attempts (
                    assessment_id, question_id, learner_id, submitted_response,
                    correct, attempt_number, response_time_ms, hint_used,
                    error_category, missing_dots, extra_dots, input_status,
                    counts_for_learning, technical_failure_code,
                    mapping_version, curriculum_version, intervention_type,
                    feedback_type
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s
                )
                """,
                (
                    assessment_id,
                    question.question_id,
                    learner_id,
                    Jsonb(question.submitted_response),
                    question.correct,
                    question.attempts,
                    question.response_time_ms,
                    question.hint_used,
                    error_category,
                    Jsonb(error_details["missing_dots"]),
                    Jsonb(error_details["extra_dots"]),
                    input_status,
                    error_details["counts_for_learning"],
                    error_details["technical_failure_code"],
                    getattr(question, "mapping_version", "unspecified"),
                    getattr(question, "curriculum_version", "flutter-catalog-v1"),
                    getattr(question, "intervention_type", None),
                    getattr(question, "feedback_type", None),
                ),
            )
            if error_details["counts_for_learning"]:
                resolve_previous_prediction(
                    connection,
                    learner_id=learner_id,
                    skill_id=question.skill_id,
                    submission_id=assessment.submission_id,
                    observed_incorrect=not question.correct,
                    observed_at=assessment.completed_at,
                )
                update_skill_progress(
                    connection,
                    learner_id=learner_id,
                    skill_id=question.skill_id,
                    language=assessment.language,
                    correct=question.correct,
                    response_time_ms=question.response_time_ms,
                )
            if error_details["counts_for_learning"] and error_category is not None:
                connection.execute(
                    """
                    INSERT INTO resonant.assessment_error_summaries (
                        learner_id, language, skill_id, error_category,
                        error_count, first_seen_at, last_seen_at
                    ) VALUES (%s, %s, %s, %s, 1, now(), now())
                    ON CONFLICT (learner_id, skill_id, error_category) DO UPDATE SET
                        error_count = resonant.assessment_error_summaries.error_count + 1,
                        last_seen_at = now()
                    """,
                    (learner_id, assessment.language, question.skill_id, error_category),
                )

        progress_rows = connection.execute(
            """
            SELECT skill_id, attempts, correct_count, mastery,
                   average_response_ms, next_review_at, updated_at
            FROM resonant.skill_progress
            WHERE learner_id = %s AND skill_id = ANY(%s)
            """,
            (learner_id, skill_ids),
        ).fetchall()
        error_rows = connection.execute(
            """
            SELECT skill_id, error_category, error_count
            FROM resonant.assessment_error_summaries
            WHERE learner_id = %s AND skill_id = ANY(%s)
            """,
            (learner_id, skill_ids),
        ).fetchall()
        prior_bandit_rows = connection.execute(
            """
            SELECT evidence, succeeded
            FROM resonant.adaptive_decisions
            WHERE learner_id = %s AND succeeded IS NOT NULL
            ORDER BY created_at DESC
            LIMIT 100
            """,
            (learner_id,),
        ).fetchall()
        decision = _adaptive_decision(
            assessment,
            [dict(row) for row in progress_rows],
            prior_progress_rows=[dict(row) for row in prior_progress_rows],
            history_row=dict(history_row) if history_row else None,
            error_rows=[dict(row) for row in error_rows],
            prior_bandit_decisions=[dict(row) for row in prior_bandit_rows],
            prior_remediation_count=prior_remediation_count,
        )
        prediction_skill = (
            decision["recommended_skill_id"] or assessment.questions[0].skill_id
        )
        prediction_question = next(
            (
                question
                for question in assessment.questions
                if question.skill_id == prediction_skill
            ),
            assessment.questions[0],
        )
        prediction = build_prediction(
            connection,
            learner_id=learner_id,
            skill_id=prediction_skill,
            language=assessment.language,
            question_type=prediction_question.exercise_type,
            current_difficulty=assessment.difficulty,
            prediction_time=datetime.now(timezone.utc),
        )
        persist_prediction(
            connection,
            learner_id=learner_id,
            skill_id=prediction_skill,
            language=assessment.language,
            prediction=prediction,
        )
        decision = hybridize_decision(
            decision,
            prediction,
            current_difficulty=assessment.difficulty,
        )
        if decision["action"] in {
            "reinforce", "remediate", "remedial_practice",
            "revisit_prerequisite", "reassess", "schedule_revision",
            "revise",
        }:
            try:
                question = select_adaptive_question(
                    learner_id=str(learner_id),
                    skill_id=prediction_skill,
                    lesson_id=decision["recommended_lesson_id"],
                    language=assessment.language,
                    difficulty=decision["difficulty_after"],
                    recent_question_ids=recent_question_ids(
                        connection,
                        learner_id=learner_id,
                        skill_id=prediction_skill,
                    ),
                    try_ai=False,
                )
                persist_question(
                    connection,
                    learner_id=learner_id,
                    prediction_id=prediction["prediction_id"],
                    question=question,
                )
                decision["question_instance_id"] = question["question_instance_id"]
                decision["evidence"]["next_question"] = {
                    **question,
                    "question_instance_id": str(question["question_instance_id"]),
                }
            except ValueError as error:
                decision["evidence"]["question_fallback_reason"] = str(error)
        connection.execute(
            """
            INSERT INTO resonant.adaptive_decisions (
                decision_id, assessment_id, learner_id, action,
                recommended_skill_id, recommended_lesson_id, reason, evidence,
                confidence, expected_learning_objective, decision_method,
                status, remediation_cycle, mastery_before, mastery_after,
                prediction_id, question_instance_id,
                model_probability_incorrect, model_version,
                difficulty_before, difficulty_after, fallback_used
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s
            )
            """,
            (
                decision["decision_id"],
                assessment_id,
                learner_id,
                decision["action"],
                decision["recommended_skill_id"],
                decision["recommended_lesson_id"],
                decision["reason"],
                Jsonb(decision["evidence"]),
                decision["confidence"],
                decision["expected_learning_objective"],
                decision["decision_method"],
                decision["status"],
                decision["remediation_cycle"],
                decision["mastery_before"],
                decision["mastery_after"],
                decision["prediction_id"],
                decision.get("question_instance_id"),
                decision["model_probability_incorrect"],
                decision["model_version"],
                decision["difficulty_before"],
                decision["difficulty_after"],
                decision["fallback_used"],
            ),
        )

    return {
        **dict(session),
        "duplicate": False,
        "decision": decision,
    }


def update_adaptive_decision_status(
    learner_id,
    decision_id,
    *,
    status: str,
    succeeded: bool | None = None,
    applied_at=None,
    completed_at=None,
) -> dict | None:
    """Idempotently record a validated learner-side decision lifecycle."""
    status_order = {
        "pending": 0,
        "applied": 1,
        "completed": 2,
        "superseded": 3,
    }
    if status not in status_order:
        raise ValueError("adaptive_decision_status_invalid")
    now = datetime.now(timezone.utc)
    with get_connection() as connection:
        existing = connection.execute(
            """
            SELECT decision_id, learner_id, action, recommended_skill_id,
                   recommended_lesson_id, reason, evidence, confidence,
                   expected_learning_objective, decision_method, status,
                   remediation_cycle, mastery_before, mastery_after,
                   applied_at, completed_at, succeeded, created_at,
                   prediction_id, question_instance_id,
                   model_probability_incorrect, model_version,
                   difficulty_before, difficulty_after, fallback_used
            FROM resonant.adaptive_decisions
            WHERE decision_id = %s AND learner_id = %s
            """,
            (decision_id, learner_id),
        ).fetchone()
        if existing is None:
            return None
        current = dict(existing)
        current_status = current.get("status") or "pending"
        if status_order[status] < status_order.get(current_status, 0):
            return current

        resolved_applied_at = current.get("applied_at")
        resolved_completed_at = current.get("completed_at")
        if status in {"applied", "completed"}:
            resolved_applied_at = resolved_applied_at or applied_at or now
        if status in {"completed", "superseded"}:
            resolved_completed_at = resolved_completed_at or completed_at or now

        mastery_row = None
        recommended_skill = current.get("recommended_skill_id")
        if recommended_skill:
            mastery_row = connection.execute(
                """
                SELECT mastery
                FROM resonant.skill_progress
                WHERE learner_id = %s AND skill_id = %s
                """,
                (learner_id, recommended_skill),
            ).fetchone()
        mastery_after = (
            _as_float(
                dict(mastery_row).get("mastery"),
                _as_float(current.get("mastery_after"), 0.0),
            )
            if mastery_row
            else current.get("mastery_after")
        )
        updated = connection.execute(
            """
            UPDATE resonant.adaptive_decisions
            SET status = %s,
                applied_at = %s,
                completed_at = %s,
                succeeded = COALESCE(%s, succeeded),
                mastery_after = COALESCE(%s, mastery_after)
            WHERE decision_id = %s AND learner_id = %s
            RETURNING decision_id, learner_id, action, recommended_skill_id,
                      recommended_lesson_id, reason, evidence, confidence,
                      expected_learning_objective, decision_method, status,
                      remediation_cycle, mastery_before, mastery_after,
                      applied_at, completed_at, succeeded, created_at,
                      prediction_id, question_instance_id,
                      model_probability_incorrect, model_version,
                      difficulty_before, difficulty_after, fallback_used
            """,
            (
                status,
                resolved_applied_at,
                resolved_completed_at,
                succeeded,
                mastery_after,
                decision_id,
                learner_id,
            ),
        ).fetchone()
        return dict(updated) if updated else current


def get_teacher_assessment_report(teacher_id: str, learner_id: str) -> dict | None:
    """Return assessment history only when the learner belongs to the teacher."""
    with get_connection() as connection:
        owner = connection.execute(
            """
            SELECT learner_id
            FROM resonant.learners
            WHERE learner_id = %s AND teacher_id = %s
            """,
            (learner_id, teacher_id),
        ).fetchone()
        if owner is None:
            return None
        sessions = connection.execute(
            """
            SELECT s.assessment_id, s.assessment_key, s.lesson_id, s.language,
                   s.assessment_type, s.difficulty, s.score, s.question_count,
                   s.eligible_question_count,
                   s.duration_ms, s.completed_at, d.decision_id, d.action,
                   d.recommended_skill_id, d.recommended_lesson_id, d.reason,
                   d.evidence, d.confidence, d.expected_learning_objective,
                   d.decision_method, d.status, d.remediation_cycle,
                   d.mastery_before, d.mastery_after, d.applied_at,
                   d.completed_at AS decision_completed_at, d.succeeded,
                   d.prediction_id, d.question_instance_id,
                   d.model_probability_incorrect, d.model_version,
                   d.difficulty_before, d.difficulty_after, d.fallback_used
            FROM resonant.assessment_sessions s
            LEFT JOIN resonant.adaptive_decisions d
              ON d.assessment_id = s.assessment_id
            WHERE s.learner_id = %s
            ORDER BY s.completed_at DESC
            LIMIT 50
            """,
            (learner_id,),
        ).fetchall()
        errors = connection.execute(
            """
            SELECT skill_id, language, error_category, error_count,
                   first_seen_at, last_seen_at
            FROM resonant.assessment_error_summaries
            WHERE learner_id = %s
            ORDER BY error_count DESC, last_seen_at DESC
            LIMIT 20
            """,
            (learner_id,),
        ).fetchall()
        predictions = connection.execute(
            """
            SELECT prediction_id, skill_id, language, prediction_task,
                   probability_incorrect, prediction_source, validity_status,
                   model_version, feature_schema_version, fallback_reason,
                   prediction_latency_ms, predicted_at, linked_submission_id,
                   observed_incorrect, resolved_at
            FROM resonant.ml_predictions
            WHERE learner_id = %s
            ORDER BY predicted_at DESC
            LIMIT 50
            """,
            (learner_id,),
        ).fetchall()
        questions = connection.execute(
            """
            SELECT question_instance_id, prediction_id, skill_id, lesson_id,
                   language, difficulty, question_type, question_source,
                   question_version, mapping_version, curriculum_version,
                   generation_model, generation_failure, validation_status,
                   created_at
            FROM resonant.adaptive_question_instances
            WHERE learner_id = %s
            ORDER BY created_at DESC
            LIMIT 50
            """,
            (learner_id,),
        ).fetchall()

    assessments = []
    for row in sessions:
        item = dict(row)
        question_count = item.get("eligible_question_count")
        if question_count is None:
            question_count = item.get("question_count") or 0
        item["assessment_id"] = str(item["assessment_id"])
        if item.get("decision_id") is not None:
            item["decision_id"] = str(item["decision_id"])
        item["accuracy_pct"] = round(
            (item.get("score", 0) / question_count * 100.0) if question_count else 0.0,
            1,
        )
        assessments.append(item)
    return {
        "recent_assessments": assessments,
        "assessment_error_summary": [dict(row) for row in errors],
        "recent_predictions": [dict(row) for row in predictions],
        "recent_adaptive_questions": [dict(row) for row in questions],
    }
