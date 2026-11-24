# Frontend Architecture (Flutter/Dart)

> Navigation: [← AGENTS.md](../../AGENTS.md) · [Backend →](backend.md) · [Data Flow →](data-flow.md) · [Dependencies →](file-dependencies.md)

## Overview

Flutter app (`lib/`) targeting Android in landscape mode, with teacher pages also available in Flutter web. It provides six-dot Braille input, English/Hindi/Kannada learning flows, automatic character and composed-writing assessments, voice tutoring, TTS/haptic feedback, and accessibility features.

## Module Map

### `lib/main.dart`
- **Purpose**: App entry point and central state coordinator.
- **Contains**: `ResonantApp`, `ResonantHome` (stateful root), `_BrailleKeyboardState`, `_WordChapterScreenState`, all page/navigation/lesson state, voice command routing.
- **Imports**: All `lib/` modules below, plus `flutter_tts`, `flutter/services`, `flutter/semantics`.
- **Key state**: `page`, `chapter`, `lessonItem`, `onboardingComplete`, `courseComplete`, `wordAssessment`, progress sets/maps.
- **Note**: This is a large monolith (~3000 lines). Most UI widgets and lesson logic live here.

### `lib/core/braille/` — Braille Engines
| File | Purpose | Public API |
|---|---|---|
| `english_grade1_engine.dart` | Uncontracted English Braille encoding | `EnglishGrade1Engine.encode(String) → List<int>`, static `_table` map |
| `bharati_hindi_engine.dart` | Bharati Hindi Grade 1 forward table | `BharatiHindiEngine.encode(String) → List<int>`, `table` getter |
| `bharati_kannada_engine.dart` | Bharati Kannada Grade 1 forward table | `BharatiKannadaEngine.encode(String) → List<int>`, `table` getter |

- All engines are **pure-Dart, no external imports** (only `dart:core`).
- Hindi/Kannada engines are reached through the multilingual dispatcher used by lessons, practice, and assessment metadata.
- English engine is used by `main.dart`, `local_braille_tutor.dart`, `voice_tutor_controller.dart`.

### `lib/learning/` — Curriculum & Progress
| File | Purpose | Public API |
|---|---|---|
| `lesson_catalog.dart` | Static curriculum data (chapters, exercises, stages, word lessons) | `LessonCatalog`, `LessonChapter`, `LessonExercise`, `CurriculumStage`, `WordLesson` |
| `chapter_navigation_controller.dart` | Pure curriculum destination and prerequisite validation | `ChapterNavigationController`, `LearningNavigationContext`, `NavigationResolution` |
| `adaptive_decision_controller.dart` | Typed, explainable, prerequisite-safe learner adaptation | `AdaptiveDecisionController`, `AdaptiveDecision`, `AdaptiveAssessmentSnapshot`, `AdaptiveDecisionResolution` |
| `adaptive_word_recommender.dart` | Explainable local ranking inside verified language-specific word banks | `AdaptiveWordRecommender`, `AdaptiveWordRecommendation` |
| `adaptive_recommendation_status.dart` | Screen-reader-first recommendation/model-mode status and reusable question choices | `AdaptiveRecommendationStatus`, `AccessibleLessonQuestion` |
| `lesson_progress_store.dart` | Local JSON persistence, adaptive-decision inbox/lifecycle, immediate assessment reconciliation, and best-effort backend sync | `LessonProgressStore.forApplication()`, `.record()`, `.saveAdaptiveDecision()`, `.pendingAdaptiveDecision()`, `.syncAssessmentDecision()`, `.syncPending()` |
| `onboarding_store.dart` | Persists onboarding completion state | `OnboardingStore.forApplication()` → `OnboardingProgress`, `.isComplete()`, `.markComplete()`, `.currentStep()`, `.saveStep()` |
| `welcome_onboarding.dart` | Welcome/onboarding screen widget | `WelcomeOnboarding` widget |

- `lesson_catalog.dart` uses the deterministic dispatcher/English engine to
  validate authored phrase/sentence targets and fail closed when a personalized
  learner name is not encodable.
- `lesson_progress_store.dart` imports `path_provider`, `dart:io`, `dart:convert`.
- `onboarding_store.dart` imports `path_provider`, `dart:io`, `dart:convert`.
- `welcome_onboarding.dart` imports `flutter_tts`, `vibration`.

### `lib/teacher/` — Teacher Dashboard

- `dashboard_api.dart` maps authenticated dashboard, learner-detail, attempt,
  assessment, repeated-error, adaptive-prediction, and adaptive-question
  provenance payloads.
- `teacher_dashboard_page.dart` and `learner_detail_page.dart` render
  database-backed learner metrics and decisions, distinguish qualified model
  advice from deterministic cold-start, and show probability only for a valid
  qualified prediction.
- Authentication/session modules keep the teacher Bearer token separate from learner account proof.

### `lib/tutor/` — Voice Tutor System
| File | Purpose | Public API |
|---|---|---|
| `http_tutor_gateway.dart` | HTTP client to backend `/ask` endpoint | `HttpTutorGateway.ask()` → `TutorResponse` |
| `local_braille_tutor.dart` | Offline fallback tutor using local engine | `LocalBrailleTutor.ask()` → `TutorResponse` |
| `speech_to_text_recognizer.dart` | Wraps `speech_to_text` plugin | `SpeechToTextRecognizer`, `.initialize()`, `.listen()`, `.stop()` |
| `voice_command_parser.dart` | Parses voice input into structured commands | `VoiceCommandParser.parse(String) → ParsedCommand?`, `VoiceCommand` enum |
| `tutor_action_controller.dart` | Validates executable intents against learner and curriculum context without mutating UI state | `TutorActionController.resolve()` |
| `tutor_screen_context.dart` | Structured, non-sensitive snapshot and screen-reading text for the active Flutter screen | `TutorScreenContext`, `TutorScreenContextProvider` |
| `tutor_option_resolver.dart` | Resolves only visible multiple-choice options by label, ordinal, or unique text match | `TutorOptionResolver.resolveIndex()` |
| `voice_tutor_controller.dart` | Orchestrates tutor conversation lifecycle | `createVoiceTutorController()` → `VoiceTutorController` |
| `voice_tutor_panel.dart` | Dialog UI for voice tutor | `VoiceTutorPanel` widget, `VerifiedBrailleExample` |

- `http_tutor_gateway.dart` imports `dart:convert`, `package:http`.
- `local_braille_tutor.dart` imports `english_grade1_engine.dart`.
- `voice_tutor_controller.dart` imports `http_tutor_gateway`, `local_braille_tutor`, `voice_tutor_panel` (for types), `speech_to_text_recognizer`.
- `voice_tutor_panel.dart` imports `flutter_tts`, `vibration`.

### `lib/accessibility/`
| File | Purpose | Public API |
|---|---|---|
| `accessible_action_surface.dart` | Flat touch, keyboard/switch, and TalkBack action surface without button semantics | `AccessibleActionSurface` widget |
| `two_finger_navigation_detector.dart` | Detects two-finger swipe gestures | `TwoFingerNavigationDetector` widget |

- No external imports beyond Flutter core.

## Key Patterns

- **No router/DI framework**: Navigation is manual (`page` integer index in `_ResonantHomeState`).
- **No state management library**: All state lives in `_ResonantHomeState` via `setState()`.
- **Engines are stateless**: Braille encoding is pure function — `encode(input) → cells`.
- **Progress is file-based**: JSON append-log on device, no SQLite.
- **Adaptive execution is hybrid but deterministically authoritative**: Flutter
  first persists an offline decision, briefly reconciles a backend response,
  serializes applications, and revalidates language, curriculum, prerequisites,
  answer, and authoritative Braille cells. Qualified model advice is optional;
  missing/unqualified service behavior remains deterministic cold-start.
- **Learner ML messaging is plain-language**: accessible status explains the
  activity and whether qualified advice or fallback was used without exposing
  risk probabilities.
- **Adaptive word ordering is deterministic and bounded**: local history may
  reorder only eligible catalog words; the policy cannot invent content,
  change mappings, alter the mastery set, or unlock prerequisites.
- **Composed writing stays cell-authoritative**: phrase and sentence targets
  are encoded by the selected deterministic engine, and the learner submits
  every ordered cell including spaces and punctuation through the accessible
  six-dot keyboard.
- **Voice tutor has dual path**: Online (HTTP → backend) or offline (local engine fallback).
- **Tutor screen awareness is state-backed**: `_ResonantHomeState` creates a fresh `TutorScreenContext` for each turn. It includes only active-screen content, the selected language, visible question/options, feedback, and relevant progress. Screen reading and actions are handled locally; compact context is attached to conversational `/ask` requests. The LLM cannot execute actions or select answers.
- **Tutor actions are separated from tutor prose**: `TutorActionController` validates commands before `main.dart` can navigate, assess, remediate, revise, or resume.
- **Learner actions are buttonless**: learner routes use voice commands, simple
  gestures, semantic custom actions, and flat focusable action surfaces. The
  surfaces expose tap/focus actions but never the screen-reader button role.
  Six-dot controls expose toggle semantics and remain authoritative input.

