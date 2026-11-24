import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

os.environ.setdefault(
    "RESONANT_JWT_SECRET",
    "resonant-test-only-jwt-secret-never-use-in-production",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import assessment_service
import main


class FakeCursor:
    def __init__(self, row=None, rows=None):
        self._row = row
        self._rows = rows or []

    def fetchone(self):
        return self._row

    def fetchall(self):
        return self._rows


class AssessmentConnection:
    def __init__(
        self,
        *,
        session_row=None,
        duplicate_row=None,
        progress_rows=None,
        owner_row=None,
        report_rows=None,
        error_rows=None,
        prediction_rows=None,
        adaptive_question_rows=None,
        decision_row=None,
        updated_decision_row=None,
        mastery_row=None,
    ):
        self.calls = []
        self.session_row = session_row
        self.duplicate_row = duplicate_row
        self.progress_rows = progress_rows or []
        self.owner_row = owner_row
        self.report_rows = report_rows or []
        self.error_rows = error_rows or []
        self.prediction_rows = prediction_rows or []
        self.adaptive_question_rows = adaptive_question_rows or []
        self.decision_row = decision_row
        self.updated_decision_row = updated_decision_row
        self.mastery_row = mastery_row

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, sql, params=None):
        self.calls.append((sql, params))
        if "INSERT INTO resonant.assessment_sessions" in sql:
            return FakeCursor(row=self.session_row)
        if "WHERE s.submission_id = %s" in sql:
            return FakeCursor(row=self.duplicate_row)
        if "FROM resonant.skill_progress" in sql and "ANY(%s)" in sql:
            return FakeCursor(rows=self.progress_rows)
        if "FROM resonant.skill_progress" in sql and "skill_id = %s" in sql:
            return FakeCursor(row=self.mastery_row)
        if "FROM resonant.adaptive_decisions" in sql and "decision_id = %s" in sql:
            return FakeCursor(row=self.decision_row)
        if "UPDATE resonant.adaptive_decisions" in sql:
            return FakeCursor(row=self.updated_decision_row)
        if "FROM resonant.learners" in sql and "teacher_id = %s" in sql:
            return FakeCursor(row=self.owner_row)
        if "FROM resonant.assessment_sessions s" in sql:
            return FakeCursor(rows=self.report_rows)
        if "FROM resonant.assessment_error_summaries" in sql:
            return FakeCursor(rows=self.error_rows)
        if "FROM resonant.ml_predictions" in sql:
            return FakeCursor(rows=self.prediction_rows)
        if "FROM resonant.adaptive_question_instances" in sql:
            return FakeCursor(rows=self.adaptive_question_rows)
        return FakeCursor()


def question(**overrides):
    values = {
        "question_id": "lesson-assessment-letter-a",
        "skill_id": "english-letter-a",
        "exercise_type": "letter_recognition",
        "learning_objective": "Recognize the uncontracted English letter a.",
        "difficulty": 1,
        "question_text": "Which letter uses dot 1?",
        "options": ["a", "b", "c", "d"],
        "expected_response": {"choice": "a", "cells": [1]},
        "submitted_response": {"choice": "a", "cells": [1]},
        "correct": True,
        "attempts": 1,
        "response_time_ms": 900,
        "hint_used": False,
        "error_category": None,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def assessment(*questions):
    return SimpleNamespace(
        submission_id=uuid4(),
        assessment_key="lesson-letter-a-v1",
        lesson_id="letter-a",
        language="English",
        assessment_type="lesson",
        difficulty=1,
        generated_content_version="flutter-catalog-v1",
        duration_ms=900,
        started_at=None,
        completed_at=datetime.now(timezone.utc),
        questions=list(questions),
    )


class AssessmentValidationTests(unittest.TestCase):
    def test_adaptive_decision_prioritizes_due_review_over_lower_mastery_not_due(self):
        now = datetime.now(timezone.utc)
        result = assessment_service._adaptive_decision(
            assessment(
                question(),
                question(
                    question_id="lesson-assessment-letter-b",
                    skill_id="english-letter-b",
                    expected_response={"choice": "b", "cells": [3]},
                    submitted_response={"choice": "b", "cells": [3]},
                ),
            ),
            [
                {
                    "skill_id": "english-letter-a",
                    "mastery": 0.3,
                    "next_review_at": now + timedelta(days=3),
                },
                {
                    "skill_id": "english-letter-b",
                    "mastery": 0.8,
                    "next_review_at": now - timedelta(days=1),
                },
            ],
        )

        self.assertEqual(result["recommended_skill_id"], "english-letter-b")
        self.assertTrue(result["evidence"]["review_due"])
        self.assertEqual(result["evidence"]["review_due_skills"], ["english-letter-b"])
        self.assertIn("scheduled skill review is due", result["reason"])

    def test_decision_uses_contextual_bandit_after_persisted_outcome_threshold(self):
        available = [
            {"skill_id": "english-letter-a", "mastery": 0.7,
             "attempts": 5, "review_due": False,
             "information_gain_bits": 0.1,
             "forgetting_risk_estimate": 0.1, "error_count": 0},
            {"skill_id": "english-letter-b", "mastery": 0.3,
             "attempts": 5, "review_due": True,
             "information_gain_bits": 0.3,
             "forgetting_risk_estimate": 0.4, "error_count": 2},
        ]
        prior_decisions = [
            {
                "succeeded": True,
                "evidence": {
                    "eligible_skill_scores": available,
                    "selected_skill_for_next_exercise": available[1],
                },
            }
            for _ in range(5)
        ]
        result = assessment_service._adaptive_decision(
            assessment(
                question(),
                question(
                    question_id="lesson-assessment-letter-b",
                    skill_id="english-letter-b",
                    expected_response={"choice": "b", "cells": [3]},
                    submitted_response={"choice": "b", "cells": [3]},
                ),
            ),
            available,
            prior_bandit_decisions=prior_decisions,
        )
        self.assertEqual(
            result["evidence"]["adaptive_selection_method"],
            "linucb_with_information_gain_forgetting_context",
        )
        self.assertEqual(result["evidence"]["bandit_observation_count"], 5)
        self.assertTrue(all("bandit_score" in row for row in result["evidence"]["eligible_skill_scores"]))

    def test_verified_letter_question_is_accepted(self):
        assessment_service.validate_question(question(), "English")

    def test_mismatched_skill_or_claimed_correctness_is_rejected(self):
        with self.assertRaises(ValueError):
            assessment_service.validate_question(
                question(expected_response={"choice": "b", "cells": [3]}),
                "English",
            )

    def test_sentence_transcription_accepts_validated_cell_only_input(self):
        expected = assessment_service._verified_cells("My name is Sam.", "English")
        self.assertIsNotNone(expected)
        assessment_service.validate_question(
            question(
                question_id="en-sentence-personal-name",
                skill_id="english-sentence-personal-name",
                exercise_type="transcription",
                question_text="Write My name is Sam.",
                options=[],
                expected_response={"text": "My name is Sam.", "cells": expected},
                submitted_response={"cells": expected},
                correct=True,
            ),
            "English",
        )
        wrong = list(expected)
        wrong[-1] = 0
        assessment_service.validate_question(
            question(
                question_id="en-sentence-personal-name",
                skill_id="english-sentence-personal-name",
                exercise_type="transcription",
                question_text="Write My name is Sam.",
                options=[],
                expected_response={"text": "My name is Sam.", "cells": expected},
                submitted_response={"cells": wrong},
                correct=False,
            ),
            "English",
        )
        with self.assertRaises(ValueError):
            assessment_service.validate_question(
                question(
                    submitted_response={"choice": "b", "cells": [3]},
                    correct=True,
                ),
                "English",
            )
        with self.assertRaises(ValueError):
            assessment_service.validate_question(
                question(
                    submitted_response={"choice": "b", "cells": [1]},
                    correct=False,
                ),
                "English",
            )

    def test_dot_and_character_errors_are_categorized_deterministically(self):
        self.assertEqual(
            assessment_service.categorize_error(
                {"cells": [3]},
                {"cells": [1]},
            ),
            "missing_dot",
        )
        self.assertEqual(
            assessment_service.categorize_error(
                {"cells": [1]},
                {"cells": [3]},
            ),
            "extra_dot",
        )
        self.assertEqual(
            assessment_service.categorize_error(
                {"choice": "a"},
                {"choice": "b"},
            ),
            "character_confusion",
        )


class AssessmentPersistenceTests(unittest.TestCase):
    def test_assessment_is_transactional_and_updates_mastery_and_decision(self):
        learner_id = uuid4()
        session_row = {
            "assessment_id": uuid4(),
            "submission_id": uuid4(),
            "learner_id": learner_id,
            "assessment_key": "lesson-letter-a-v1",
            "lesson_id": "letter-a",
            "score": 1,
            "question_count": 1,
        }
        connection = AssessmentConnection(
            session_row=session_row,
            progress_rows=[{"skill_id": "english-letter-a", "mastery": 0.67}],
        )
        data = assessment(question())
        with patch.object(
            assessment_service,
            "get_connection",
            return_value=connection,
        ):
            result = assessment_service.record_assessment(learner_id, data)

        statements = [sql for sql, _ in connection.calls]
        self.assertFalse(result["duplicate"])
        self.assertEqual(result["decision"]["action"], "advance")
        self.assertEqual(result["decision"]["difficulty_before"], 1)
        self.assertEqual(result["decision"]["difficulty_after"], 2)
        self.assertEqual(
            result["decision"]["evidence"]["adaptive_selection_method"],
            "information_gain_forget_risk_rules_cold_start",
        )
        self.assertEqual(
            result["decision"]["evidence"]["selected_skill_for_next_exercise"]["skill_id"],
            "english-letter-a",
        )
        self.assertTrue(any("assessment_questions" in sql for sql in statements))
        self.assertTrue(any("assessment_attempts" in sql for sql in statements))
        self.assertTrue(any("skill_progress" in sql for sql in statements))
        self.assertTrue(any("adaptive_decisions" in sql for sql in statements))
        self.assertTrue(any(
            "succeeded IS NOT NULL" in sql and "LIMIT 100" in sql
            for sql in statements
        ))

    def test_incorrect_assessment_updates_error_summary_and_remediation(self):
        learner_id = uuid4()
        connection = AssessmentConnection(
            session_row={"assessment_id": uuid4(), "score": 0, "question_count": 1},
            progress_rows=[{"skill_id": "english-letter-a", "mastery": 0.2}],
        )
        wrong = question(
            submitted_response={"choice": "b", "cells": [3]},
            correct=False,
            attempts=2,
        )
        with patch.object(
            assessment_service,
            "get_connection",
            return_value=connection,
        ):
            result = assessment_service.record_assessment(
                learner_id,
                assessment(wrong),
            )

        self.assertEqual(result["decision"]["action"], "revisit_prerequisite")
        self.assertTrue(
            any(
                "assessment_error_summaries" in sql
                for sql, _ in connection.calls
            )
        )

    def test_repeated_remediation_is_capped_with_reassessment(self):
        wrong = question(
            submitted_response={"choice": "b", "cells": [3]},
            correct=False,
        )
        decision = assessment_service._adaptive_decision(
            assessment(wrong),
            [{"skill_id": "english-letter-a", "mastery": 0.2}],
            prior_progress_rows=[
                {"skill_id": "english-letter-a", "mastery": 0.25}
            ],
            error_rows=[
                {"error_category": "substitution", "error_count": 3}
            ],
            prior_remediation_count=2,
        )
        self.assertEqual(decision["action"], "reassess")
        self.assertEqual(decision["decision_method"], "deterministic_rules")
        self.assertEqual(decision["evidence"]["repeated_error_count"], 3)

    def test_decision_lifecycle_records_success_and_server_mastery(self):
        learner_id = uuid4()
        decision_id = uuid4()
        existing = {
            "decision_id": decision_id,
            "learner_id": learner_id,
            "status": "applied",
            "recommended_skill_id": "english-letter-a",
            "mastery_after": 0.4,
            "applied_at": datetime.now(timezone.utc),
        }
        updated = {
            **existing,
            "status": "completed",
            "succeeded": True,
            "mastery_after": 0.75,
        }
        connection = AssessmentConnection(
            decision_row=existing,
            updated_decision_row=updated,
            mastery_row={"mastery": 0.75},
        )
        with patch.object(
            assessment_service,
            "get_connection",
            return_value=connection,
        ):
            result = assessment_service.update_adaptive_decision_status(
                learner_id,
                decision_id,
                status="completed",
                succeeded=True,
            )

        self.assertEqual(result["status"], "completed")
        self.assertTrue(result["succeeded"])
        update_params = next(
            params
            for sql, params in connection.calls
            if "UPDATE resonant.adaptive_decisions" in sql
        )
        self.assertEqual(update_params[4], 0.75)

    def test_teacher_report_is_scoped_to_the_owning_teacher(self):
        learner_id = uuid4()
        assessment_id = uuid4()
        connection = AssessmentConnection(
            owner_row={"learner_id": learner_id},
            report_rows=[{
                "assessment_id": assessment_id,
                "lesson_id": "letter-a",
                "score": 1,
                "question_count": 1,
                "status": "completed",
                "succeeded": True,
                "mastery_before": 0.4,
                "mastery_after": 0.75,
                "evidence": {
                    "adaptive_selection_method": "information_gain_forget_risk_rules_cold_start",
                    "eligible_skill_scores": [{
                        "skill_id": "english-letter-a",
                        "information_gain_bits": 0.2,
                        "forgetting_risk_estimate": 0.1,
                    }],
                },
            }],
            error_rows=[{
                "skill_id": "english-letter-b",
                "language": "English",
                "error_category": "character_confusion",
                "error_count": 2,
            }],
            prediction_rows=[{
                "prediction_id": uuid4(),
                "skill_id": "english-letter-a",
                "language": "English",
                "prediction_source": "cold_start_deterministic",
                "validity_status": "fallback",
                "feature_schema_version": "resonant-next-attempt-v2",
            }],
            adaptive_question_rows=[{
                "question_instance_id": uuid4(),
                "skill_id": "english-letter-a",
                "lesson_id": "letter-a",
                "language": "English",
                "question_source": "validated_bank",
                "validation_status": "validated",
            }],
        )
        with patch.object(
            assessment_service,
            "get_connection",
            return_value=connection,
        ):
            report = assessment_service.get_teacher_assessment_report(
                "teacher-1",
                str(learner_id),
            )

        self.assertEqual(report["recent_assessments"][0]["accuracy_pct"], 100.0)
        self.assertTrue(report["recent_assessments"][0]["succeeded"])
        self.assertEqual(report["recent_assessments"][0]["mastery_after"], 0.75)
        self.assertEqual(
            report["recent_assessments"][0]["evidence"]["eligible_skill_scores"][0]["information_gain_bits"],
            0.2,
        )
        self.assertEqual(report["assessment_error_summary"][0]["error_count"], 2)
        self.assertEqual(
            report["recent_predictions"][0]["prediction_source"],
            "cold_start_deterministic",
        )
        self.assertEqual(
            report["recent_adaptive_questions"][0]["validation_status"],
            "validated",
        )
        self.assertEqual(connection.calls[0][1], (str(learner_id), "teacher-1"))


class AssessmentApiTests(unittest.TestCase):
    def _payload(self, **overrides):
        values = {
            "submission_id": uuid4(),
            "learner_code": "012345",
            "assessment_key": "lesson-letter-a-v1",
            "lesson_id": "letter-a",
            "language": "English",
            "assessment_type": "lesson",
            "difficulty": 1,
            "generated_content_version": "flutter-catalog-v1",
            "duration_ms": 900,
            "questions": [{
                "question_id": "lesson-assessment-letter-a",
                "skill_id": "english-letter-a",
                "exercise_type": "letter_recognition",
                "learning_objective": "Recognize letter a.",
                "difficulty": 1,
                "question_text": "Which letter uses dot 1?",
                "options": ["a", "b", "c", "d"],
                "expected_response": {"choice": "a", "cells": [1]},
                "submitted_response": {"choice": "a", "cells": [1]},
                "correct": True,
                "attempts": 1,
                "response_time_ms": 900,
            }],
        }
        values.update(overrides)
        return main.LessonAssessmentCreate(**values)

    def test_invalid_learner_code_is_rejected(self):
        with patch.object(
            main.registration_service,
            "verify_learner_code",
            return_value=False,
        ):
            with self.assertRaises(main.HTTPException) as caught:
                main.create_lesson_assessment(uuid4(), self._payload())
        self.assertEqual(caught.exception.status_code, 401)

    def test_valid_assessment_reaches_service(self):
        expected = {"assessment_id": "saved", "duplicate": False}
        with patch.object(
            main.registration_service,
            "verify_learner_code",
            return_value=True,
        ), patch.object(main, "record_assessment", return_value=expected):
            result = main.create_lesson_assessment(uuid4(), self._payload())
        self.assertEqual(result, expected)

    def test_teacher_assessment_report_returns_404_across_accounts(self):
        with patch.object(main, "get_teacher_assessment_report", return_value=None):
            with self.assertRaises(main.HTTPException) as caught:
                main.teacher_learner_assessments(uuid4(), teacher_id="other-teacher")
        self.assertEqual(caught.exception.status_code, 404)

    def test_adaptive_lifecycle_requires_learner_proof_and_routes_update(self):
        learner_id = uuid4()
        decision_id = uuid4()
        data = main.AdaptiveDecisionStatusUpdate(
            learner_code="012345",
            status="completed",
            succeeded=True,
        )
        with patch.object(
            main.registration_service,
            "verify_learner_code",
            return_value=True,
        ), patch.object(
            main,
            "update_adaptive_decision_status",
            return_value={"decision_id": decision_id, "status": "completed"},
        ) as update:
            result = main.update_learner_adaptive_decision(
                learner_id,
                decision_id,
                data,
            )
        self.assertEqual(result["status"], "completed")
        update.assert_called_once()


if __name__ == "__main__":
    unittest.main()
