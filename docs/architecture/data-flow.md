# Data Flow

> Navigation: [← AGENTS.md](../../AGENTS.md) · [Frontend →](frontend.md) · [Backend →](backend.md) · [Dependencies →](file-dependencies.md)

## Primary Flows

### 1. Braille Learning (Letter Course)

```
LessonCatalog (static data)
  → _ResonantHomeState (page/chapter/lessonItem state)
    → Lesson UI (explanation → guided practice → keyboard entry)
      → EnglishGrade1Engine.encode() (verify pattern)
        → TTS.speak() + HapticFeedback (feedback)
          → LessonProgressStore.record() (persist to local JSON)
            → _selectResumePoint() (advance curriculum)
```

### 2. Word Assessment

```
CurriculumStage.words / LessonCatalog.cumulativeWords
  → _ResonantHomeState (wordAssessment mode)
    → BrailleKeyboard (multi-cell input)
      → EnglishGrade1Engine.encode() (verify each letter cell)
        → Assessment scoring (per-cell match)
          → LessonProgressStore.record() (persist)
            → completedWordStages / completedStageWords (advance)
```

### 3. Voice Tutor Conversation

```
User speech → SpeechToTextRecognizer (speech_to_text plugin)
  → VoiceCommandParser.parse()
    ├─ Local command? → handleVoiceCommand() → TTS response → close dialog
    └─ Braille question? → VoiceTutorController
        → EnglishGrade1Engine.encode() (build verified examples)
          → HttpTutorGateway.ask() ──HTTP──→ Backend POST /ask
          │   ├─ verified_braille.py (deterministic check)
          │   ├─ knowledge_base.py (RAG evidence retrieval)
          │   └─ Ollama LLM (conversational response)
          │       → contains_unverified_dot_claim() (safety filter)
          │           → JSON response with answer + verified_examples
          ├─ On network failure → LocalBrailleTutor.ask() (offline fallback)
          └─ TTS.speak(answer) → VoiceTutorPanel UI
```

### 4. Backend Learner Management

```
POST /learners → progress_service.create_learner() → PostgreSQL INSERT
GET /learners/{id} → progress_service.get_learner() → PostgreSQL SELECT
POST /practice/attempts → progress_service.record_practice_attempt() → PostgreSQL INSERT
POST /quizzes/results → progress_service.record_quiz_result() → PostgreSQL INSERT
GET /learners/{id}/progress → progress_service.get_skill_progress() → PostgreSQL aggregate
```

### 5. Adaptive Recommendations (Not Yet Connected to App)

```
recommendation_service.get_recommendations(learner_id)
  → adaptive_engine.compute_next_exercises()
    → adaptive_ml.predict_difficulty() (scikit-learn model)
      → artifacts/adaptive_v1.joblib
```

### 6. Onboarding

```
App start → OnboardingStore.forApplication() (load from local file)
  ├─ Not complete → WelcomeOnboarding widget (guided intro)
  │   → OnboardingStore.saveStep() / .markComplete()
  │     → finishOnboarding() → redirect to lessons
  └─ Complete → _selectResumePoint() → resume last lesson
```

## Data Storage

| Store | Location | Format | Purpose |
|---|---|---|---|
| Lesson progress | Device file via `path_provider` | JSON append-log | Practice events (exercise_id, outcome, timing) |
| Onboarding state | Device file via `path_provider` | JSON | Step index, completion flag |
| Learner profiles | PostgreSQL `resonant.learners` | SQL | Username, language, timestamps |
| Practice attempts | PostgreSQL `resonant.practice_attempts` | SQL | Detailed attempt records |
| Quiz results | PostgreSQL `resonant.quiz_results` | SQL | Quiz scores and durations |
| ML model | `resonant_backend/artifacts/adaptive_v1.joblib` | joblib | Trained difficulty predictor |

## Network Boundary

The Flutter app communicates with the backend **only** through `HttpTutorGateway` → `POST /ask`. Learner management endpoints exist but are **not yet called from the app**. Local lesson progress does **not** sync to the backend.

