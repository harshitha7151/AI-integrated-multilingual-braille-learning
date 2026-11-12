# AGENTS.md — Resonant Braille Learning System

## Project Overview

**Resonant** is an AI-assisted multilingual Braille learning system built with Flutter (frontend) and FastAPI/Python (backend). It teaches six-dot Braille through an audio-guided, accessible interface targeting blind and low-vision learners on Android.

**Current scope**: English uncontracted Braille (letter course → word assessment → word chapter → mastery). Hindi and Kannada engines exist but are not connected to the UI. A voice tutor uses a local Ollama LLM with deterministic verification to prevent hallucinated Braille patterns.

## Architecture Summary

```
┌─────────────────────────────────────────────────────┐
│  Flutter App (lib/)                                 │
│  ┌──────────┐ ┌───────────┐ ┌────────────────────┐  │
│  │  Braille  │ │ Learning  │ │   Voice Tutor      │  │
│  │  Engines  │ │ Curriculum│ │   (speech/TTS/     │  │
│  │  (core/)  │ │ & Progress│ │    commands)        │  │
│  └──────────┘ │ (learning/)│ └─────────┬──────────┘  │
│               └───────────┘           │ HTTP         │
│  ┌──────────────────┐                 │              │
│  │ Accessibility     │                │              │
│  │ (two-finger nav)  │                │              │
│  └──────────────────┘                 │              │
└───────────────────────────────────────┼──────────────┘
                                        │
                              POST /ask  │
                                        ▼
┌─────────────────────────────────────────────────────┐
│  Backend (resonant_backend/)                        │
│  ┌────────────┐ ┌──────────┐ ┌───────────────────┐  │
│  │ Verified   │ │Knowledge │ │  Progress Service  │  │
│  │ Braille    │ │ Base     │ │  (learner CRUD)    │  │
│  └────────────┘ └──────────┘ └───────────────────┘  │
│  ┌────────────────────┐  ┌────────────────────────┐  │
│  │ Adaptive ML/Engine │  │  PostgreSQL + Ollama   │  │
│  └────────────────────┘  └────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Directory Map

```
.
├── lib/                              # Flutter app source
│   ├── main.dart                     # Entry point, all UI, state coordinator (~3000 lines)
│   ├── core/braille/                 # Braille encoding engines
│   │   ├── english_grade1_engine.dart
│   │   ├── bharati_hindi_engine.dart  # Not yet in UI
│   │   └── bharati_kannada_engine.dart# Not yet in UI
│   ├── learning/                     # Curriculum, progress, onboarding
│   │   ├── lesson_catalog.dart       # Static curriculum data
│   │   ├── lesson_progress_store.dart# Local JSON progress persistence
│   │   ├── onboarding_store.dart     # Onboarding state persistence
│   │   └── welcome_onboarding.dart   # Onboarding UI widget
│   ├── tutor/                        # Voice tutor system
│   │   ├── http_tutor_gateway.dart   # HTTP client → backend /ask
│   │   ├── local_braille_tutor.dart  # Offline fallback tutor
│   │   ├── speech_to_text_recognizer.dart
│   │   ├── voice_command_parser.dart # Voice → structured commands
│   │   ├── voice_tutor_controller.dart# Tutor conversation orchestration
│   │   └── voice_tutor_panel.dart    # Tutor dialog UI
│   └── accessibility/
│       └── two_finger_navigation_detector.dart
├── resonant_backend/                 # Python FastAPI backend
│   ├── main.py                       # API routes (tutor, learners, progress)
│   ├── database.py                   # PostgreSQL connection pool
│   ├── verified_braille.py           # Deterministic Braille verifier
│   ├── knowledge_base.py            # RAG evidence retrieval
│   ├── progress_service.py           # Learner/attempt/quiz CRUD
│   ├── recommendation_service.py     # Adaptive recommendations
│   ├── adaptive_engine.py            # Recommendation logic
│   ├── adaptive_ml.py                # scikit-learn model wrapper
│   ├── migrate.py                    # DB migration runner
│   ├── train_adaptive_demo.py        # Demo ML training script
│   ├── migrations/001_initial.sql    # Schema: resonant.learners/attempts/results
│   ├── artifacts/adaptive_v1.joblib  # Trained ML model
│   ├── requirements.txt
│   └── tests/
├── test/                             # Flutter/Dart tests
├── docs/                             # Project documentation
│   ├── architecture/                 # ← Architecture docs (this system)
│   │   ├── frontend.md               # Frontend module details
│   │   ├── backend.md                # Backend module details
│   │   ├── data-flow.md              # Data flow diagrams
│   │   └── file-dependencies.md      # Dependency graph & change navigation
│   ├── adaptive-learning.md
│   ├── braille-standards.md
│   ├── curriculum.md
│   ├── database-and-api.md
│   ├── voice-tutor.md
│   └── project-status.md
├── android/                          # Android platform config
├── web/                              # Web platform config (not primary target)
├── pubspec.yaml                      # Flutter dependencies
└── CHANGELOG.md
```

## Architecture Documentation

| Document | Purpose |
|---|---|
| [docs/architecture/frontend.md](docs/architecture/frontend.md) | Frontend module map, public APIs, patterns |
| [docs/architecture/backend.md](docs/architecture/backend.md) | Backend module map, routes, env config |
| [docs/architecture/data-flow.md](docs/architecture/data-flow.md) | End-to-end data flows for all features |
| [docs/architecture/file-dependencies.md](docs/architecture/file-dependencies.md) | File dependency graph and change navigation tables |

### Existing Documentation

| Document | Purpose |
|---|---|
| [docs/braille-standards.md](docs/braille-standards.md) | Language coverage and Braille standard references |
| [docs/curriculum.md](docs/curriculum.md) | Curriculum design and stage definitions |
| [docs/database-and-api.md](docs/database-and-api.md) | Database schema details and API validation |
| [docs/voice-tutor.md](docs/voice-tutor.md) | Voice tutor privacy, setup, language limits |
| [docs/adaptive-learning.md](docs/adaptive-learning.md) | ML methodology and synthetic demo notes |
| [docs/project-status.md](docs/project-status.md) | Implementation status and blockers |
| [CHANGELOG.md](CHANGELOG.md) | Recent changes |

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter/Dart (SDK ^3.8.1), Android landscape |
| Backend | Python, FastAPI, uvicorn |
| Database | PostgreSQL (psycopg) |
| AI/LLM | Ollama (default: qwen2.5:0.5b) |
| ML | scikit-learn, joblib |
| TTS | flutter_tts (Android) |
| Voice Input | speech_to_text (Android) |
| Haptics | vibration package |

---

## Rules for AI Agents

### Before Making Any Change

1. **Identify targets**: Determine the exact file(s) and code sections involved.
2. **Trace dependencies**: Use [file-dependencies.md](docs/architecture/file-dependencies.md) to find what imports or calls the target, and what the target imports or calls.
3. **Read selectively**: Read only the relevant sections of source files. Read full files only when the change scope is unclear.
4. **Check tests**: Find corresponding test files in the [test mapping](docs/architecture/file-dependencies.md#test-file-mapping).

### While Making Changes

5. **Modify only what is required** to fulfill the request. Do not refactor, reformat, rename, or rewrite unrelated code.
6. **Preserve existing architecture**, naming conventions, patterns, and behavior.
7. **Do not modify dependent files** unless the change genuinely requires it.
8. **Preserve all existing comments and docstrings** unrelated to the change.

### Critical Sync Points

9. **Braille tables must stay in sync**: If you modify `lib/core/braille/english_grade1_engine.dart`, verify that `resonant_backend/verified_braille.py` reflects the same mappings, and vice versa.
10. **Curriculum changes cascade**: Changes to `lesson_catalog.dart` may affect progression logic in `main.dart` (stages, word lists, resume logic).
11. **Voice commands have two halves**: `voice_command_parser.dart` (parse) and `main.dart` `handleVoiceCommand()` (execute) must agree on the `VoiceCommand` enum.

### After Making Changes

12. **Report**: List the files changed and explain why each was modified.
13. **Update documentation only when** the architecture, dependencies, or navigation actually change. Minor code fixes do not require doc updates.
14. **If a change has broader implications**, explain them before expanding scope.

### Navigation Shortcuts

- **Adding a voice command?** → `voice_command_parser.dart` + `main.dart` (`handleVoiceCommand`) + `test/voice_command_parser_test.dart`
- **Adding a Braille letter?** → `english_grade1_engine.dart` + `verified_braille.py` + `test/english_grade1_engine_test.dart`
- **Adding a lesson/exercise?** → `lesson_catalog.dart` + check stage boundaries in `main.dart`
- **Changing tutor behavior?** → `voice_tutor_controller.dart` + check `http_tutor_gateway.dart` and `local_braille_tutor.dart`
- **Changing DB schema?** → Add new migration in `migrations/`, update `progress_service.py`, update `main.py` models
- **Adding API endpoint?** → `main.py` + add test in `tests/test_api.py`

