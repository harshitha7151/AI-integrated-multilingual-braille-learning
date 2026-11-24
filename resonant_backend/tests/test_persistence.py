import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

os.environ.setdefault(
    "RESONANT_JWT_SECRET",
    "resonant-test-only-jwt-secret-never-use-in-production",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import migrate
import progress_service


class FakeCursor:
    def __init__(self, row=None, rows=None):
        self.row = row
        self.rows = rows or []

    def fetchone(self):
        return self.row

    def fetchall(self):
        return self.rows


class FakeConnection:
    def __init__(self, insert_row=None, existing_row=None, migration_rows=None):
        self.calls = []
        self.insert_row = insert_row
        self.existing_row = existing_row
        self.migration_rows = migration_rows or []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, sql, params=None):
        self.calls.append((sql, params))
        if "INSERT INTO resonant.practice_attempts" in sql:
            return FakeCursor(self.insert_row)
        if "FROM resonant.practice_attempts WHERE submission_id" in sql:
            return FakeCursor(self.existing_row)
        if "INSERT INTO resonant.quiz_results" in sql:
            return FakeCursor(self.insert_row)
        if "FROM resonant.quiz_results WHERE submission_id" in sql:
            return FakeCursor(self.existing_row)
        if "INSERT INTO resonant.learners" in sql:
            return FakeCursor(self.insert_row)
        if "SELECT version FROM resonant.schema_migrations" in sql:
            return FakeCursor(rows=self.migration_rows)
        return FakeCursor()


class PersistenceTests(unittest.TestCase):
    def test_learner_write_uses_the_isolated_schema_and_parameters(self):
        learner_id = uuid4()
        connection = FakeConnection(
            insert_row={"learner_id": learner_id, "username": "Learner"}
        )
        with patch.object(progress_service, "get_connection", return_value=connection):
            learner = progress_service.create_learner("Learner", "English")

        self.assertEqual(learner["learner_id"], learner_id)
        self.assertIn("resonant.learners", connection.calls[0][0])
        self.assertEqual(connection.calls[0][1][1:], ("Learner", "English", None))

    def test_legacy_learner_upsert_cannot_update_another_teachers_username(self):
        connection = FakeConnection(insert_row=None)
        with patch.object(progress_service, "get_connection", return_value=connection):
            with self.assertRaisesRegex(ValueError, "username_conflict"):
                progress_service.create_learner(
                    "Existing learner", "Kannada", teacher_id="teacher-b",
                )

        self.assertIn(
            "IS NOT DISTINCT FROM EXCLUDED.teacher_id",
            connection.calls[0][0],
        )

    def test_new_migration_isolated_in_its_schema_and_versioned(self):
        connection = FakeConnection()
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "001_initial.sql").write_text(
                "CREATE TABLE resonant.learners (learner_id UUID);",
                encoding="utf-8",
            )
            applied = migrate.run_migrations(lambda: connection, Path(directory))

        self.assertEqual(applied, [1])
        statements = [sql for sql, _ in connection.calls]
        self.assertIn("CREATE SCHEMA IF NOT EXISTS resonant", statements)
        self.assertTrue(any("INSERT INTO resonant.schema_migrations" in sql for sql in statements))
        self.assertTrue(any("CREATE TABLE resonant.learners" in sql for sql in statements))

    def test_attempt_insert_is_parameterized_and_updates_mastery_once(self):
        row = {
            "submission_id": uuid4(),
            "attempt_id": 1,
            "learner_id": uuid4(),
            "skill_id": "english-a",
            "outcome": "correct",
        }
        connection = FakeConnection(insert_row=row)
        attempt = SimpleNamespace(
            submission_id=row["submission_id"],
            learner_id=row["learner_id"],
            exercise_id="letter-a",
            skill_id="english-a",
            language="English",
            exercise_type="letter_recognition",
            outcome="correct",
            response_time_ms=1300,
            hint_used=False,
            attempt_number=1,
        )
        with patch.object(progress_service, "get_connection", return_value=connection):
            result = progress_service.record_practice_attempt(attempt)

        self.assertFalse(result["duplicate"])
        attempt_sql = connection.calls[0][0]
        self.assertIn("ON CONFLICT (submission_id) DO NOTHING", attempt_sql)
        self.assertIn("INSERT INTO resonant.skill_progress", connection.calls[1][0])
        self.assertIn("CASE WHEN EXCLUDED.correct_count = 1 THEN", connection.calls[1][0])
        self.assertIn("next_review_at = now() +", connection.calls[1][0])
        self.assertNotIn("letter-a", attempt_sql)

    def test_word_attempt_updates_only_reported_letter_skills_once(self):
        row = {
            "submission_id": uuid4(), "attempt_id": 11,
            "learner_id": uuid4(), "outcome": "incorrect",
        }
        connection = FakeConnection(insert_row=row)
        attempt = SimpleNamespace(
            submission_id=row["submission_id"], learner_id=row["learner_id"],
            exercise_id="word-cat", skill_id="english-word-writing-test",
            language="English", exercise_type="transcription",
            outcome="incorrect", response_time_ms=1200, hint_used=False,
            attempt_number=1, input_status="valid",
            expected_response={"text": "CAT"},
            submitted_response={"cells": [5, 1, 20], "skill_observations": [
                {"character": "C", "skill_id": "english-letter-c", "correct": True},
                {"character": "A", "skill_id": "english-letter-a", "correct": True},
                {"character": "T", "skill_id": "english-letter-t", "correct": False},
            ]},
        )
        with patch.object(progress_service, "get_connection", return_value=connection), \
             patch("resonant_ml_service.resolve_previous_prediction"):
            progress_service.record_practice_attempt(attempt)

        updates = [
            params for sql, params in connection.calls
            if "INSERT INTO resonant.skill_progress" in sql
        ]
        self.assertEqual([params[1] for params in updates], [
            "english-word-writing-test",
            "english-letter-c",
            "english-letter-a",
            "english-letter-t",
        ])
        self.assertEqual([params[3] for params in updates], [0, 1, 1, 0])

    def test_practice_attempt_persists_deterministic_dot_error_classification(self):
        row = {"submission_id": uuid4(), "attempt_id": 12, "outcome": "incorrect"}
        connection = FakeConnection(insert_row=row)
        attempt = SimpleNamespace(
            submission_id=row["submission_id"], learner_id=uuid4(),
            exercise_id="letter-a", skill_id="english-letter-a", language="English",
            exercise_type="braille_writing", outcome="incorrect",
            response_time_ms=1400, hint_used=False, attempt_number=1,
            expected_response={"text": "A", "cells": [1]},
            submitted_response={"cells": [3]},
        )
        with patch.object(progress_service, "get_connection", return_value=connection), \
             patch("resonant_ml_service.resolve_previous_prediction"):
            progress_service.record_practice_attempt(attempt)

        saved_response = connection.calls[0][1][15].obj
        self.assertEqual(saved_response["cells"], [3])
        self.assertEqual(saved_response["error_analysis"]["category"], "extra_dot")
        self.assertEqual(saved_response["error_analysis"]["extra_dots"], [
            {"cell_index": 0, "dots": [2]}
        ])

    def test_skill_observations_cannot_claim_a_character_outside_the_word(self):
        from types import SimpleNamespace

        with self.assertRaisesRegex(ValueError, "invalid_skill_observation"):
            progress_service._validated_skill_observations(SimpleNamespace(
                language="English",
                expected_response={"text": "CAT"},
                submitted_response={"skill_observations": [
                    {"character": "Z", "skill_id": "english-letter-z", "correct": False},
                ]},
            ))

    def test_duplicate_attempt_returns_saved_record_without_second_progress_update(self):
        row = {"submission_id": uuid4(), "attempt_id": 7, "outcome": "incorrect"}
        connection = FakeConnection(insert_row=None, existing_row=row)
        attempt = SimpleNamespace(
            submission_id=row["submission_id"], learner_id=uuid4(),
            exercise_id="letter-a", skill_id="english-a", language="English",
            exercise_type="letter_recognition", outcome="incorrect",
            response_time_ms=800, hint_used=True, attempt_number=2,
            input_status="valid", expected_response={"text": "a"},
            submitted_response={"skill_observations": [
                {"character": "a", "skill_id": "english-letter-a", "correct": False},
            ]},
        )
        with patch.object(progress_service, "get_connection", return_value=connection):
            result = progress_service.record_practice_attempt(attempt)

        self.assertTrue(result["duplicate"])
        self.assertEqual(len(connection.calls), 2)

    def test_non_answer_touch_events_are_saved_but_do_not_change_mastery(self):
        row = {"submission_id": uuid4(), "attempt_id": 9, "outcome": "cancelled"}
        connection = FakeConnection(insert_row=row)
        attempt = SimpleNamespace(
            submission_id=row["submission_id"], learner_id=uuid4(),
            exercise_id="letter-a", skill_id="english-a", language="English",
            exercise_type="letter_recognition", outcome="cancelled",
            response_time_ms=500, hint_used=False, attempt_number=1,
        )
        with patch.object(progress_service, "get_connection", return_value=connection):
            result = progress_service.record_practice_attempt(attempt)

        self.assertEqual(result["outcome"], "cancelled")
        self.assertEqual(len(connection.calls), 1)

    def test_quiz_result_uses_submission_id_for_idempotency(self):
        row = {"submission_id": uuid4(), "quiz_result_id": 4, "score": 3}
        connection = FakeConnection(insert_row=row)
        quiz = SimpleNamespace(
            submission_id=row["submission_id"], learner_id=uuid4(),
            quiz_id="english-basics", language="English", score=3,
            max_score=4, duration_ms=9000,
        )
        with patch.object(progress_service, "get_connection", return_value=connection):
            result = progress_service.record_quiz_result(quiz)

        self.assertFalse(result["duplicate"])
        self.assertIn("ON CONFLICT (submission_id) DO NOTHING", connection.calls[0][0])

    def test_quiz_score_cannot_exceed_total(self):
        from fastapi import HTTPException
        import main

        result = main.QuizResultCreate(
            submission_id=uuid4(), learner_id=uuid4(), quiz_id="q1",
            learner_code="123456", language="English", score=4, max_score=3,
            duration_ms=1000,
        )
        with self.assertRaises(HTTPException) as error:
            main.create_quiz_result(result)
        self.assertEqual(error.exception.status_code, 422)


if __name__ == "__main__":
    unittest.main()
