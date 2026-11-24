import os
import sys
import json
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import requests
from pydantic import ValidationError

os.environ.setdefault(
    "RESONANT_JWT_SECRET",
    "resonant-test-only-jwt-secret-never-use-in-production",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main
from adaptive_ml import FEATURE_NAMES, predict_probability
from train_adaptive_demo import generate_synthetic_examples, train_and_evaluate
from recommendation_service import recommend_from_progress
from verified_braille import verified_single_letter, verified_uncontracted_word


class ApiTests(unittest.TestCase):
    def test_contextual_intent_interpreter_returns_validated_action_candidate(self):
        class Response:
            def raise_for_status(self):
                pass

            def json(self):
                return {"message": {"content": (
                    '{"intent":"start_word_test","target":"words",'
                    '"language_target":null,"letter":null,"option_index":null,'
                    '"confidence":0.91,"clarification":null,'
                    '"reasoning_summary":"The learner requests a words assessment."}'
                )}}

        data = main.TutorIntentRequest(
            utterance="I want to test myself with words",
            language="English",
            screen_context="Screen: active letter assessment; answers are not submitted.",
            history=[{"role": "user", "content": "I'm tired of this quiz."}],
            available_actions=["ask_tutor", "start_word_test", "exit_assessment"],
        )
        with patch.object(main.requests, "post", return_value=Response()) as ollama:
            result = main.interpret_tutor_intent(data)
        self.assertEqual(result.intent, "start_word_test")
        self.assertEqual(result.confidence, 0.91)
        self.assertIn("active letter assessment", ollama.call_args.kwargs["json"]["messages"][1]["content"])
        self.assertIn("I'm tired of this quiz", ollama.call_args.kwargs["json"]["messages"][1]["content"])
        self.assertIn('"start_word_test"', ollama.call_args.kwargs["json"]["messages"][1]["content"])
        self.assertEqual(ollama.call_args.kwargs["json"]["format"], main.TutorIntentResult.model_json_schema())

    def test_contextual_intent_interpreter_handles_kannada_and_clarification(self):
        class Response:
            def raise_for_status(self):
                pass

            def json(self):
                return {"message": {"content": (
                    '{"intent":"switch_language","target":null,'
                    '"language_target":"English","letter":null,"option_index":null,'
                    '"confidence":0.88,"clarification":null,'
                    '"reasoning_summary":"Kannada phrase requests English content."}'
                )}}

        with patch.object(main.requests, "post", return_value=Response()) as ollama:
            result = main.interpret_tutor_intent(main.TutorIntentRequest(
                utterance="ಇಂಗ್ಲಿಷ್‌ಗೆ ಬದಲಾಯಿಸು", language="Kannada",
                available_actions=["ask_tutor", "switch_language"],
            ))
        self.assertEqual(result.intent, "switch_language")
        self.assertIn("Selected content language: Kannada", ollama.call_args.kwargs["json"]["messages"][1]["content"])

    def test_contextual_intent_interpreter_reports_model_failure_and_rejects_bad_schema(self):
        request = main.TutorIntentRequest(
            utterance="Let's do something", language="English",
            available_actions=["ask_tutor", "go_to_lesson"],
        )
        with patch.object(main.requests, "post", side_effect=requests.Timeout()):
            with self.assertRaises(main.HTTPException) as timeout:
                main.interpret_tutor_intent(request)
        self.assertEqual(timeout.exception.status_code, 504)

        class InvalidResponse:
            def raise_for_status(self):
                pass

            def json(self):
                return {"message": {"content": '{"intent":"delete_account","confidence":1}'}}

        with patch.object(main.requests, "post", return_value=InvalidResponse()):
            with self.assertRaises(main.HTTPException) as invalid:
                main.interpret_tutor_intent(request)
        self.assertEqual(invalid.exception.status_code, 502)

    def test_contextual_tool_selection_is_semantic_test_data_not_phrase_routing(self):
        utterances = [
            ("English", "Maybe I should work on vocabulary instead", "open_word_lessons"),
            ("Hindi", "मुझे अब शब्दों का अभ्यास करना है", "open_word_lessons"),
            ("Kannada", "ಪದಗಳನ್ನು ಕಲಿಯೋಣ", "open_word_lessons"),
            ("Hindi", "English kalna hai", "switch_language"),
            ("Kannada", "ನನಗೆ ಇಂಗ್ಲಿಷ್ ಕಲಿಯಬೇಕು", "switch_language"),
            ("English", "I don't want to continue this test", "exit_assessment"),
        ]

        class Response:
            def __init__(self, intent):
                self.intent = intent

            def raise_for_status(self):
                pass

            def json(self):
                language_target = "English" if self.intent == "switch_language" else None
                return {"message": {"content": json.dumps({
                    "intent": self.intent,
                    "target": None,
                    "language_target": language_target,
                    "letter": None,
                    "option_index": None,
                    "confidence": 0.91,
                    "clarification": None,
                    "reasoning_summary": "The current request and context identify this capability.",
                })}}

        for language, utterance, intent in utterances:
            available = ["ask_tutor", intent]
            request = main.TutorIntentRequest(
                utterance=utterance,
                language=language,
                screen_context={"screen": "learning", "assessment_active": intent == "exit_assessment"},
                available_actions=available,
            )
            with self.subTest(language=language, utterance=utterance), patch.object(
                main.requests, "post", return_value=Response(intent)
            ) as model:
                result = main.interpret_tutor_intent(request)
            self.assertEqual(result.intent, intent)
            model_prompt = model.call_args.kwargs["json"]["messages"][1]["content"]
            self.assertIn(utterance, model_prompt)
            self.assertIn(intent, model_prompt)

    def test_proposal_for_unavailable_screen_capability_becomes_clarification(self):
        class Response:
            def raise_for_status(self):
                pass

            def json(self):
                return {"message": {"content": json.dumps({
                    "intent": "select_answer", "target": None, "language_target": None,
                    "letter": None, "option_index": 1, "confidence": 0.95,
                    "clarification": None, "reasoning_summary": "Selected a choice.",
                })}}

        with patch.object(main.requests, "post", return_value=Response()):
            result = main.interpret_tutor_intent(main.TutorIntentRequest(
                utterance="That one", language="English",
                screen_context={"screen": "lesson, no question"},
                available_actions=["ask_tutor", "read_screen"],
            ))
        self.assertEqual(result.intent, "clarify")
        self.assertIsNone(result.option_index)

    def test_private_fields_are_removed_from_context_and_redacted_from_history(self):
        class Response:
            def raise_for_status(self):
                pass

            def json(self):
                return {"message": {"content": json.dumps({
                    "intent": "ask_tutor", "target": None,
                    "language_target": None, "letter": None,
                    "option_index": None, "confidence": 0.9,
                    "clarification": None, "reasoning_summary": "A Braille question.",
                })}}

        request = main.TutorIntentRequest(
            utterance="Can you explain this?",
            language="English",
            screen_context={"screen": "lesson", "email": "private@example.test"},
            history=[{"role": "user", "content": "My number is +1 650 555 0199"}],
            available_actions=["ask_tutor"],
        )
        with patch.object(main.requests, "post", return_value=Response()) as model:
            result = main.interpret_tutor_intent(request)
        prompt = model.call_args.kwargs["json"]["messages"][1]["content"]
        self.assertEqual(result.intent, "ask_tutor")
        self.assertNotIn("private@example.test", prompt)
        self.assertNotIn("650 555 0199", prompt)

    def test_unrelated_questions_are_declined_instead_of_sent_to_model(self):
        cases = [
            ("English", "What is the weather today?"),
            ("English", "Explain the weather forecast."),
            ("Hindi", "आज मौसम कैसा है?"),
            ("Kannada", "ಇಂದು ಹವಾಮಾನ ಹೇಗಿದೆ?"),
        ]
        for language, question in cases:
            with self.subTest(language=language), patch.object(
                main.requests,
                "post",
                side_effect=AssertionError("unrelated questions must not reach Ollama"),
            ):
                result = main.ask_tutor(
                    main.TutorQuestion(question=question, language=language)
                )
            self.assertEqual(result["source"], "out_of_scope")
            self.assertTrue(result["answer"])

    def test_rule_baseline_selects_a_due_skill_before_future_review(self):
        from datetime import datetime, timedelta, timezone

        now = datetime.now(timezone.utc)
        result = recommend_from_progress([
            {"skill_id": "future", "attempts": 2, "mastery": 0.2, "next_review_at": now + timedelta(days=1)},
            {"skill_id": "due", "attempts": 3, "mastery": 0.6, "next_review_at": now - timedelta(days=1)},
        ])
        self.assertEqual(result["skill_id"], "due")
        self.assertEqual(result["source"], "rule_baseline")

    def test_rule_baseline_handles_new_learners_without_history(self):
        self.assertEqual(recommend_from_progress([]), {
            "skill_id": None,
            "reason": "no_practice_history",
            "source": "rule_baseline",
        })

    def test_application_health_is_independent_of_services(self):
        self.assertEqual(main.application_health(), {"status": "ok"})

    def test_educational_prediction_request_has_bounded_public_features(self):
        valid = {
            "learner_prior_interactions": 8,
            "learner_prior_success_rate": 0.625,
            "learner_prior_hint_interaction_rate": 0.25,
            "learner_prior_mean_attempts": 1.5,
            "learner_prior_mean_response_ms": 1450.0,
            "skill_prior_interactions": 3,
            "skill_prior_success_rate": 0.6,
            "skill_prior_hint_interaction_rate": 0.33,
            "skill_prior_mean_attempts": 2.0,
            "skill_prior_mean_response_ms": 1600.0,
            "original": 1,
            "position": 17,
            "hint_total": 4,
            "skill_id": "7.0",
            "tutor_mode": "tutor",
            "answer_type": "algebra",
        }
        request = main.EducationalPredictionRequest(**valid)
        self.assertEqual(request.skill_id, "7.0")
        with self.assertRaises(ValidationError):
            main.EducationalPredictionRequest(
                **{**valid, "learner_prior_success_rate": 1.01}
            )
        with self.assertRaises(ValidationError):
            main.EducationalPredictionRequest(
                **{**valid, "answer_type": "learner-identifier"}
            )

    def test_educational_prediction_endpoint_returns_no_learning_action(self):
        data = main.EducationalPredictionRequest(
            learner_prior_interactions=8,
            learner_prior_success_rate=0.625,
            learner_prior_hint_interaction_rate=0.25,
            learner_prior_mean_attempts=1.5,
            learner_prior_mean_response_ms=1450.0,
            skill_prior_interactions=3,
            skill_prior_success_rate=0.6,
            skill_prior_hint_interaction_rate=0.33,
            skill_prior_mean_attempts=2.0,
            skill_prior_mean_response_ms=1600.0,
            original=1,
            position=17,
            hint_total=4,
            skill_id="7.0",
            tutor_mode="tutor",
            answer_type="algebra",
        )
        expected = {
            "prediction": 1,
            "probability_correct": 0.71,
            "model_version": "test-model",
            "experiment_id": "test-experiment",
            "dataset_id": "test-public-data",
            "prediction_target": "first-attempt correctness",
            "experimental": True,
            "learning_action": None,
            "scope": "Experimental only; not a Braille mastery score.",
        }
        with patch.object(
            main, "predict_educational_outcome", return_value=expected
        ) as predict:
            result = main.educational_ml_prediction(data)
        self.assertEqual(result, expected)
        predict.assert_called_once_with(data.model_dump())

    def test_educational_prediction_endpoint_returns_503_without_artifact(self):
        data = main.EducationalPredictionRequest(
            learner_prior_interactions=0,
            learner_prior_success_rate=0.5,
            learner_prior_hint_interaction_rate=0,
            learner_prior_mean_attempts=0,
            learner_prior_mean_response_ms=0,
            skill_prior_interactions=0,
            skill_prior_success_rate=0.5,
            skill_prior_hint_interaction_rate=0,
            skill_prior_mean_attempts=0,
            skill_prior_mean_response_ms=0,
            original=1,
            position=1,
            hint_total=0,
            skill_id="__missing_skill__",
            tutor_mode="__missing__",
            answer_type="__missing__",
        )
        with patch.object(
            main,
            "predict_educational_outcome",
            side_effect=main.EducationalMLUnavailable("missing"),
        ):
            with self.assertRaises(main.HTTPException) as caught:
                main.educational_ml_prediction(data)
        self.assertEqual(caught.exception.status_code, 503)

    def test_resonant_model_status_exposes_cold_start_without_fake_model(self):
        expected = {
            "mode": "cold_start",
            "artifact_status": "artifact_missing",
            "prediction_task": "probability_of_incorrect_future_attempt",
        }
        with patch.object(main, "resonant_model_status", return_value=expected):
            self.assertEqual(main.adaptive_model_status(), expected)

    def test_resonant_prediction_authenticates_builds_and_persists(self):
        from datetime import datetime, timezone
        from uuid import UUID, uuid4

        learner_id = UUID("11111111-1111-4111-8111-111111111111")
        request = main.ResonantPredictionRequest(
            learner_code="012345",
            skill_id="english-letter-a",
            language="English",
            question_type="letter_recognition",
            current_difficulty=2,
        )
        expected = {
            "prediction_id": uuid4(),
            "prediction_task": "probability_of_incorrect_future_attempt",
            "probability_incorrect": 0.5,
            "prediction_source": "cold_start_deterministic",
            "validity_status": "fallback",
            "model_version": None,
            "feature_schema_version": "resonant-next-attempt-v2",
            "fallback_reason": "artifact_missing",
            "prediction_latency_ms": 1,
            "predicted_at": datetime.now(timezone.utc),
        }
        connection = MagicMock()
        connection.__enter__.return_value = connection
        connection.__exit__.return_value = False
        with (
            patch.object(
                main.registration_service,
                "verify_learner_code",
                return_value=True,
            ),
            patch.object(main, "get_connection", return_value=connection),
            patch.object(
                main,
                "build_resonant_prediction",
                return_value=expected,
            ) as build,
            patch.object(main, "persist_resonant_prediction") as persist,
        ):
            result = main.resonant_adaptive_prediction(learner_id, request)

        self.assertEqual(result, expected)
        build.assert_called_once_with(
            connection,
            learner_id=learner_id,
            skill_id="english-letter-a",
            language="English",
            question_type="letter_recognition",
            current_difficulty=2,
        )
        persist.assert_called_once_with(
            connection,
            learner_id=learner_id,
            skill_id="english-letter-a",
            language="English",
            prediction=expected,
        )

    def test_resonant_prediction_rejects_invalid_learner_proof(self):
        from uuid import UUID

        request = main.ResonantPredictionRequest(
            learner_code="012345",
            skill_id="english-letter-a",
            language="English",
            question_type="letter_recognition",
            current_difficulty=1,
        )
        with patch.object(
            main.registration_service,
            "verify_learner_code",
            return_value=False,
        ):
            with self.assertRaises(main.HTTPException) as caught:
                main.resonant_adaptive_prediction(
                    UUID("11111111-1111-4111-8111-111111111111"),
                    request,
                )
        self.assertEqual(caught.exception.status_code, 401)

    def test_tutor_uses_bounded_timeout_and_returns_local_answer(self):
        class Response:
            def raise_for_status(self):
                pass

            def json(self):
                return {"message": {"content": "Try the example in your lesson."}}

        def fake_post(url, json, timeout):
            self.assertEqual(timeout, (3, 20))
            return Response()

        with patch.object(main.requests, "post", side_effect=fake_post):
            response = main.ask_tutor(main.TutorQuestion(question="Give me a hint"))

        self.assertEqual(response["answer"], "Try the example in your lesson.")
        self.assertEqual(response["source"], "ollama")

    def test_general_braille_questions_are_not_misrouted_as_unknown_characters(self):
        class Response:
            def raise_for_status(self): pass
            def json(self): return {"message": {"content": "Braille uses cells with six possible dot positions."}}

        questions = [
            "What is Braille? Explain the six-dot system in simple English.",
            "Explain the six-dot system.",
            "How do I learn letters?",
        ]
        for question in questions:
            with self.subTest(question=question), patch.object(main.requests, "post", return_value=Response()) as ollama:
                result = main.ask_tutor(main.TutorQuestion(question=question))
                self.assertIn(result["source"], {"ollama", "ollama_rag"})
                self.assertIn("six possible", result["answer"])
                ollama.assert_called_once()

    def test_concepts_are_routed_to_ollama_in_selected_languages(self):
        cases = [("Hindi", "ब्रेल क्या है?", "Braille को समझें"), ("Kannada", "ಬ್ರೈಲ್ ಎಂದರೇನು?", "ಬ್ರೈಲ್ ಪರಿಚಯ")]
        for language, question, answer in cases:
            class Response:
                def raise_for_status(self): pass
                def json(self): return {"message": {"content": answer}}
            with self.subTest(language=language), patch.object(main.requests, "post", return_value=Response()) as ollama:
                result = main.ask_tutor(main.TutorQuestion(question=question, language=language))
                self.assertEqual(result["answer"], answer)
                self.assertEqual(result["source"], "ollama_rag")
                self.assertIn(f"Answer in {language}", ollama.call_args.kwargs["json"]["messages"][0]["content"])

    def test_model_unavailable_returns_service_error(self):
        with patch.object(main.requests, "post", side_effect=requests.ConnectionError("offline")):
            with self.assertRaises(main.HTTPException) as caught:
                main.ask_tutor(main.TutorQuestion(question="What is Braille?"))
        self.assertEqual(caught.exception.status_code, 503)

    def test_model_output_validation_rejects_empty_repetition_wrong_language_and_oversize(self):
        cases = [
            ("", "English"),
            ("Same sentence. Same sentence. Same sentence. Same sentence.", "English"),
            ("Braille uses cells and dots.", "Hindi"),
            ("x" * (main.TUTOR_MAX_RESPONSE_CHARS + 1), "English"),
        ]
        for answer, language in cases:
            class Response:
                def raise_for_status(self): pass
                def json(self): return {"message": {"content": answer}}
            with self.subTest(language=language, length=len(answer)), patch.object(main.requests, "post", return_value=Response()):
                with self.assertRaises(main.HTTPException) as caught:
                    main.ask_tutor(main.TutorQuestion(question="Explain the lesson", language=language))
                self.assertEqual(caught.exception.status_code, 502)

    def test_tutor_filters_model_generated_dot_pattern_claims(self):
        class Response:
            def raise_for_status(self):
                pass
            def json(self):
                return {"message": {"content": "The letter uses dot 4."}}

        with patch.object(main.requests, "post", return_value=Response()):
            response = main.ask_tutor(main.TutorQuestion(question="Explain my lesson"))
        self.assertEqual(response["source"], "safe_fallback")
        self.assertNotIn("dot 4", response["answer"])

    def test_braille_pattern_question_uses_verified_engine_without_calling_ollama(self):
        data = main.TutorQuestion(
            question="What is the Braille pattern for a?",
            verified_examples=[{"text": "a", "cells": [1]}],
        )
        with patch.object(main.requests, "post", side_effect=AssertionError("LLM must not encode")):
            response = main.ask_tutor(data)
        self.assertEqual(response["source"], "verified_engine")
        self.assertEqual(response["verified_examples"], [{"text": "a", "cells": [1]}])
        self.assertTrue(response["sources"])

    def test_uppercase_a_answer_explains_letter_dots_and_capital_sign(self):
        with patch.object(main.requests, "post", side_effect=AssertionError("LLM must not encode")):
            response = main.ask_tutor(main.TutorQuestion(
                question="What is the Braille pattern for A?",
            ))

        self.assertEqual(response["source"], "verified_engine")
        self.assertIn("The letter A uses dot 1 only", response["answer"])
        self.assertIn("top-left", response["answer"])
        self.assertIn("capital sign (dot 6)", response["answer"])
        # Six-bit masks: 32 is dot 6 (capital sign), 1 is dot 1 (A cell).
        self.assertEqual(response["verified_examples"], [{"text": "A", "cells": [32, 1]}])
        self.assertTrue(any("iceb.org" in source["url"] for source in response["sources"]))

    def test_supported_single_letter_phrasings_bypass_ollama(self):
        questions = [
            ("How do I write F in English Braille?", "F", [32, 11], [1, 2, 4]),
            ("What are the dots for letter A?", "A", [32, 1], [1]),
            ("Show me how to write B.", "B", [32, 3], [1, 2]),
        ]
        for question, letter, cells, dots in questions:
            with self.subTest(question=question), patch.object(main.requests, "post", side_effect=AssertionError("verified letter lookup must not call Ollama")):
                response = main.ask_tutor(main.TutorQuestion(question=question))
            self.assertEqual(response["source"], "verified_engine")
            self.assertEqual(response["verified_examples"], [{"text": letter, "cells": cells}])
            self.assertEqual(response["letter_examples"][0]["dots"], dots)
            if letter == "F":
                self.assertIn("uses dots 1, 2, and 4", response["answer"])
                self.assertIn(
                    "top-left, middle-left, and top-right positions",
                    response["answer"],
                )

    def test_explicit_single_letter_unverified_target_is_refused_without_ollama(self):
        with patch.object(main.requests, "post", side_effect=AssertionError("unsupported mapping must not call Ollama")):
            response = main.ask_tutor(main.TutorQuestion(question="How do I write Ā in English Braille?"))
        self.assertEqual(response["source"], "unsupported_example")
        self.assertEqual(response["verified_examples"], [])

    def test_braille_word_answer_is_deterministic_and_includes_verified_cells(self):
        with patch.object(
            main.requests,
            "post",
            side_effect=AssertionError("word encodings must not rely on Ollama"),
        ) as request:
            response = main.ask_tutor(main.TutorQuestion(
                question="How do I write the word cat in Braille?",
            ))

        self.assertEqual(response["source"], "verified_engine")
        self.assertTrue(response["answer"].startswith("Let's look at cat one letter at a time."))
        self.assertIn("uses 3 cells", response["answer"])
        self.assertIn("c: dot 1 at top-left and dot 4 at top-right", response["answer"])
        self.assertIn("a: dot 1 at top-left", response["answer"])
        self.assertIn("t: dot 2 at middle-left, dot 3 at bottom-left, dot 4 at top-right, and dot 5 at middle-right", response["answer"])
        self.assertIn("without contractions", response["answer"])
        self.assertEqual(response["verified_examples"], [{"text": "cat", "cells": [9, 1, 30]}])
        self.assertEqual([item["letter"] for item in response["letter_examples"]], ["c", "a", "t"])
        self.assertFalse(request.called)
        self.assertTrue(any("iceb.org" in source["url"] for source in response["sources"]))

    def test_mixed_case_word_includes_capital_sign_and_unsupported_word_is_refused(self):
        class Response:
            def raise_for_status(self):
                pass
            def json(self):
                return {"message": {"content": "Let's look at each letter in order."}}

        with patch.object(main.requests, "post", return_value=Response()):
            mixed_case = main.ask_tutor(main.TutorQuestion(
                question="Encode Cat in Braille",
            ))
            unsupported = main.ask_tutor(main.TutorQuestion(
                question="Write can't in Braille",
            ))

        self.assertEqual(mixed_case["verified_examples"], [{"text": "Cat", "cells": [32, 9, 1, 30]}])
        self.assertIn("Each uppercase letter has a capital sign, dot 6", mixed_case["answer"])
        self.assertEqual(unsupported["source"], "unsupported_example")

    def test_uppercase_word_uses_the_verified_engine_capital_word_indicator(self):
        self.assertEqual(
            verified_uncontracted_word("CAT"),
            {"text": "CAT", "cells": [32, 32, 9, 1, 30]},
        )
        class Response:
            def raise_for_status(self):
                pass
            def json(self):
                return {"message": {"content": "We'll explore this word together."}}

        with patch.object(main.requests, "post", return_value=Response()):
            response = main.ask_tutor(main.TutorQuestion(
                question="How do I write CAT in Braille?",
            ))
        self.assertEqual(response["verified_examples"][0]["cells"], [32, 32, 9, 1, 30])
        self.assertIn("capital-word indicator first: dot 6 twice", response["answer"])

    def test_supported_word_question_forms_resolve_target_word(self):
        from verified_braille import requested_english_word
        examples = {
            "What dots make up the word DOG?": "DOG",
            "How do I read the Braille word SUN?": "SUN",
            "Can you teach me to write BAT?": "BAT",
            "Why is CAT written using these Braille cells?": "CAT",
        }
        for question, expected in examples.items():
            with self.subTest(question=question):
                self.assertEqual(requested_english_word(question), expected)

    def test_short_word_followup_keeps_the_verified_word_context(self):
        class Response:
            def raise_for_status(self):
                pass
            def json(self):
                return {"message": {"content": "Each cell represents one letter in this beginner spelling."}}

        with patch.object(main.requests, "post", return_value=Response()):
            response = main.ask_tutor(main.TutorQuestion(
                question="Why?",
                history=[{"role": "user", "content": "How do I write CAT in Braille?"}],
            ))
        self.assertIn("capital-word indicator", response["answer"])
        self.assertEqual(response["verified_examples"][0]["cells"], [32, 32, 9, 1, 30])
        self.assertEqual([item["letter"] for item in response["letter_examples"]], ["C", "A", "T"])

    def test_word_answers_use_verified_cells_without_calling_ollama(self):
        with patch.object(
            main.requests,
            "post",
            side_effect=requests.Timeout("local model timed out"),
        ):
            response = main.ask_tutor(main.TutorQuestion(
                question="What dots make up the word DOG?",
            ))
        self.assertEqual(response["source"], "verified_engine")
        self.assertEqual(response["verified_examples"][0]["cells"], [32, 32, 25, 21, 27])
        self.assertIn("D: dot 1 at top-left", response["answer"])
        self.assertEqual(len(response["letter_examples"]), 3)

    def test_server_verifies_requested_pattern_and_rejects_unsupported_letter(self):
        with patch.object(main.requests, "post", side_effect=AssertionError("unsupported mapping must not call LLM")):
            unsupported = main.ask_tutor(main.TutorQuestion(question="What is the pattern for Hindi अ?"))
            corrected = main.ask_tutor(main.TutorQuestion(
                question="What is the Braille pattern for a?",
                verified_examples=[{"text": "a", "cells": [2]}],
            ))
        self.assertEqual(unsupported["source"], "unsupported_example")
        self.assertEqual(corrected["source"], "verified_engine")
        self.assertEqual(corrected["verified_examples"], [{"text": "a", "cells": [1]}])

    def test_retrieval_evidence_and_followup_are_used_for_conceptual_answers(self):
        class Response:
            def raise_for_status(self):
                pass
            def json(self):
                return {"message": {"content": "The cell has two columns and three positions."}}

        captured = {}
        def fake_post(url, json, timeout):
            captured.update(json)
            return Response()

        data = main.TutorQuestion(
            question="Why?",
            history=[{"role": "user", "content": "Explain the six-dot Braille cell layout"}],
        )
        with patch.object(main.requests, "post", side_effect=fake_post):
            response = main.ask_tutor(data)
        self.assertEqual(response["source"], "ollama_rag")
        self.assertTrue(any("english-six-dot-cell" in message["content"] for message in captured["messages"]))
        self.assertTrue(response["sources"])

    def test_tutor_rejects_unvalidated_voice_language_and_limits_history(self):
        self.assertEqual(
            main.TutorQuestion(question="Explain Braille", language="Hindi").language,
            "Hindi",
        )
        with self.assertRaises(ValidationError):
            main.TutorQuestion(question="Explain Braille", language="Tamil")
        with self.assertRaises(ValidationError):
            main.TutorQuestion(question="Explain Braille", history=[
                {"role": "user", "content": "past"} for _ in range(9)
            ])

    def test_deterministic_verifier_matches_lowercase_and_capital_cells(self):
        self.assertEqual(verified_single_letter("a"), {"text": "a", "cells": [1]})
        self.assertEqual(verified_single_letter("A"), {"text": "A", "cells": [32, 1]})
        self.assertIsNone(verified_single_letter("ā"))

    def test_tutor_timeout_returns_gateway_timeout(self):
        with patch.object(
            main.requests,
            "post",
            side_effect=requests.Timeout("local model timed out"),
        ):
            with self.assertRaises(main.HTTPException) as caught:
                main.ask_tutor(main.TutorQuestion(question="Explain this"))
        self.assertEqual(caught.exception.status_code, 504)

    def test_conceptual_question_reports_model_unavailable(self):
        with patch.object(
            main.requests,
            "post",
            side_effect=requests.ConnectionError("local model is stopped"),
        ):
            with self.assertRaises(main.HTTPException) as caught:
                main.ask_tutor(main.TutorQuestion(
                    question="Explain the six-dot Braille cell layout",
                ))
        self.assertEqual(caught.exception.status_code, 503)

    def test_conversational_tutor_answers_in_selected_language(self):
        class Response:
            def raise_for_status(self): pass
            def json(self): return {"message": {"content": "यह पाठ धैर्य से अभ्यास करें।"}}

        with patch.object(main.requests, "post", return_value=Response()) as ollama:
            response = main.ask_tutor(main.TutorQuestion(
                question="मुझे अभ्यास में मदद चाहिए",
                language="Hindi",
            ))
        self.assertEqual(response["answer"], "यह पाठ धैर्य से अभ्यास करें।")
        self.assertEqual(response["source"], "ollama_rag")
        self.assertIn("Answer in Hindi", ollama.call_args.kwargs["json"]["messages"][0]["content"])

    def test_english_word_translation_to_kannada_has_verified_braille(self):
        class Response:
            def raise_for_status(self): pass
            def json(self): return {"message": {"content": "ಹಲ"}}

        with patch.object(main.requests, "post", return_value=Response()):
            response = main.ask_tutor(main.TutorQuestion(
                question="Translate the English word hello to Kannada",
                language="English",
            ))
        self.assertEqual(response["source"], "ollama_translation_verified_engine")
        self.assertIn("hello", response["answer"])
        self.assertIn("ಹಲ", response["answer"])
        self.assertEqual(response["verified_examples"], [{"text": "ಹಲ", "cells": [19, 7]}])
        self.assertTrue(response["sources"])

    def test_translation_refuses_unencodable_model_suggestion(self):
        class Response:
            def raise_for_status(self): pass
            def json(self): return {"message": {"content": "ಕನ್ನಡ ಭಾಷೆ"}}

        with patch.object(main.requests, "post", return_value=Response()):
            response = main.ask_tutor(main.TutorQuestion(
                question="Translate hello to Kannada",
            ))
        self.assertEqual(response["source"], "unverified_translation")
        self.assertEqual(response["verified_examples"], [])

    def test_kannada_ha_question_returns_verified_bharati_dots_and_source(self):
        with patch.object(main.requests, "post") as ollama:
            response = main.ask_tutor(main.TutorQuestion(
                question="How do I write the starting Kannada letter ha in Braille?",
                language="Kannada",
            ))

        self.assertEqual(response["source"], "verified_engine")
        self.assertIn("dots 1, 2, and 5", response["answer"])
        self.assertIn("top left", response["answer"])
        self.assertEqual(response["verified_examples"], [{"text": "ಹ", "cells": [19]}])
        self.assertTrue(response["sources"])
        ollama.assert_not_called()

    def test_kannada_word_explanation_lists_each_verified_cell_in_order(self):
        response = main.ask_tutor(main.TutorQuestion(
            question="How do I write the Kannada word ಹಲ?",
            language="Kannada",
        ))

        self.assertEqual(response["source"], "verified_engine")
        self.assertIn("2 Bharati Braille cells", response["answer"])
        self.assertIn("cell 1: dot 1 (top left), dot 2 (middle left), and dot 5 (middle right)", response["answer"])
        self.assertIn("cell 2: dot 1 (top left), dot 2 (middle left), and dot 3 (bottom left)", response["answer"])
        self.assertEqual(response["verified_examples"], [{"text": "ಹಲ", "cells": [19, 7]}])
        self.assertTrue(response["sources"])

    def test_hindi_multi_cell_character_uses_verified_ordered_cells(self):
        response = main.ask_tutor(main.TutorQuestion(
            question="How do I write त्र in Hindi Braille?",
            language="Hindi",
        ))

        self.assertEqual(response["source"], "verified_engine")
        self.assertEqual(response["verified_examples"], [{"text": "त्र", "cells": [8, 30, 23]}])
        self.assertIn("3 Bharati Braille cells in order", response["answer"])
        self.assertTrue(response["sources"])

    def test_hindi_target_extraction_uses_requested_character_not_language_name(self):
        from bharati_verified import encode, bitmasks
        questions = [
            "हिंदी में अ कैसे लिखते हैं?",
            "अ अक्षर के dots क्या हैं?",
            "Show me how to write अ.",
        ]
        expected_cells = bitmasks(encode("अ", "Hindi"))
        for question in questions:
            with self.subTest(question=question), patch.object(main.requests, "post", side_effect=AssertionError("verified Bharati mapping must not call Ollama")):
                response = main.ask_tutor(main.TutorQuestion(question=question, language="Hindi"))
            self.assertEqual(response["source"], "verified_engine")
            self.assertEqual(response["verified_examples"][0]["text"], "अ")
            self.assertEqual(response["verified_examples"][0]["cells"], expected_cells)

    def test_kannada_target_extraction_uses_requested_character_exactly(self):
        from bharati_verified import encode, bitmasks
        questions = ["ಕನ್ನಡದಲ್ಲಿ ಹ ಹೇಗೆ ಬರೆಯುವುದು?", "ಹ ಅಕ್ಷರದ ಚುಕ್ಕೆಗಳು ಯಾವುವು?"]
        expected_cells = bitmasks(encode("ಹ", "Kannada"))
        for question in questions:
            with self.subTest(question=question), patch.object(main.requests, "post", side_effect=AssertionError("verified Bharati mapping must not call Ollama")):
                response = main.ask_tutor(main.TutorQuestion(question=question, language="Kannada"))
            self.assertEqual(response["source"], "verified_engine")
            self.assertEqual(response["verified_examples"][0]["text"], "ಹ")
            self.assertEqual(response["verified_examples"][0]["cells"], expected_cells)

    def test_tutor_rejects_empty_question(self):
        with self.assertRaises(ValidationError):
            main.TutorQuestion(question="")

    def test_ml_loader_falls_back_when_artifact_is_missing(self):
        result = predict_probability({}, 0.37, Path("missing-model.joblib"))
        self.assertEqual(result["source"], "rule_based")
        self.assertEqual(result["probability"], 0.37)

    def test_synthetic_demo_model_loads_with_bounded_probability(self):
        artifact = Path(__file__).resolve().parents[1] / "artifacts" / "adaptive_v1.joblib"
        features = {
            "recent_accuracy": 0.6,
            "attempt_count": 4,
            "average_response_seconds": 25,
            "hint_rate": 0.2,
            "days_since_practice": 2,
            "mastery_estimate": 0.55,
            "exercise_difficulty": 0.4,
        }
        result = predict_probability(features, 0.5, artifact)
        self.assertEqual(result["source"], "model")
        self.assertGreaterEqual(result["probability"], 0)
        self.assertLessEqual(result["probability"], 1)

    def test_synthetic_ml_training_uses_grouped_held_out_learners(self):
        rows, targets, groups = generate_synthetic_examples(
            learner_count=40,
            skills_per_learner=3,
            attempts=5,
            seed=42,
        )
        model, metrics = train_and_evaluate(rows, targets, groups, seed=42)

        self.assertEqual(len(rows[0]), len(FEATURE_NAMES))
        self.assertEqual(metrics["train_learners"] + metrics["test_learners"], 40)
        self.assertTrue(0 <= metrics["brier_score_model"] <= 1)
        self.assertTrue(0 <= metrics["log_loss_model"])
        self.assertEqual(len(model.classes_), 2)


class RegistrationServiceTests(unittest.TestCase):
    """Unit tests for registration_service.py — no database required."""

    def test_generate_code_is_six_digits(self):
        import registration_service
        code = registration_service._generate_code()
        self.assertRegex(code, r"^\d{6}$")

    def test_hash_code_is_stable_sha256(self):
        import hashlib
        import registration_service
        code = "123456"
        expected = hashlib.sha256(code.encode()).hexdigest()
        self.assertEqual(registration_service._hash_code(code), expected)

    def test_different_codes_produce_different_hashes(self):
        import registration_service
        h1 = registration_service._hash_code("000001")
        h2 = registration_service._hash_code("000002")
        self.assertNotEqual(h1, h2)


class LearnerRegisterEndpointTests(unittest.TestCase):
    """Tests for POST /learners/register without a real database."""

    def _make_valid_payload(self, **overrides):
        payload = {
            "name": "Priya",
            "phone": "9876543210",
            "preferred_language": "English",
            "consent": True,
        }
        payload.update(overrides)
        return payload

    def test_register_requires_at_least_phone_or_email(self):
        data = main.LearnerRegisterRequest(
            name="Test", consent=True,
        )
        # Remove both phone and email
        with self.assertRaises(Exception) as ctx:
            main.learner_register(data)
        # Should raise HTTPException with 422
        from fastapi import HTTPException
        self.assertIsInstance(ctx.exception, HTTPException)
        self.assertEqual(ctx.exception.status_code, 422)

    def test_register_requires_consent(self):
        from fastapi import HTTPException
        data = main.LearnerRegisterRequest(
            name="Test", phone="9876543210", consent=False,
        )
        with self.assertRaises(HTTPException) as ctx:
            main.learner_register(data)
        self.assertEqual(ctx.exception.status_code, 422)

    def test_pydantic_rejects_non_digit_phone(self):
        from pydantic import ValidationError
        with self.assertRaises(ValidationError):
            main.LearnerRegisterRequest(
                name="Test",
                phone="not-a-number",
                consent=True,
            )

    def test_pydantic_rejects_too_short_phone(self):
        from pydantic import ValidationError
        with self.assertRaises(ValidationError):
            main.LearnerRegisterRequest(
                name="Test",
                phone="123",   # fewer than 7 digits
                consent=True,
            )

    def test_register_calls_registration_service_and_returns_code(self):
        import registration_service
        sentinel = {
            "learner_id": "uuid-abc",
            "learner_code": "042817",
            "name": "Priya",
            "phone": "9876543210",
            "email": None,
            "batch": None,
            "preferred_language": "English",
            "consent_at": None,
            "created_at": None,
        }
        with patch.object(registration_service, "register_learner", return_value=sentinel) as mock_reg:
            data = main.LearnerRegisterRequest(
                name="Priya", phone="9876543210", consent=True,
            )
            result = main.learner_register(data)
        mock_reg.assert_called_once()
        self.assertEqual(result["learner_code"], "042817")

    def test_register_propagates_db_error_as_500(self):
        import registration_service
        from fastapi import HTTPException
        with patch.object(registration_service, "register_learner", side_effect=RuntimeError("db down")):
            data = main.LearnerRegisterRequest(
                name="Priya", phone="9876543210", consent=True,
            )
            with self.assertRaises(HTTPException) as ctx:
                main.learner_register(data)
        self.assertEqual(ctx.exception.status_code, 500)


class LearnerLanguagePreferenceEndpointTests(unittest.TestCase):
    def test_preference_update_is_saved_for_each_supported_language(self):
        learner_id = "64ac1268-a24a-4dcc-a7d3-1fbf81cd5511"
        for language in ("English", "Hindi", "Kannada"):
            with self.subTest(language=language):
                data = main.LearnerLanguageUpdateRequest(
                    learner_code="012345",
                    preferred_language=language,
                )
                expected = {
                    "learner_id": learner_id,
                    "preferred_language": language,
                }
                with patch.object(
                    main.registration_service,
                    "update_learner_language",
                    return_value=expected,
                ) as update:
                    result = main.learner_update_language(learner_id, data)
                self.assertEqual(result, expected)
                update.assert_called_once_with(
                    learner_id=learner_id,
                    code="012345",
                    language=language,
                )

    def test_preference_update_rejects_invalid_language_and_code(self):
        with self.assertRaises(ValidationError):
            main.LearnerLanguageUpdateRequest(
                learner_code="123",
                preferred_language="English",
            )
        with self.assertRaises(ValidationError):
            main.LearnerLanguageUpdateRequest(
                learner_code="123456",
                preferred_language="Tamil",
            )

    def test_preference_update_hides_invalid_learner_code(self):
        from fastapi import HTTPException

        data = main.LearnerLanguageUpdateRequest(
            learner_code="000001",
            preferred_language="Kannada",
        )
        with patch.object(
            main.registration_service, "update_learner_language", return_value=None
        ):
            with self.assertRaises(HTTPException) as ctx:
                main.learner_update_language(
                    "64ac1268-a24a-4dcc-a7d3-1fbf81cd5511", data
                )
        self.assertEqual(ctx.exception.status_code, 404)


class LearnerRestoreEndpointTests(unittest.TestCase):
    """Tests for POST /learners/restore without a real database."""

    def test_restore_returns_404_on_mismatch(self):
        import registration_service
        from fastapi import HTTPException
        with patch.object(registration_service, "restore_learner", return_value=None):
            data = main.LearnerRestoreRequest(
                phone_or_email="9876543210", code="000000",
            )
            with self.assertRaises(HTTPException) as ctx:
                main.learner_restore(data)
        self.assertEqual(ctx.exception.status_code, 404)

    def test_restore_returns_learner_on_match(self):
        import registration_service
        sentinel = {
            "learner_id": "uuid-abc",
            "name": "Priya",
            "phone": "9876543210",
            "email": None,
            "batch": None,
            "preferred_language": "English",
            "created_at": None,
        }
        with patch.object(registration_service, "restore_learner", return_value=sentinel):
            data = main.LearnerRestoreRequest(
                phone_or_email="9876543210", code="042817",
            )
            result = main.learner_restore(data)
        self.assertEqual(result["learner_id"], "uuid-abc")

    def test_pydantic_rejects_non_six_digit_code(self):
        from pydantic import ValidationError
        with self.assertRaises(ValidationError):
            main.LearnerRestoreRequest(
                phone_or_email="9876543210", code="12345",  # 5 digits
            )

    def test_pydantic_rejects_alpha_code(self):
        from pydantic import ValidationError
        with self.assertRaises(ValidationError):
            main.LearnerRestoreRequest(
                phone_or_email="9876543210", code="abc123",
            )

    def test_restore_propagates_db_error_as_500(self):
        import registration_service
        from fastapi import HTTPException
        with patch.object(registration_service, "restore_learner", side_effect=RuntimeError("db down")):
            data = main.LearnerRestoreRequest(
                phone_or_email="9876543210", code="042817",
            )
            with self.assertRaises(HTTPException) as ctx:
                main.learner_restore(data)
        self.assertEqual(ctx.exception.status_code, 500)


class TeacherServiceTests(unittest.TestCase):
    """Unit tests for teacher_service.py helpers that don't need a DB."""

    def test_check_rate_allows_first_attempt(self):
        import teacher_service
        # Use a unique key so other tests don't interfere.
        allowed = teacher_service._check_rate("unique_test_email_rate@example.com")
        self.assertTrue(allowed)

    def test_check_rate_blocks_after_max_attempts(self):
        import teacher_service
        key = "blocked_test@example.com"
        teacher_service._rate[key] = []  # reset
        for _ in range(teacher_service._RATE_MAX):
            teacher_service._check_rate(key)
        self.assertFalse(teacher_service._check_rate(key))

    def test_verify_token_raises_on_garbage(self):
        import teacher_service
        with self.assertRaises(ValueError):
            teacher_service.verify_token("not.a.real.token")


class TeacherSignupEndpointTests(unittest.TestCase):
    def test_pydantic_rejects_short_password(self):
        from pydantic import ValidationError
        with self.assertRaises(ValidationError):
            main.TeacherSignupRequest(
                name="Alice", email="a@b.com", password="short",
            )

    def test_signup_returns_409_on_duplicate_email(self):
        import teacher_service
        from fastapi import HTTPException
        with patch.object(main, "signup_teacher", side_effect=ValueError("email_taken")):
            data = main.TeacherSignupRequest(
                name="Alice", email="a@b.com", password="password123",
            )
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_signup(data)
        self.assertEqual(ctx.exception.status_code, 409)

    def test_signup_calls_service_and_returns_result(self):
        import teacher_service
        sentinel = {"teacher_id": "tid", "name": "Alice",
                    "email": "a@b.com", "organization": None}
        with patch.object(main, "signup_teacher", return_value=sentinel) as mock:
            data = main.TeacherSignupRequest(
                name="Alice", email="a@b.com", password="password123",
            )
            result = main.teacher_signup(data)
        mock.assert_called_once()
        self.assertEqual(result["teacher_id"], "tid")

    def test_signup_returns_500_on_db_error(self):
        import teacher_service
        from fastapi import HTTPException
        with patch.object(main, "signup_teacher", side_effect=RuntimeError("db")):
            data = main.TeacherSignupRequest(
                name="Alice", email="a@b.com", password="password123",
            )
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_signup(data)
        self.assertEqual(ctx.exception.status_code, 500)

    def test_signup_reports_missing_teacher_table_as_migration_error(self):
        from fastapi import HTTPException

        class MissingTeacherTableError(Exception):
            sqlstate = "42P01"

        data = main.TeacherSignupRequest(
            name="Alice", email="a@b.com", password="password123",
        )
        with patch.object(
            main,
            "signup_teacher",
            side_effect=MissingTeacherTableError("relation resonant.teachers does not exist"),
        ):
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_signup(data)

        self.assertEqual(ctx.exception.status_code, 503)
        self.assertIn("schema is missing or outdated", ctx.exception.detail)
        self.assertIn("python migrate.py", ctx.exception.detail)

    def test_signup_logs_diagnostic_without_credentials_or_identity(self):
        from fastapi import HTTPException

        data = main.TeacherSignupRequest(
            name="Alice Example",
            email="alice@example.test",
            password="my-private-password",
        )
        failure = RuntimeError(
            "failed for alice@example.test using password=my-private-password"
        )
        with patch.object(main, "signup_teacher", side_effect=failure):
            with self.assertLogs(main.logger, level="ERROR") as captured:
                with self.assertRaises(HTTPException) as ctx:
                    main.teacher_signup(data)

        self.assertEqual(ctx.exception.status_code, 500)
        self.assertIn("Reference:", ctx.exception.detail)
        self.assertIn("failed for [redacted] using password=[redacted]", captured.output[0])
        self.assertNotIn("alice@example.test", captured.output[0])
        self.assertNotIn("my-private-password", captured.output[0])

    def test_missing_password_hasher_is_reported_as_configuration_unavailable(self):
        from fastapi import HTTPException

        data = main.TeacherSignupRequest(
            name="Alice", email="a@b.com", password="password123",
        )
        with patch.object(
            main,
            "signup_teacher",
            side_effect=RuntimeError("passlib[bcrypt] is not installed."),
        ):
            with self.assertLogs(main.logger, level="ERROR") as captured:
                with self.assertRaises(HTTPException) as ctx:
                    main.teacher_signup(data)

        self.assertEqual(ctx.exception.status_code, 503)
        self.assertIn("passlib[bcrypt]", ctx.exception.detail)
        self.assertIn("same environment", ctx.exception.detail)
        self.assertIn("configuration_failure=True", captured.output[0])
        self.assertNotIn("passlib", captured.output[0])

    def test_missing_database_configuration_is_reported_as_unavailable(self):
        from fastapi import HTTPException

        data = main.TeacherSignupRequest(
            name="Alice", email="a@b.com", password="password123",
        )
        with patch.object(
            main,
            "signup_teacher",
            side_effect=RuntimeError("RESONANT_DATABASE_URL is not configured."),
        ):
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_signup(data)

        self.assertEqual(ctx.exception.status_code, 503)
        self.assertIn("RESONANT_DATABASE_URL", ctx.exception.detail)

    def test_signup_password_dependency_fails_before_database_access(self):
        import teacher_service

        with (
            patch.object(teacher_service, "_BCRYPT_OK", False),
            patch.object(teacher_service, "get_connection") as get_connection,
        ):
            with self.assertRaisesRegex(RuntimeError, "passlib\\[bcrypt\\]"):
                teacher_service.signup_teacher(
                    name="Alice",
                    email="a@b.com",
                    password="password123",
                    organization=None,
                )
        get_connection.assert_not_called()

    def test_signup_jwt_dependency_fails_before_database_access(self):
        import teacher_service

        with (
            patch.object(teacher_service, "_JWT_OK", False),
            patch.object(teacher_service, "get_connection") as get_connection,
        ):
            with self.assertRaisesRegex(RuntimeError, "python-jose"):
                teacher_service.signup_teacher(
                    name="Alice",
                    email="a@b.com",
                    password="password123",
                    organization=None,
                )
        get_connection.assert_not_called()

    def test_signup_jwt_dependency_failure_is_clear_and_does_not_create_account(self):
        from fastapi import HTTPException

        data = main.TeacherSignupRequest(
            name="Alice", email="a@b.com", password="password123",
        )
        with patch.object(
            main,
            "signup_teacher",
            side_effect=RuntimeError("python-jose is not installed."),
        ):
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_signup(data)

        self.assertEqual(ctx.exception.status_code, 503)
        self.assertIn("python-jose", ctx.exception.detail)
        self.assertIn("No account was created", ctx.exception.detail)


class TeacherLoginEndpointTests(unittest.TestCase):
    def test_login_returns_token_on_success(self):
        import teacher_service
        sentinel = {"teacher_id": "tid", "name": "Alice",
                    "email": "a@b.com", "token": "tok"}
        with patch.object(main, "login_teacher", return_value=sentinel):
            data = main.TeacherLoginRequest(email="a@b.com", password="password123")
            result = main.teacher_login(data)
        self.assertEqual(result["token"], "tok")

    def test_login_returns_401_on_bad_credentials(self):
        import teacher_service
        from fastapi import HTTPException
        with patch.object(main, "login_teacher",
                          side_effect=ValueError("invalid_credentials")):
            data = main.TeacherLoginRequest(email="a@b.com", password="wrong")
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_login(data)
        self.assertEqual(ctx.exception.status_code, 401)

    def test_login_returns_429_when_rate_limited(self):
        import teacher_service
        from fastapi import HTTPException
        with patch.object(main, "login_teacher",
                          side_effect=ValueError("rate_limited")):
            data = main.TeacherLoginRequest(email="a@b.com", password="password123")
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_login(data)
        self.assertEqual(ctx.exception.status_code, 429)


class TeacherAuthDependencyTests(unittest.TestCase):
    def test_require_teacher_raises_401_on_missing_header(self):
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as ctx:
            main._require_teacher(authorization=None)
        self.assertEqual(ctx.exception.status_code, 401)

    def test_require_teacher_raises_401_on_bad_token(self):
        import teacher_service
        from fastapi import HTTPException
        with patch.object(main, "verify_token",
                          side_effect=ValueError("invalid_token")):
            with self.assertRaises(HTTPException) as ctx:
                main._require_teacher(authorization="Bearer bad.token")
        self.assertEqual(ctx.exception.status_code, 401)

    def test_require_teacher_returns_teacher_id_on_valid_token(self):
        import teacher_service
        with patch.object(main, "verify_token", return_value="tid-abc"):
            result = main._require_teacher(authorization="Bearer valid.token")
        self.assertEqual(result, "tid-abc")

    def test_learner_register_returns_401_without_token(self):
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as ctx:
            main._require_teacher(authorization=None)
        self.assertEqual(ctx.exception.status_code, 401)


class TeacherLearnersEndpointTests(unittest.TestCase):
    def test_returns_learner_list(self):
        import teacher_service
        sentinel = [{"learner_id": "lid", "name": "Priya",
                     "batch": "A", "created_at": None}]
        with patch.object(main, "get_teacher_learners", return_value=sentinel):
            result = main.teacher_learners(teacher_id="tid")
        self.assertEqual(result["teacher_id"], "tid")
        self.assertEqual(len(result["learners"]), 1)


class TeacherDashboardEndpointTests(unittest.TestCase):
    def test_dashboard_returns_summary_and_learners(self):
        import teacher_service
        sentinel = {
            "summary": {"total_learners": 1, "active_this_week": 1, "struggling": 0},
            "learners": [{
                "id": "11111111-1111-1111-1111-111111111111",
                "name": "Priya",
                "batch": "Morning A",
                "preferred_language": "Kannada",
                "last_active_at": "2026-11-10T10:00:00Z",
                "current_stage": "stage-1-exercise-2",
                "current_letter": "B",
                "accuracy_pct": 85.0,
                "attempts_7d": 12,
                "top_weak_letters": ["C", "D"],
                "status": "active",
            }],
        }
        with patch.object(main, "get_teacher_dashboard_data", return_value=sentinel):
            result = main.teacher_dashboard(teacher_id="teacher-uuid")
        self.assertEqual(result["summary"]["total_learners"], 1)
        self.assertEqual(result["learners"][0]["name"], "Priya")
        self.assertEqual(result["learners"][0]["preferred_language"], "Kannada")
        self.assertEqual(result["learners"][0]["status"], "active")

    def test_learner_detail_returns_404_for_other_teacher_learner(self):
        import teacher_service
        from fastapi import HTTPException
        from uuid import UUID
        # Mock returns None when learner does not belong to the teacher
        with patch.object(main, "get_teacher_learner_detail", return_value=None):
            lid = UUID("22222222-2222-2222-2222-222222222222")
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_learner_detail(learner_id=lid, teacher_id="teacher-owner-2")
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertEqual(ctx.exception.detail, "Learner not found.")

    def test_learner_detail_returns_data_when_belongs_to_teacher(self):
        import teacher_service
        from uuid import UUID
        lid = UUID("33333333-3333-3333-3333-333333333333")
        sentinel = {
            "id": str(lid),
            "name": "Priya",
            "batch": "Morning A",
            "phone": "9876543210",
            "email": "priya@example.com",
            "accuracy_pct": 90.0,
            "skill_progress": [{
                "skill_id": "english-letter-d",
                "attempts": 3,
                "correct_count": 1,
                "accuracy_pct": 33.3,
                "mastery_estimate": 0.41,
                "mastery_method": "bayesian_knowledge_tracing",
                "review_due": True,
            }],
            "recent_attempts": [{"exercise_id": "ex-1", "outcome": "correct"}],
        }
        with patch.object(main, "get_teacher_learner_detail", return_value=sentinel):
            result = main.teacher_learner_detail(learner_id=lid, teacher_id="teacher-owner-1")
        self.assertEqual(result["id"], str(lid))
        self.assertEqual(result["name"], "Priya")
        self.assertEqual(len(result["recent_attempts"]), 1)
        self.assertEqual(result["skill_progress"][0]["mastery_estimate"], 0.41)


class LearnerOwnershipEndpointTests(unittest.TestCase):
    def setUp(self):
        from uuid import uuid4
        self.learner_id = uuid4()
        self.other_learner_id = uuid4()
        self.code = "012345"

    def _attempt(self, learner_id=None, submission_id=None):
        from uuid import uuid4
        return main.PracticeAttemptCreate(
            submission_id=submission_id or uuid4(),
            learner_id=learner_id or self.learner_id,
            learner_code=self.code,
            exercise_id="english-a",
            skill_id="english-a",
            language="English",
            exercise_type="letter_recognition",
            outcome="correct",
            response_time_ms=1000,
            attempt_number=1,
        )

    def _quiz(self, learner_id=None, submission_id=None):
        from uuid import uuid4
        return main.QuizResultCreate(
            submission_id=submission_id or uuid4(),
            learner_id=learner_id or self.learner_id,
            learner_code=self.code,
            quiz_id="english-words",
            language="English",
            score=2,
            max_score=3,
            duration_ms=5000,
        )

    def test_profile_and_progress_reject_wrong_learner_code(self):
        from fastapi import HTTPException
        with patch.object(main.registration_service, "verify_learner_code", return_value=False), \
             patch.object(main, "load_learner") as load, \
             patch.object(main, "get_skill_progress") as progress:
            for endpoint, args in (
                (main.learner_profile, {"learner_id": self.learner_id, "learner_code": self.code}),
                (main.learner_progress, {"learner_id": self.learner_id, "learner_code": "999999"}),
            ):
                with self.subTest(endpoint=endpoint.__name__, args=args), self.assertRaises(HTTPException) as error:
                    endpoint(**args)
                self.assertEqual(error.exception.status_code, 401)
            load.assert_not_called()
            progress.assert_not_called()

    def test_practice_and_quiz_writes_reject_other_learner_before_persistence(self):
        from fastapi import HTTPException
        attempt = self._attempt(learner_id=self.other_learner_id)
        quiz = self._quiz(learner_id=self.other_learner_id)
        with patch.object(main.registration_service, "verify_learner_code", return_value=False), \
             patch.object(main, "record_practice_attempt") as save_attempt, \
             patch.object(main, "record_quiz_result") as save_quiz:
            for endpoint, payload in (
                (main.create_practice_attempt, attempt),
                (main.create_quiz_result, quiz),
            ):
                with self.subTest(endpoint=endpoint.__name__), self.assertRaises(HTTPException) as error:
                    endpoint(payload)
                self.assertEqual(error.exception.status_code, 401)
            save_attempt.assert_not_called()
            save_quiz.assert_not_called()

    def test_verified_learner_can_submit_only_to_own_account(self):
        attempt = self._attempt()
        saved = {"learner_id": self.learner_id, "submission_id": attempt.submission_id}
        with patch.object(main.registration_service, "verify_learner_code", return_value=True) as verify, \
             patch.object(main, "record_practice_attempt", return_value=saved) as persist:
            result = main.create_practice_attempt(attempt)
        self.assertEqual(result, saved)
        verify.assert_called_once_with(str(self.learner_id), self.code)
        persist.assert_called_once_with(attempt)

    def test_reused_submission_id_cannot_return_another_learners_attempt(self):
        from fastapi import HTTPException
        attempt = self._attempt()
        other_result = {"learner_id": self.other_learner_id, "outcome": "correct"}
        with patch.object(main.registration_service, "verify_learner_code", return_value=True), \
             patch.object(main, "record_practice_attempt", return_value=other_result):
            with self.assertRaises(HTTPException) as error:
                main.create_practice_attempt(attempt)
        self.assertEqual(error.exception.status_code, 409)

    def test_learner_code_is_required_for_legacy_write_payloads(self):
        from pydantic import ValidationError
        from uuid import uuid4
        common = {
            "submission_id": uuid4(),
            "learner_id": self.learner_id,
        }
        with self.assertRaises(ValidationError):
            main.PracticeAttemptCreate(
                **common,
                exercise_id="e1", skill_id="s1", language="English",
                exercise_type="letter_recognition", outcome="correct",
                response_time_ms=1, attempt_number=1,
            )
        with self.assertRaises(ValidationError):
            main.QuizResultCreate(
                **common,
                quiz_id="q1", language="English", score=1, max_score=1,
                duration_ms=1,
            )

    def test_learner_creation_requires_teacher_dependency(self):
        from fastapi import HTTPException
        route = next(
            route for route in main.app.routes
            if getattr(route, "path", None) == "/learners"
            and "POST" in getattr(route, "methods", set())
        )
        self.assertTrue(any(
            dependency.call is main._require_teacher
            for dependency in route.dependant.dependencies
        ))
        with self.assertRaises(HTTPException) as error:
            main._require_teacher(authorization=None)
        self.assertEqual(error.exception.status_code, 401)

    def test_profile_route_requires_learner_code_header(self):
        route = next(
            route for route in main.app.routes
            if getattr(route, "path", None) == "/learners/{learner_id}"
            and "GET" in getattr(route, "methods", set())
        )
        self.assertTrue(any(
            parameter.alias == "X-Learner-Code" and parameter.required
            for parameter in route.dependant.header_params
        ))


class TeacherPasswordResetEndpointTests(unittest.TestCase):
    def test_forgot_password_does_not_create_or_log_undelivered_token(self):
        import io
        import contextlib
        import teacher_service
        from fastapi import HTTPException

        output = io.StringIO()
        with patch.object(
            teacher_service, "create_password_reset_token",
            side_effect=AssertionError("no delivery channel is configured"),
        ) as create_token, contextlib.redirect_stdout(output):
            req = main.TeacherForgotPasswordRequest(email="teacher@example.com")
            with self.assertRaises(HTTPException) as error:
                main.teacher_forgot_password(req)
        self.assertEqual(error.exception.status_code, 503)
        self.assertIn("No reset email was sent", error.exception.detail)
        create_token.assert_not_called()
        self.assertNotIn("reset-tok", output.getvalue())

    def test_reset_password_success(self):
        import teacher_service
        with patch.object(main, "reset_password_with_token", return_value=True):
            req = main.TeacherResetPasswordRequest(token="valid-reset-token", new_password="new-password123")
            res = main.teacher_reset_password(req)
        self.assertIn("successfully updated", res["message"])

    def test_reset_password_invalid_token_returns_400(self):
        import teacher_service
        from fastapi import HTTPException
        with patch.object(main, "reset_password_with_token", return_value=False):
            req = main.TeacherResetPasswordRequest(token="invalid-reset-token", new_password="new-password123")
            with self.assertRaises(HTTPException) as ctx:
                main.teacher_reset_password(req)
        self.assertEqual(ctx.exception.status_code, 400)


class PrivacyDeletionEndpointTests(unittest.TestCase):
    def test_delete_learner_success(self):
        import teacher_service
        from uuid import UUID
        lid = UUID("44444444-4444-4444-4444-444444444444")
        with patch.object(main, "delete_teacher_learner", return_value=True):
            res = main.delete_learner_endpoint(learner_id=lid, teacher_id="teacher-1")
        self.assertIn("successfully deleted", res["message"])

    def test_delete_learner_not_owned_returns_404(self):
        import teacher_service
        from fastapi import HTTPException
        from uuid import UUID
        lid = UUID("55555555-5555-5555-5555-555555555555")
        with patch.object(main, "delete_teacher_learner", return_value=False):
            with self.assertRaises(HTTPException) as ctx:
                main.delete_learner_endpoint(learner_id=lid, teacher_id="teacher-2")
        self.assertEqual(ctx.exception.status_code, 404)

    def test_delete_teacher_account_success(self):
        import teacher_service
        with patch.object(main, "delete_teacher_account", return_value=True):
            res = main.delete_teacher_me_endpoint(teacher_id="teacher-1")
        self.assertIn("successfully deleted", res["message"])


if __name__ == "__main__":
    unittest.main()
