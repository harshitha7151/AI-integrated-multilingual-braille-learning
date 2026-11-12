# Frontend Architecture (Flutter/Dart)

> Navigation: [← AGENTS.md](../../AGENTS.md) · [Backend →](backend.md) · [Data Flow →](data-flow.md) · [Dependencies →](file-dependencies.md)

## Overview

Flutter app (`lib/`) targeting Android in landscape mode. Provides a six-dot Braille keyboard, structured English lessons (letter → word → mastery), voice tutoring, TTS/haptic feedback, and accessibility features. Hindi/Kannada engines exist but are not yet wired into the UI.

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
- Hindi/Kannada engines are **standalone**; not imported by `main.dart` or any UI code yet.
- English engine is used by `main.dart`, `local_braille_tutor.dart`, `voice_tutor_controller.dart`.

### `lib/learning/` — Curriculum & Progress
| File | Purpose | Public API |
|---|---|---|
| `lesson_catalog.dart` | Static curriculum data (chapters, exercises, stages, word lessons) | `LessonCatalog`, `LessonChapter`, `LessonExercise`, `CurriculumStage`, `WordLesson` |
| `lesson_progress_store.dart` | Local JSON-file persistence of practice events | `LessonProgressStore.forApplication()`, `.record()`, `.readEvents()` |
| `onboarding_store.dart` | Persists onboarding completion state | `OnboardingStore.forApplication()` → `OnboardingProgress`, `.isComplete()`, `.markComplete()`, `.currentStep()`, `.saveStep()` |
| `welcome_onboarding.dart` | Welcome/onboarding screen widget | `WelcomeOnboarding` widget |

- `lesson_catalog.dart` has **no imports** — pure data.
- `lesson_progress_store.dart` imports `path_provider`, `dart:io`, `dart:convert`.
- `onboarding_store.dart` imports `path_provider`, `dart:io`, `dart:convert`.
- `welcome_onboarding.dart` imports `flutter_tts`, `vibration`.

### `lib/tutor/` — Voice Tutor System
| File | Purpose | Public API |
|---|---|---|
| `http_tutor_gateway.dart` | HTTP client to backend `/ask` endpoint | `HttpTutorGateway.ask()` → `TutorResponse` |
| `local_braille_tutor.dart` | Offline fallback tutor using local engine | `LocalBrailleTutor.ask()` → `TutorResponse` |
| `speech_to_text_recognizer.dart` | Wraps `speech_to_text` plugin | `SpeechToTextRecognizer`, `.initialize()`, `.listen()`, `.stop()` |
| `voice_command_parser.dart` | Parses voice input into structured commands | `VoiceCommandParser.parse(String) → ParsedCommand?`, `VoiceCommand` enum |
| `voice_tutor_controller.dart` | Orchestrates tutor conversation lifecycle | `createVoiceTutorController()` → `VoiceTutorController` |
| `voice_tutor_panel.dart` | Dialog UI for voice tutor | `VoiceTutorPanel` widget, `VerifiedBrailleExample` |

- `http_tutor_gateway.dart` imports `dart:convert`, `package:http`.
- `local_braille_tutor.dart` imports `english_grade1_engine.dart`.
- `voice_tutor_controller.dart` imports `http_tutor_gateway`, `local_braille_tutor`, `voice_tutor_panel` (for types), `speech_to_text_recognizer`.
- `voice_tutor_panel.dart` imports `flutter_tts`, `vibration`.

### `lib/accessibility/`
| File | Purpose | Public API |
|---|---|---|
| `two_finger_navigation_detector.dart` | Detects two-finger swipe gestures | `TwoFingerNavigationDetector` widget |

- No external imports beyond Flutter core.

## Key Patterns

- **No router/DI framework**: Navigation is manual (`page` integer index in `_ResonantHomeState`).
- **No state management library**: All state lives in `_ResonantHomeState` via `setState()`.
- **Engines are stateless**: Braille encoding is pure function — `encode(input) → cells`.
- **Progress is file-based**: JSON append-log on device, no SQLite.
- **Voice tutor has dual path**: Online (HTTP → backend) or offline (local engine fallback).

