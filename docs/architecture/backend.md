# Backend Architecture (Python/FastAPI)

> Navigation: [← AGENTS.md](../../AGENTS.md) · [Frontend →](frontend.md) · [Data Flow →](data-flow.md) · [Dependencies →](file-dependencies.md)

## Overview

`resonant_backend/` is a FastAPI application providing an AI Braille tutor endpoint, learner CRUD, practice/quiz persistence, and progress tracking. It connects to PostgreSQL for data and Ollama for LLM inference.

## Module Map

### `main.py` — API Routes
- **Purpose**: FastAPI app definition and all route handlers.
- **Routes**: `GET /`, `/health`, `/health/ai`, `/health/database`, `POST /ask`, `POST /learners`, `GET /learners/{id}`, `GET /learners/{id}/progress`, `POST /practice/attempts`, `POST /quizzes/results`.
- **Imports**: `database`, `progress_service`, `verified_braille`, `knowledge_base`.
- **Models**: `TutorQuestion`, `TutorTurn`, `TutorExampleInput`, `LearnerCreate`, `PracticeAttemptCreate`, `QuizResultCreate`.

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
- **Imports**: `database` (for `get_connection()`).

### `recommendation_service.py` — Adaptive Recommendations
- **Purpose**: Generates next-exercise recommendations based on learner progress.
- **Public API**: `get_recommendations()`.
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

### `migrate.py` — Database Migration Runner
- **Purpose**: Applies SQL migrations from `migrations/` directory.
- **Imports**: `database`.
- **Standalone script**, run before server start.

### `migrations/001_initial.sql`
- Creates `resonant` schema with tables: `learners`, `practice_attempts`, `quiz_results`.
- All tables namespaced under `resonant.` schema.

### `tests/`
| File | Tests |
|---|---|
| `test_api.py` | API route integration tests |
| `test_knowledge_base.py` | Evidence retrieval unit tests |
| `test_persistence.py` | Database CRUD tests |

## External Dependencies

| Package | Purpose |
|---|---|
| `fastapi` | Web framework |
| `uvicorn` | ASGI server |
| `requests` | HTTP client (Ollama API) |
| `psycopg[binary]` | PostgreSQL driver |
| `scikit-learn` | ML model for adaptive difficulty |
| `joblib` | Model serialization |

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `RESONANT_DATABASE_URL` | — | PostgreSQL connection string |
| `RESONANT_OLLAMA_URL` | `http://localhost:11434` | Ollama base URL |
| `RESONANT_OLLAMA_MODEL` | `qwen2.5:0.5b` | LLM model name |
| `RESONANT_AI_ENABLED` | `true` | Enable/disable AI tutoring |

