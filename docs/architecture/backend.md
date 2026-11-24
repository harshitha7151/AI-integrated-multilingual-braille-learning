# Backend Architecture (Python/FastAPI)

> Navigation: [← AGENTS.md](../../AGENTS.md) · [Frontend →](frontend.md) · [Data Flow →](data-flow.md) · [Dependencies →](file-dependencies.md)

## Overview

`resonant_backend/` is a FastAPI application providing an AI Braille tutor endpoint, learner CRUD, practice/quiz/lesson-assessment persistence, progress tracking, and teacher-scoped reporting. It connects to PostgreSQL for data and Ollama for LLM inference.

## Module Map

### `main.py` — API Routes
- **Purpose**: FastAPI app definition and all route handlers.
- **Routes**: health/tutor routes; learner, practice, quiz, lesson-assessment,
  adaptive prediction/status routes; teacher authentication/dashboard/reporting
  routes; isolated experimental `POST /aiml/predict`; ephemeral paired live-demo
  session/event endpoints, an authenticated WebSocket stream, dashboard metadata,
  and opt-in experimental intent comparison.
- **Imports**: persistence/account/teacher services, deterministic Braille
  verifiers, `assessment_service`, `resonant_ml_service`, the separate
  `educational_ml_service`, and `knowledge_base`.
- **Assessment models**: `LessonAssessmentCreate` and `AssessmentQuestionCreate` carry structured, bounded responses rather than free-form learner transcripts.

### `database.py` — Connection Pool
- **Purpose**: PostgreSQL connection management via `psycopg` connection pool.
- **Public API**: `get_connection()` context manager.
- **Config**: Reads `RESONANT_DATABASE_URL` env var.

### `verified_braille.py` — Deterministic Braille Verifier
- **Purpose**: Verifies Braille cell patterns using deterministic tables (not LLM). Ensures no hallucinated dot patterns reach the learner.
- **Public API**: `verified_single_letter()`, `verified_uncontracted_word()`, `verified_uncontracted_word_details()`, `verify_client_examples()`, `contains_unverified_dot_claim()`, `is_pattern_question()`, `requested_english_word()`.
- **Imports**: None from other backend modules — self-contained lookup tables.

### `knowledge_base.py` — RAG Evidence Retrieval
- **Purpose**: Retrieves evidence snippets for Braille questions from a curated knowledge base. Used to ground LLM answers.
- **Public API**: `retrieve_evidence()`, `evidence_for_letter()`, `format_evidence()`, `has_braille_scope()`, `requested_english_letter()`, `source_references()`.
- **Imports**: None from other backend modules.

### `progress_service.py` — Learner Data Operations
- **Purpose**: Database CRUD for learners, practice attempts, quiz results, and skill progress aggregation.
- **Public API**: `create_learner()`, `get_learner()`, `get_skill_progress()`, `record_practice_attempt()`, `record_quiz_result()`.
- **Imports**: `database`; valid answer attempts also resolve the newest earlier
  `resonant_ml_service` prediction in the same transaction.

### `assessment_service.py` — Lesson Assessment Operations
- **Purpose**: validates catalog-backed targets against deterministic English/Bharati engines, stores normalized sessions/questions/attempts, updates mastery and error summaries transactionally, builds the governed next-attempt prediction or cold-start fallback, selects a validated adaptive question, records the explainable hybrid decision, synchronizes decision lifecycle, and returns teacher-scoped reports.
- **Public API**: `validate_question()`, `categorize_error()`, `record_assessment()`, `update_adaptive_decision_status()`, `get_teacher_assessment_report()`.
- **Imports**: `database`, `progress_service`, deterministic Braille verifiers,
  `learning_error_service`, `resonant_ml_service`, and
  `adaptive_question_service`.

### `braille_mapping_registry.py` — Versioned Mapping Records
- **Purpose**: derives read-only English/Hindi/Kannada mapping, source,
  curriculum, and version records directly from authoritative engine tables.
- **Safety boundary**: rejects duplicate/conflicting records and never acts as
  an alternative encoder.

### `learning_error_service.py` — Deterministic Error Analysis
- **Purpose**: computes exact missing/extra-dot details and separates valid
  learning errors from no input, invalid input, and technical failure.
- **Safety boundary**: nonlearning input remains observable but cannot lower
  mastery or drive remediation.

### `adaptive_question_service.py` — Validated Question Selection
- **Purpose**: selects mapping-backed multilingual question variants, avoids
  recent IDs, persists provenance, and optionally validates constrained Ollama
  rephrasing.
- **Safety boundary**: answer/cells always come from deterministic mappings;
  invalid or unavailable generation falls back to a validated bank question.

### `resonant_ml_service.py` — Governed Learner-History Prediction
- **Purpose**: constructs the exact `resonant-next-attempt-v2` point-in-time
  feature snapshot, loads a qualified trusted artifact, persists prediction
  provenance/outcomes, and adds bounded advisory evidence to a deterministic
  decision.
- **Safety boundary**: requires consented-data provenance, exact task/schema,
  declared language support, passing qualification, explicit human review, and
  probabilistic inference. Otherwise it returns explicit deterministic
  cold-start fallback.

### `recommendation_service.py` — Adaptive Recommendations
- **Purpose**: Generates next-exercise recommendations based on learner progress.
- **Public API**: `get_recommendations()`.

### `live_demo_service.py` and `aiml_dashboard_service.py`
- **Purpose**: The first manages expiring in-memory demonstration sessions and
  privacy-filtered, ordered events; the second exposes verified project
  experiment metadata and inference using saved CLINC150 model pipelines.
- **Boundary**: Experimental intent models do not control live navigation. Demo
  event streams are session-scoped and are not persisted in PostgreSQL.
- **Imports**: `database`, `adaptive_engine`.

### `adaptive_engine.py` — Recommendation Logic
- **Purpose**: Computes adaptive difficulty and exercise ordering.
- **Public API**: `compute_next_exercises()`, difficulty calculation helpers.
- **Imports**: `adaptive_ml`.

### `adaptive_ml.py` — ML Model Wrapper
- **Purpose**: Loads and runs the scikit-learn adaptive difficulty model.
- **Public API**: `predict_difficulty()`, `load_model()`.
- **Imports**: `scikit-learn`, `joblib`. Model artifact at `artifacts/adaptive_v1.joblib`.

### `train_adaptive_demo.py` — Demo ML Training
- **Purpose**: Generates synthetic data and trains the demo adaptive model.
- **Standalone script**, not imported by the server.

### `educational_ml_service.py` — Public-Dataset Experimental Inference
- **Purpose**: Lazily loads the trusted local ASSISTments Random Forest artifact, enforces the exact aggregate/question feature schema, and returns an explicitly experimental first-attempt correctness estimate.
- **Public API**: `load_educational_ml_artifact()`, `predict_educational_outcome()`.
- **Safety boundary**: accepts no learner identifier or raw answer, never returns a learning action, rejects missing/invalid artifacts, and does not call the adaptive controller.
- **Artifact**: `aiml/artifacts/assistments_2009_rf_v1.joblib` by default; raw CSV and model binary are Git-ignored.

### `migrate.py` — Database Migration Runner
- **Purpose**: Applies SQL migrations from `migrations/` directory.
- **Imports**: `database`.
- **Standalone script**, run before server start.

### `migrations/001_initial.sql`
- Creates `resonant` schema with tables: `learners`, `practice_attempts`, `quiz_results`.
- All tables namespaced under `resonant.` schema.

### `migrations/005_lesson_assessments.sql`
- Adds normalized assessment sessions, questions, attempts, repeated-error summaries, and explainable adaptive decisions.
- Is additive and does not rewrite existing practice or quiz records.

### `migrations/006_adaptive_decision_lifecycle.sql`
- Adds deterministic decision method, lifecycle status, remediation cycle, mastery before/after, applied/completed timestamps, and remediation success.
- Expands the bounded action constraint for learner-side `remediate`, `reassess`, and `revise` mappings without removing legacy action values.

### `migrations/007_resonant_ml_adaptive_foundation.sql`
- Adds mapping-version provenance, structured attempt/error/intervention fields,
  model metadata, prediction outcomes, adaptive-question instances, and
  prediction/question links on decisions.
- Remains additive and backward-compatible with earlier assessment rows.

### `tests/`
| File | Tests |
|---|---|
| `test_api.py` | API route integration tests |
| `test_knowledge_base.py` | Evidence retrieval unit tests |
| `test_persistence.py` | Database CRUD tests |
| `test_assessments.py` | Assessment validation, persistence, authorization, adaptive decisions, and teacher reporting |
| `test_educational_ml.py` | Trusted artifact loading, exact feature contract, prediction, and missing/invalid artifact behavior |
| `test_resonant_ml.py` | Point-in-time features, qualification gating, fallback, qualified prediction, and bounded hybrid advice |
| `test_adaptive_questions.py` | Multilingual validated selection, recent-question variation, and AI-rejection fallback |
| `test_braille_mapping_registry.py` | Engine-derived mapping consistency and conflict rejection |
| `test_learning_errors.py` | Dot-difference taxonomy and technical-input exclusion |

## External Dependencies

| Package | Purpose |
|---|---|
| `fastapi` | Web framework |
| `uvicorn` | ASGI server |
| `requests` | HTTP client (Ollama API) |
| `psycopg[binary]` | PostgreSQL driver |
| `scikit-learn` | ML model for adaptive difficulty |
| `joblib` | Model serialization |
| `pandas` | Exact tabular feature frame for the fitted public-dataset pipeline |

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `RESONANT_DATABASE_URL` | — | PostgreSQL connection string |
| `RESONANT_OLLAMA_URL` | `http://localhost:11434` | Ollama base URL |
| `RESONANT_OLLAMA_MODEL` | `qwen2.5:0.5b` | LLM model name |
| `RESONANT_AI_ENABLED` | `true` | Enable/disable AI tutoring |
| `RESONANT_JWT_SECRET` | — | Required production secret for teacher JWT signing; startup fails closed when absent |
| `RESONANT_EDUCATIONAL_ML_ARTIFACT` | `../aiml/artifacts/assistments_2009_rf_v1.joblib` | Optional trusted local public-dataset experiment artifact; never accept a user-uploaded joblib file |
| `RESONANT_ML_ARTIFACT` | `../aiml/artifacts/resonant_next_attempt_v2.joblib` | Optional trusted qualified Resonant learner-history artifact; missing/unqualified files use deterministic fallback |
| `RESONANT_ML_LOW_RISK_THRESHOLD` | `0.25` | Lower advisory risk threshold; invalid threshold pairs reset to safe defaults |
| `RESONANT_ML_HIGH_RISK_THRESHOLD` | `0.55` | Higher advisory risk threshold; never overrides prerequisites or verified outcomes |
| `RESONANT_ADAPTIVE_AI_QUESTIONS` | `false` | Optional constrained question rephrasing switch; the production assessment call path currently leaves it disabled |

## Adaptive Decision Boundary

The operational assessment loop starts from transparent deterministic evidence.
`resonant_ml_service.py` may attach qualified advisory evidence and bounded
difficulty/reinforcement changes, but deterministic correctness, curriculum,
mastery, prerequisites, and Braille validation remain authoritative. With no
qualified Resonant artifact, the decision is labelled deterministic cold-start.
Flutter may execute a returned decision only after local language, curriculum,
question, duplicate, remediation-cap, and prerequisite validation. Lifecycle
updates use learner proof at
`POST /learners/{learner_id}/adaptive-decisions/{decision_id}/status`.

The older `adaptive_ml.py` artifact remains a separate synthetic demonstration
and is not accepted by the governed production loader.

The ASSISTments artifact is a second, separately named experimental component.
`POST /aiml/predict` estimates only public-dataset first-attempt correctness and
returns `learning_action: null`; it is not connected to Flutter progression or
the deterministic assessment service.

