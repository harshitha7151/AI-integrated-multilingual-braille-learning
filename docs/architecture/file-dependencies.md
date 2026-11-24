# File Dependencies & Navigation

> Navigation: [← AGENTS.md](../../AGENTS.md) · [Frontend →](frontend.md) · [Backend →](backend.md) · [Data Flow →](data-flow.md)

## Flutter (lib/) Dependency Graph

```
main.dart
├── core/braille/english_grade1_engine.dart    (Braille encoding)
├── learning/lesson_catalog.dart               (curriculum data)
├── learning/chapter_navigation_controller.dart (validated destinations)
├── learning/adaptive_decision_controller.dart  (adaptive rules/validation)
├── learning/adaptive_word_recommender.dart      (bounded word ranking)
├── learning/adaptive_recommendation_status.dart (accessible adaptive UI)
├── learning/lesson_progress_store.dart         (events + decision inbox/sync)
├── learning/onboarding_store.dart              (onboarding state)
├── learning/welcome_onboarding.dart            (onboarding UI)
├── tutor/speech_to_text_recognizer.dart        (voice input)
├── tutor/voice_tutor_panel.dart                (tutor dialog UI)
├── tutor/voice_tutor_controller.dart           (tutor orchestration)
├── tutor/voice_command_parser.dart             (command parsing)
├── tutor/tutor_action_controller.dart           (intent validation)
├── accessibility/accessible_action_surface.dart (buttonless actions)
└── accessibility/two_finger_navigation_detector.dart

voice_tutor_controller.dart
├── tutor/http_tutor_gateway.dart               (online tutor)
├── tutor/local_braille_tutor.dart              (offline fallback)
├── tutor/voice_tutor_panel.dart                (types: VerifiedBrailleExample)
└── tutor/speech_to_text_recognizer.dart

local_braille_tutor.dart
└── core/braille/english_grade1_engine.dart

http_tutor_gateway.dart
└── (external: package:http)

lesson_progress_store.dart
├── learning/adaptive_decision_controller.dart  (decision wire/storage types)
├── learning/learner_account_store.dart         (learner proof)
└── POST assessments / adaptive lifecycle endpoints

core/braille/bharati_hindi_engine.dart          (via dispatcher: Hindi lessons/writing)
core/braille/bharati_kannada_engine.dart        (via dispatcher: Kannada lessons/writing)
```

## Backend (resonant_backend/) Dependency Graph

```
main.py
├── database.py
├── progress_service.py ──→ database.py, resonant_ml_service.py
├── assessment_service.py ──→ database.py, progress_service.py,
│                              verified Braille engines,
│                              learning_error_service.py,
│                              resonant_ml_service.py,
│                              adaptive_question_service.py
├── resonant_ml_service.py ──→ trusted qualified joblib artifact, pandas
├── adaptive_question_service.py ──→ braille_mapping_registry.py, Ollama (optional)
├── braille_mapping_registry.py ──→ verified_braille.py, bharati_verified.py
├── educational_ml_service.py ──→ pandas, joblib, trusted local AIML artifact
├── verified_braille.py                         (standalone)
└── knowledge_base.py                           (standalone)

recommendation_service.py
├── database.py
└── adaptive_engine.py ──→ adaptive_ml.py       (scikit-learn + joblib)

migrate.py ──→ database.py
train_adaptive_demo.py                          (standalone script)

aiml/experiments/assistments_2009_2010/run_experiment.py
├── aiml/src/data/assistments_2009.py
├── aiml/src/features/assistments_history.py
├── aiml/src/models/educational_outcome.py
└── aiml/src/evaluation/educational_outcome.py
    ──→ ignored raw CSV, measured reports, ignored fitted artifact
```

## Cross-Boundary Dependency

```
Flutter app                          Backend
─────────────                        ───────
voice_tutor_controller.dart
  └─ http_tutor_gateway.dart ──HTTP──→ main.py POST /ask
                                         ├─ verified_braille.py
                                         ├─ knowledge_base.py
                                         └─ Ollama (external LLM)

lesson_progress_store.dart
  ├─ POST /learners/{id}/assessments ─────→ assessment_service.py
  └─ POST /learners/{id}/adaptive-decisions/{decision_id}/status
                                         └─ assessment_service.py
```

## Module Quick Reference

Use this table to navigate when modifying a specific feature.

### Braille Encoding
| What to change | Files | Also check |
|---|---|---|
| English letter/word encoding | `lib/core/braille/english_grade1_engine.dart` | `resonant_backend/verified_braille.py` (must stay in sync) |
| Hindi encoding | `lib/core/braille/bharati_hindi_engine.dart` | Not connected to UI yet |
| Kannada encoding | `lib/core/braille/bharati_kannada_engine.dart` | Not connected to UI yet |
| Backend verification tables | `resonant_backend/verified_braille.py` | `lib/core/braille/english_grade1_engine.dart` |

### Curriculum & Lessons
| What to change | Files | Also check |
|---|---|---|
| Add/modify exercises | `lib/learning/lesson_catalog.dart` | `main.dart` (stage progression logic) |
| Progress persistence | `lib/learning/lesson_progress_store.dart` | `main.dart` (`restoreLessonProgress`, `persistLessonAttempt`) |
| Adaptive learner decisions | `lib/learning/adaptive_decision_controller.dart`, `lib/learning/lesson_progress_store.dart` | `main.dart` (`_handleLessonAssessmentResult`, `_applyAdaptiveDecision`) |
| Adaptive word ordering | `lib/learning/adaptive_word_recommender.dart` | `lesson_catalog.dart`, `main.dart` (`_wordRecommendation`, `_nextRecommendedWordIndex`) |
| Accessible adaptive question/status UI | `lib/learning/adaptive_recommendation_status.dart` | `main.dart`, `test/adaptive_question_integration_test.dart` |
| Onboarding flow | `lib/learning/onboarding_store.dart`, `lib/learning/welcome_onboarding.dart` | `main.dart` (`restoreOnboarding`, `finishOnboarding`) |

### Voice Tutor
| What to change | Files | Also check |
|---|---|---|
| Voice commands | `lib/tutor/voice_command_parser.dart` | `main.dart` (`handleVoiceCommand`) |
| Executable tutor actions | `lib/tutor/voice_command_parser.dart`, `lib/tutor/tutor_action_controller.dart` | `lib/learning/chapter_navigation_controller.dart`, `main.dart` (`handleVoiceCommand`) |
| Screen-aware Tutor reading/context | `lib/tutor/tutor_screen_context.dart`, `lib/tutor/voice_tutor_controller.dart` | `main.dart` (`tutorScreenContext`, `handleVoiceCommand`), `voice_tutor_panel.dart`, `http_tutor_gateway.dart` |
| Tutor choice resolution | `lib/tutor/tutor_option_resolver.dart` | `main.dart` (`handleVoiceCommand`), `test/tutor_option_resolver_test.dart` |
| Chapter navigation and boundaries | `lib/learning/chapter_navigation_controller.dart` | `lesson_catalog.dart`, `main.dart`, `two_finger_navigation_detector.dart` |
| Tutor UI | `lib/tutor/voice_tutor_panel.dart` | `lib/tutor/voice_tutor_controller.dart` |
| Tutor conversation logic | `lib/tutor/voice_tutor_controller.dart` | `http_tutor_gateway.dart`, `local_braille_tutor.dart` |
| Backend tutor endpoint | `resonant_backend/main.py` (`/ask`) | `verified_braille.py`, `knowledge_base.py` |
| Braille fact safety | `resonant_backend/verified_braille.py` | `resonant_backend/knowledge_base.py` |

### Backend Data
| What to change | Files | Also check |
|---|---|---|
| Database schema | `resonant_backend/migrations/001_initial.sql` | `migrate.py`, `progress_service.py` |
| Learner/attempt CRUD | `resonant_backend/progress_service.py` | `main.py` (route handlers), `database.py` |
| Lesson assessments and reports | `resonant_backend/assessment_service.py` | `main.py`, `registration_service.py`, `teacher_service.py`, migrations `005`–`007` |
| Governed Resonant prediction | `resonant_backend/resonant_ml_service.py` | `assessment_service.py`, `progress_service.py`, migration `007`, mastery experiment runner |
| Adaptive question selection | `resonant_backend/adaptive_question_service.py`, `braille_mapping_registry.py` | `assessment_service.py`, Flutter adaptive validator, migration `007` |
| Learning-error taxonomy | `resonant_backend/learning_error_service.py` | `assessment_service.py`, migration `007` |
| DB connection config | `resonant_backend/database.py` | `.env.example` |
| Adaptive ML | `resonant_backend/adaptive_ml.py`, `adaptive_engine.py` | `recommendation_service.py`, `artifacts/` |
| Public educational ML experiment | `aiml/src/data/assistments_2009.py`, `aiml/src/features/assistments_history.py`, `aiml/src/models/educational_outcome.py`, `aiml/src/evaluation/educational_outcome.py` | experiment runner, measured reports, ignored raw/model files |
| Experimental prediction API | `resonant_backend/educational_ml_service.py`, `resonant_backend/main.py` (`/aiml/predict`) | `aiml/artifacts/assistments_2009_rf_v1.joblib`, backend requirements and tests |

### Accessibility
| What to change | Files | Also check |
|---|---|---|
| Buttonless learner actions | `lib/accessibility/accessible_action_surface.dart` | learner routes in `main.dart`, registration/role widgets, `test/buttonless_learner_interface_test.dart` |
| Two-finger navigation | `lib/accessibility/two_finger_navigation_detector.dart` | `main.dart` (`navigateByTwoFingerSwipe`) |
| TTS behavior | `main.dart` (`speak()`, `configureAudio()`) | `lib/tutor/voice_tutor_panel.dart` |

## Test File Mapping

| Test | Tests Module |
|---|---|
| `test/english_grade1_engine_test.dart` | `english_grade1_engine.dart` |
| `test/bharati_forward_engines_test.dart` | `bharati_hindi_engine.dart`, `bharati_kannada_engine.dart` |
| `test/lesson_catalog_test.dart` | `lesson_catalog.dart` |
| `test/adaptive_decision_controller_test.dart` | `adaptive_decision_controller.dart` |
| `test/adaptive_word_recommender_test.dart` | `adaptive_word_recommender.dart` |
| `test/adaptive_question_integration_test.dart` | Accessible adaptive status/question widgets |
| `test/buttonless_learner_interface_test.dart` | Learner source guard and non-button action semantics |
| `test/sentence_writing_progression_test.dart` | Personalized phrase/sentence six-dot composition and progression in `main.dart` |
| `test/lesson_progress_store_test.dart` | `lesson_progress_store.dart` |
| `test/onboarding_test.dart` | `onboarding_store.dart` |
| `test/local_braille_tutor_test.dart` | `local_braille_tutor.dart` |
| `test/tutor_gateway_test.dart` | `http_tutor_gateway.dart` |
| `test/voice_command_parser_test.dart` | `voice_command_parser.dart` |
| `test/tutor_action_controller_test.dart` | `tutor_action_controller.dart` |
| `test/chapter_navigation_controller_test.dart` | `chapter_navigation_controller.dart` |
| `test/voice_tutor_test.dart` | `voice_tutor_controller.dart` |
| `test/two_finger_navigation_test.dart` | `two_finger_navigation_detector.dart` |
| `test/word_chapter_test.dart` | Word chapter UI logic in `main.dart` |
| `test/word_chapter_resume_test.dart` | Word chapter resume logic in `main.dart` |
| `test/widget_test.dart` | App widget smoke test |
| `resonant_backend/tests/test_api.py` | `main.py` routes |
| `resonant_backend/tests/test_knowledge_base.py` | `knowledge_base.py` |
| `resonant_backend/tests/test_persistence.py` | `progress_service.py`, `database.py` |
| `resonant_backend/tests/test_assessments.py` | `assessment_service.py`, assessment/lifecycle API routes, migration `005`–`007` contracts |
| `resonant_backend/tests/test_educational_ml.py` | `educational_ml_service.py`, artifact contract, missing/invalid model behavior |
| `resonant_backend/tests/test_resonant_ml.py` | `resonant_ml_service.py` feature, qualification, fallback, prediction, and hybrid rules |
| `resonant_backend/tests/test_adaptive_questions.py` | `adaptive_question_service.py` and mapping-backed fallback |
| `resonant_backend/tests/test_braille_mapping_registry.py` | Mapping registry consistency/conflict validation |
| `resonant_backend/tests/test_learning_errors.py` | Deterministic dot-error and technical-failure taxonomy |
| `aiml/tests/test_assistments_educational_outcome.py` | ASSISTments loader, point-in-time leakage safeguards, grouped split, model fitting/serialization/prediction |
| `aiml/tests/test_mastery_runner.py` | Resonant qualification gates, human review, and artifact-promotion contract |
| `aiml/tests/test_mastery_and_error_analysis.py` | Production-schema point-in-time features and grouped chronological split |

