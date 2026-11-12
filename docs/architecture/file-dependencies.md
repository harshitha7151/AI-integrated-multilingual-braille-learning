# File Dependencies & Navigation

> Navigation: [← AGENTS.md](../../AGENTS.md) · [Frontend →](frontend.md) · [Backend →](backend.md) · [Data Flow →](data-flow.md)

## Flutter (lib/) Dependency Graph

```
main.dart
├── core/braille/english_grade1_engine.dart    (Braille encoding)
├── learning/lesson_catalog.dart               (curriculum data)
├── learning/lesson_progress_store.dart         (local persistence)
├── learning/onboarding_store.dart              (onboarding state)
├── learning/welcome_onboarding.dart            (onboarding UI)
├── tutor/speech_to_text_recognizer.dart        (voice input)
├── tutor/voice_tutor_panel.dart                (tutor dialog UI)
├── tutor/voice_tutor_controller.dart           (tutor orchestration)
├── tutor/voice_command_parser.dart             (command parsing)
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

core/braille/bharati_hindi_engine.dart          (standalone, unused by UI)
core/braille/bharati_kannada_engine.dart        (standalone, unused by UI)
```

## Backend (resonant_backend/) Dependency Graph

```
main.py
├── database.py
├── progress_service.py ──→ database.py
├── verified_braille.py                         (standalone)
└── knowledge_base.py                           (standalone)

recommendation_service.py
├── database.py
└── adaptive_engine.py ──→ adaptive_ml.py       (scikit-learn + joblib)

migrate.py ──→ database.py
train_adaptive_demo.py                          (standalone script)
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
| Onboarding flow | `lib/learning/onboarding_store.dart`, `lib/learning/welcome_onboarding.dart` | `main.dart` (`restoreOnboarding`, `finishOnboarding`) |

### Voice Tutor
| What to change | Files | Also check |
|---|---|---|
| Voice commands | `lib/tutor/voice_command_parser.dart` | `main.dart` (`handleVoiceCommand`) |
| Tutor UI | `lib/tutor/voice_tutor_panel.dart` | `lib/tutor/voice_tutor_controller.dart` |
| Tutor conversation logic | `lib/tutor/voice_tutor_controller.dart` | `http_tutor_gateway.dart`, `local_braille_tutor.dart` |
| Backend tutor endpoint | `resonant_backend/main.py` (`/ask`) | `verified_braille.py`, `knowledge_base.py` |
| Braille fact safety | `resonant_backend/verified_braille.py` | `resonant_backend/knowledge_base.py` |

### Backend Data
| What to change | Files | Also check |
|---|---|---|
| Database schema | `resonant_backend/migrations/001_initial.sql` | `migrate.py`, `progress_service.py` |
| Learner/attempt CRUD | `resonant_backend/progress_service.py` | `main.py` (route handlers), `database.py` |
| DB connection config | `resonant_backend/database.py` | `.env.example` |
| Adaptive ML | `resonant_backend/adaptive_ml.py`, `adaptive_engine.py` | `recommendation_service.py`, `artifacts/` |

### Accessibility
| What to change | Files | Also check |
|---|---|---|
| Two-finger navigation | `lib/accessibility/two_finger_navigation_detector.dart` | `main.dart` (`navigateByTwoFingerSwipe`) |
| TTS behavior | `main.dart` (`speak()`, `configureAudio()`) | `lib/tutor/voice_tutor_panel.dart` |

## Test File Mapping

| Test | Tests Module |
|---|---|
| `test/english_grade1_engine_test.dart` | `english_grade1_engine.dart` |
| `test/bharati_forward_engines_test.dart` | `bharati_hindi_engine.dart`, `bharati_kannada_engine.dart` |
| `test/lesson_catalog_test.dart` | `lesson_catalog.dart` |
| `test/lesson_progress_store_test.dart` | `lesson_progress_store.dart` |
| `test/onboarding_test.dart` | `onboarding_store.dart` |
| `test/local_braille_tutor_test.dart` | `local_braille_tutor.dart` |
| `test/tutor_gateway_test.dart` | `http_tutor_gateway.dart` |
| `test/voice_command_parser_test.dart` | `voice_command_parser.dart` |
| `test/voice_tutor_test.dart` | `voice_tutor_controller.dart` |
| `test/two_finger_navigation_test.dart` | `two_finger_navigation_detector.dart` |
| `test/word_chapter_test.dart` | Word chapter UI logic in `main.dart` |
| `test/word_chapter_resume_test.dart` | Word chapter resume logic in `main.dart` |
| `test/widget_test.dart` | App widget smoke test |
| `resonant_backend/tests/test_api.py` | `main.py` routes |
| `resonant_backend/tests/test_knowledge_base.py` | `knowledge_base.py` |
| `resonant_backend/tests/test_persistence.py` | `progress_service.py`, `database.py` |

