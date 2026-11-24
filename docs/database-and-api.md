# PostgreSQL persistence

## Safe schema boundary

The repository did not contain a schema dump or migration history, and this
environment has no `RESONANT_DATABASE_URL`. To avoid changing unknown legacy
tables, Resonant's new tables live under a separate PostgreSQL schema named
`resonant`. The migration does not drop, rename, or alter `public` tables.

The first migration creates:

- `resonant.learners` — UUID learner ID, username, preferred language, and
  creation time.
- `resonant.practice_attempts` — idempotent event records, including correct,
  incorrect, cancelled, accidental-touch, and timeout outcomes.
- `resonant.quiz_results` — idempotent quiz submissions and scores.
- `resonant.skill_progress` — correct-answer counts, mastery estimate, average
  response time, and next review time.
- `resonant.schema_migrations` — applied migration versions.

Migration 002 extends `resonant.learners` with teacher-assisted registration
fields: `name`, `phone`, `email`, `batch`, `consent_at`, `code_hash`, and
`registered_by`.  Partial unique indexes enforce uniqueness for non-NULL
`phone` and `email` while allowing multiple `NULL` values (standard
PostgreSQL behaviour).  The 6-digit learner code is **never stored in
plain text**; only its SHA-256 hash is persisted.  Phone numbers and email
addresses are never written to application logs.

Migration 003 adds the `resonant.teachers` table (`teacher_id`, `name`,
`email`, `password_hash`, `organization`, `created_at`).  A partial unique
index enforces `lower(email)` uniqueness.  A nullable `teacher_id` foreign
key is added to `resonant.learners` to link each learner to their
registering teacher.  Passwords are hashed with bcrypt and are never stored
in plain text or logged.  The column `registered_by` (TEXT, from 002) is
kept as-is for legacy rows; new registrations use the typed `teacher_id` FK.

Migration 004 adds an index on `resonant.learners (teacher_id, created_at DESC)`
to support performant teacher dashboard queries. All learner metrics
(last_active_at, accuracy percentage, 7-day attempt counts, top weak skills,
and activity status) are computed dynamically from `resonant.practice_attempts`
and `resonant.skill_progress`.

Migration 005 adds normalized `assessment_sessions`, `assessment_questions`,
`assessment_attempts`, `assessment_error_summaries`, and `adaptive_decisions`.
It is additive and keeps existing practice/quiz history intact. Assessment
responses are structured JSON (for example, a selected character and verified
cell masks); the API does not store audio, speech transcripts, or touch paths.
Each submission UUID is idempotent. Session insertion, question attempts,
mastery updates, error counts, and the explainable next action share one
database transaction.

Migration 006 extends `adaptive_decisions` with an explicit
`deterministic_rules` method label, lifecycle status, remediation cycle,
mastery before/after, applied/completed timestamps, and success outcome. It
also preserves legacy action names while allowing the learner-side
`remediate`, `reassess`, and `revise` mappings. The migration is additive.

Migration 007 adds the governed ML/adaptive foundation without replacing any
existing records. It versions authoritative mapping provenance, extends
practice/assessment attempts with structured input/error/intervention metadata,
and creates `ml_model_versions`, `ml_predictions`, and
`adaptive_question_instances`. Adaptive decisions gain optional prediction,
question, model, bounded-difficulty, and fallback provenance. A prediction row
may represent either qualified model output or explicit deterministic
cold-start fallback.

Each write uses a psycopg connection context, so the event insert and mastery
update commit or roll back together. Submission UUIDs prevent retries from
creating duplicate attempts or quiz results. Only correct and incorrect
answers affect mastery; interrupted and accidental events remain in history
without being counted as lack of knowledge.

## Configure and migrate

Set `RESONANT_DATABASE_URL` in the backend process environment. Keep real
credentials out of source control and logs. From `resonant_backend`, apply
migrations before starting the API:

```powershell
python -m pip install -r requirements.txt
$env:RESONANT_DATABASE_URL = "postgresql://USER:PASSWORD@HOST:5432/DATABASE"
python migrate.py
python -m uvicorn main:app --reload
```

The migration runner takes a transaction-scoped advisory lock and records each
successful version. The SQL is additive and scoped to `resonant`.

## API routes

- `GET /health` checks application availability without touching dependencies.
- `GET /health/database` checks PostgreSQL availability.
- `POST /learners` creates or updates a legacy learner row. Requires a teacher
  `Bearer` token and only updates an existing username owned by that teacher.
- `GET /learners/{learner_id}` reads a learner profile only with the matching
  six-digit code in the `X-Learner-Code` header.
- `POST /learners/register` — teacher-assisted registration.  **Requires a
  valid teacher `Bearer` token** (`Authorization: Bearer <token>`).  Accepts
  `name` (required), `phone` (digits, 7–15 chars), `email`, `batch`,
  `preferred_language`, and `consent` (boolean).  At least one of `phone`
  or `email` is required; `consent` must be `true`.  Stores the registering
  `teacher_id` from the token.  Returns `learner_id` and a one-time
  plaintext `learner_code` (6 digits, hashed before storage).
- `POST /learners/restore` — restore an account on a new device.  Accepts
  `phone_or_email` and the 6-digit `code`.  Returns the learner profile on
  success; 404 if credentials do not match.
- `POST /teachers/signup` — create a teacher account.  Accepts `name`,
  `email`, `password` (min 8 chars), `organization` (optional).  Returns
  the teacher profile; 409 if email already registered.  Passwords are
  bcrypt-hashed and never logged.
- `POST /teachers/login` — verify credentials; return a signed JWT token
  (30-day expiry).  Rate-limited to 10 attempts per email per 10 minutes;
  returns 429 when exceeded.  Returns 401 on wrong credentials.  Emails
  and passwords are never logged.
- `GET /teachers/me/learners` — list this teacher's registered learners
  (id, name, batch, created_at).  Requires `Authorization: Bearer <token>`.
- `GET /teachers/me/dashboard` — dashboard summary and list of all learners
  belonging to the authenticated teacher. Returns summary metrics (total,
  active this week, struggling count) and per-learner details (id, name,
  batch, last_active_at, current stage/letter, accuracy %, 7-day attempt
  count, top 3 weak letters, status). Requires `Authorization: Bearer <token>`.
- `GET /teachers/me/learners/{id}` — detailed metrics and recent 50 attempt
  records for a single learner. Includes contact info (phone/email). Returns
  404 if the learner does not exist or belongs to another teacher. Requires
  `Authorization: Bearer <token>`.
- `POST /teachers/forgot-password` — returns HTTP 503 until a real reset-token
  delivery provider is configured. It does not create or log a reset token and
  explicitly reports that no reset email was sent.
- `POST /teachers/reset-password` — verifies the reset token and updates the
  teacher's bcrypt password hash.
- `DELETE /learners/{id}` — permanently removes a learner and cascades to all
  their attempts, quiz results, and skill progress. Requires `Authorization: Bearer <token>`
  and only allows deleting learners assigned to the calling teacher (404 otherwise).
- `DELETE /teachers/me` — deletes the calling teacher's account. Preserves
  all associated learners and their learning records by setting `teacher_id = NULL`.
  Requires `Authorization: Bearer <token>`.
- `POST /practice/attempts` records an idempotent practice event and updates
  skill progress for correct/incorrect answers. The request must include the
  matching learner UUID and six-digit `learner_code`.
- `GET /learners/{learner_id}/progress` reads skill mastery only with the
  matching six-digit code in the `X-Learner-Code` header.
- `POST /quizzes/results` records an idempotent quiz result only after checking
  the submitted learner UUID against its six-digit `learner_code`.
- `POST /learners/{learner_id}/assessments` records a completed automatic
  lesson assessment. It requires the learner's six-digit restore code, validates
  every target against the deterministic English or Bharati engine, computes
  correctness from structured responses, updates mastery/error records, builds
  a point-in-time next-attempt prediction or explicit cold-start fallback,
  selects a mapping-backed adaptive question when appropriate, and returns the
  recorded explainable adaptive decision. Flutter independently revalidates a
  returned question before display.
- `POST /learners/{learner_id}/adaptive-decisions/{decision_id}/status`
  synchronizes an applied/completed/superseded decision using the learner's
  six-digit proof. It records remediation success and optional client mastery
  without allowing the client to rewrite the original action or evidence.
- `GET /teachers/me/learners/{learner_id}/assessments` returns assessment
  history and repeated-error summaries only when the learner belongs to the
  authenticated teacher. Reports include the redirect reason, weak skill,
  assigned lesson, deterministic method, lifecycle status, remediation cycle,
  success outcome, mastery change, prediction provenance/outcome, and adaptive
  question provenance. Qualified-model probabilities are teacher-visible;
  deterministic fallback is labelled and not presented as trained output. The
  same fields are included in the existing teacher learner-detail response.
- `GET /adaptive/model/status` returns non-sensitive qualification/fallback
  diagnostics for the governed Resonant model boundary.
- `POST /learners/{learner_id}/adaptive/predict` requires the learner's
  six-digit proof and persists one auditable future-attempt prediction or
  deterministic cold-start estimate. It accepts bounded skill, language,
  question-type, and difficulty context; it does not let a client submit an
  outcome or override progression.
- `POST /aiml/predict` runs the isolated public-dataset educational outcome
  experiment. It accepts only bounded prior-history aggregates and current
  question metadata; learner IDs, current outcomes, answer text, and learning
  actions are not accepted. The response includes a binary estimate,
  probability, model/dataset/experiment metadata, `experimental: true`, and
  `learning_action: null`. A missing or invalid trusted local artifact returns
  HTTP 503. This route is not connected to assessment decisions or Flutter
  progression.

Request models validate languages, event types, lengths, score bounds, and
durations. SQL values use parameters. Backend tests mock the database
connection; no PostgreSQL server was available here, so migrations `005`–`007`,
constraints, transaction behavior, and SQL compatibility still require a real
database integration run.

The Flutter app also writes a local JSON event log in application documents
for offline multilingual lesson attempts. It assigns a new UUID to each event
and queues pending events locally (`synced_at: null`). Ordinary practice events
sync to `/practice/attempts`; structured automatic lesson assessments sync to
`/learners/{learner_id}/assessments` with the locally held learner proof.
Adaptive decisions are stored in a separate local JSON inbox. Matching backend
responses reconcile by assessment submission ID, and unsynchronized lifecycle
changes retry after connectivity returns without blocking offline learning.

## Privacy and authentication notes

Learner-scoped profile/progress reads and practice/quiz writes require the
existing learner code to match the UUID in the request. Teacher-managed legacy
learner creation and learner registration require a teacher `Bearer` token.
Teacher learner views and deletion remain scoped to the authenticated teacher.
The password-reset endpoint is intentionally unavailable until a real delivery
provider is configured; it does not emit tokens to logs.

Learner codes contain six digits and are rate-limit protection sensitive. The
current API does not yet have a persistent, shared learner-code attempt
throttle. Keep the API on a trusted development network with transport
protection before using private learner records in a deployment.

Set `RESONANT_JWT_SECRET` to a long random value in production to sign
teacher tokens.  Tokens have a 30-day expiry and are validated on every
authenticated request.

The optional public-dataset artifact defaults to
`aiml/artifacts/assistments_2009_rf_v1.joblib`. Override it only with the
administrator-controlled `RESONANT_EDUCATIONAL_ML_ARTIFACT` environment
variable. Never load user-uploaded joblib files because deserialization is a
trusted-code operation.

The governed learner-history service separately uses `RESONANT_ML_ARTIFACT`
and accepts paths only under the repository's trusted artifact directories.
Its artifact must declare consented Resonant training data, the exact
prediction task and feature schema, supported languages, passing qualification
gates, and human approval. No qualified artifact currently exists, so this
service returns explicit deterministic cold-start provenance.
