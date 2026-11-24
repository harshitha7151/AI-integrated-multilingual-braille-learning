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

Before an eligible word is selected, `AdaptiveWordRecommender` may reorder the
current verified word bank from local error, repeat-attempt, and hint evidence.
With no evidence it preserves catalog order. This deterministic policy cannot
add words, change mappings, alter the mastery set, or bypass prerequisites.

### 2a. Phrase and Sentence Writing

```
LessonCatalog authored target / verified personalized fallback
  → BrailleDispatcher selects the English, Hindi, or Kannada engine
    → ordered authoritative cells (capital signs, letters, spaces, punctuation)
      → accessible BrailleKeyboard submits one six-dot cell at a time
        → backspace/reset/TTS/haptics/semantics remain available
          → structured lesson-assessment event stores expected/submitted cells
            → existing adaptive decision and sync path
              → next prerequisite-safe writing exercise
```

### 2b. Automatic Lesson Assessment Persistence

```
Guided practice or an authored composed response completes
  → main.dart automatically opens the catalog-backed lesson assessment
    → deterministic Flutter Braille engine supplies expected cell metadata
      → LessonProgressStore writes a structured offline assessment event
        → syncPending() authenticates with learner ID + locally held learner code
          → POST /learners/{learner_id}/assessments
            → assessment_service validates the target with verified_braille.py
               or bharati_verified.py
              → one PostgreSQL transaction stores session/question/attempt,
                 classifies technical versus learning errors, updates mastery
                 and repeated errors, and resolves the prior prediction outcome
                → resonant_ml_service builds strictly-prior history features
                  ├─ qualified reviewed Resonant artifact → advisory risk
                  └─ unavailable/unqualified artifact → explicit deterministic
                     cold-start provenance
                    → deterministic decision is hybridized within bounded rules
                      → adaptive_question_service selects a mapping-backed
                         validated question and persists provenance
                        → response decision is reconciled with the local durable inbox
                  → AdaptiveDecisionController validates language, curriculum,
                     question answer/Braille cells, duplicates, remediation cap,
                     and prerequisites
                    ├─ remediate/reinforce → explanation + focused verified
                    │  practice → automatic reassessment
                    ├─ advance → next prerequisite-safe lesson
                    ├─ reassess → supported assessment without reassigning the
                    │  same remediation indefinitely
                    └─ revise → validated spaced review target
                      → lifecycle status syncs through
                        POST /learners/{learner_id}/adaptive-decisions/{id}/status
                          → teacher learner detail/report shows reason, weak
                             skill, assigned lesson, outcome, and mastery change
```

Offline events remain pending until an account and backend are available.
Submission UUIDs make a retried assessment session idempotent.
Offline rules keep the learner flow usable without the backend; synchronized
backend decisions supersede the matching offline decision without replaying an
already applied remediation.

The Flutter coordinator waits at most 1.5 seconds for the immediate backend
decision. Timeout, missing account, or network failure continues with the saved
offline action. A later synchronization persists backend provenance without
making the lesson depend on connectivity.

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

Executable tutor commands also use a separate deterministic path:

```
Speech or typed command
  → VoiceCommandParser (intent and structured parameters)
    → TutorActionController (learner and curriculum validation)
      → ChapterNavigationController when navigation is requested
        → main.dart applies only a resolved action
          → TTS/semantics, haptic feedback, and resume persistence
```

This path does not require Ollama. An unvalidated model response never changes
Flutter navigation state directly.

### 4. Backend Learner Management

```
POST /learners → progress_service.create_learner() → PostgreSQL INSERT
GET /learners/{id} → progress_service.get_learner() → PostgreSQL SELECT
POST /practice/attempts → progress_service.record_practice_attempt() → PostgreSQL INSERT
POST /quizzes/results → progress_service.record_quiz_result() → PostgreSQL INSERT
GET /learners/{id}/progress → progress_service.get_skill_progress() → PostgreSQL aggregate
```

### 5. Separate Synthetic/Legacy Recommendation Path

```
recommendation_service.get_recommendations(learner_id)
  → adaptive_engine.compute_next_exercises()
    → adaptive_ml.predict_difficulty() (scikit-learn model)
      → artifacts/adaptive_v1.joblib
```

This path is not the production learner assessment loop. Learner remediation
and advancement use explicit deterministic rules from the structured
assessment evidence. Synthetic model metrics are not treated as real-world
learning performance.

### 6. Separate Public-Dataset Experimental Prediction

```
POST /aiml/predict (aggregate history + question metadata only)
  → EducationalPredictionRequest bounds and category validation
    → educational_ml_service loads trusted local joblib artifact
      → fitted preprocessing + ASSISTments Random Forest
        → probability/prediction + experiment metadata
          → experimental: true, learning_action: null
```

No learner ID, current answer outcome, raw answer text, or tutor transcript is
accepted. A missing or invalid artifact returns HTTP 503. This path is not
called by Flutter and cannot mutate assessment decisions, prerequisites,
remediation state, progression, synchronization, or teacher reports.

### 7. Onboarding

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
| Adaptive decision inbox | Device file via `path_provider` | JSON | Pending/applied/completed decisions, evidence, remediation cycle, and sync state |
| Onboarding state | Device file via `path_provider` | JSON | Step index, completion flag |
| Learner profiles | PostgreSQL `resonant.learners` | SQL | Username, language, timestamps |
| Practice attempts | PostgreSQL `resonant.practice_attempts` | SQL | Detailed attempt records |
| Quiz results | PostgreSQL `resonant.quiz_results` | SQL | Quiz scores and durations |
| Lesson assessments | PostgreSQL `resonant.assessment_*`, `resonant.adaptive_decisions` | SQL/JSONB | Question attempts, structured responses, errors, and next-action evidence |
| Resonant model registry/predictions | PostgreSQL `resonant.ml_model_versions`, `resonant.ml_predictions` | SQL/JSONB | Qualification metadata, exact feature snapshots, fallback/model source, latency, and eventual observed outcome |
| Adaptive questions | PostgreSQL `resonant.adaptive_question_instances` | SQL/JSONB | Validated question, mapping/curriculum/source versions, optional generation failure, and prediction link |
| Synthetic demo model | `resonant_backend/artifacts/adaptive_v1.joblib` | joblib | Synthetic-only difficulty demonstration |
| Public educational experiment | `aiml/artifacts/assistments_2009_rf_v1.joblib` | ignored joblib | Optional ASSISTments first-attempt correctness pipeline; no learning action |
| Qualified Resonant artifact | `aiml/artifacts/resonant_next_attempt_v2.joblib` | ignored joblib | Optional consented-data future-error model; currently absent, so deterministic cold-start is used |

## Network Boundary

Flutter uses separate bounded clients for tutor questions, learner account
operations, practice/assessment synchronization, adaptive lifecycle updates,
and authenticated teacher reporting. Learning events and decisions remain
durable locally when those requests fail. LLM output is never accepted as a
navigation or adaptive action; only locally parsed and validated commands or
structured decisions that pass deterministic Flutter validation may mutate
learner state. Model advice cannot supply mappings, mark mastery, bypass a
prerequisite, or make offline learning unavailable.

