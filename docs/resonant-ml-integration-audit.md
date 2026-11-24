# Resonant ML integration audit

**Audit date:** 2026-11-22  
**Scope:** Current repository state only. No live PostgreSQL database, browser,
Android device, or authorized Resonant learner export was available during this
audit.

## Executive finding

Resonant now has a genuine backend-to-Flutter hybrid adaptive architecture.
The backend can construct point-in-time learner-history features, load only a
qualified Resonant model, persist prediction provenance, select a validated
adaptive question, and return the result through the existing assessment API.
Flutter briefly waits for that response, reconciles it with its durable offline
decision, revalidates the question against the local curriculum and
authoritative Braille engine, and applies only a prerequisite-safe action.

No authorized Resonant learner dataset or qualified production artifact exists
in this checkout. Therefore the current operational result is an explicit
`cold_start_deterministic` fallback. No real learner prediction performance is
claimed, and the genuine public ASSISTments mathematics experiment remains
isolated from Braille progression.

## Implemented data foundations

### Versioned Braille mapping foundation

- `resonant_backend/braille_mapping_registry.py` derives structured English,
  Hindi, and Kannada records directly from deterministic engine tables.
- Records include language, Unicode identity, cells, dot positions, curriculum
  skill/lesson IDs, source, validation status, mapping version, and scope.
- Duplicate identifiers, conflicting mappings, invalid languages, and invalid
  cell values are rejected.
- This registry is validation/provenance data. It is not a learned mapping and
  never replaces the Flutter or backend encoders.

### Learning-error foundation

- `resonant_backend/learning_error_service.py` separates valid learning errors
  from no input, invalid input, and technical input failure.
- Deterministic categories include missing dot, extra dot, dot substitution,
  multiple-dot error, cell-order error, and character confusion.
- Technical failures are retained for reliability analysis but do not lower
  mastery, resolve a learning prediction, or trigger remediation.
- Migration `007_resonant_ml_adaptive_foundation.sql` adds structured expected
  and submitted responses, mapping/curriculum versions, intervention and
  feedback metadata, and prediction/question provenance.

### Learner-history foundation

- Practice and assessment records supply only events strictly earlier than the
  prediction timestamp.
- The production schema is `resonant-next-attempt-v2` and includes language,
  skill, question type, prior attempts and errors, smoothed/recent accuracy,
  hint and response-time history, spacing, consecutive errors, missing/extra
  dot rates, revision count, prior intervention success, and current
  difficulty.
- Learner identifiers are used only to retrieve or split history; they are not
  model features. Names, contact details, teacher identity, codes, audio, and
  tutor transcripts are excluded.

### Multilingual boundary

- Deterministic validated content supports the repository's current English,
  Hindi, and Kannada subsets.
- A model artifact must declare supported languages, and each declared language
  must have passed configured evaluation gates. Unsupported or unevaluated
  languages remain in deterministic cold-start mode.
- No multilingual model performance has been measured.

## Predictive task and qualification

The production task is the probability that a learner's future eligible
attempt on a specific skill will be incorrect. The current attempt outcome and
all future events are excluded from its feature snapshot.

`resonant_backend/resonant_ml_service.py` accepts only a trusted local artifact
that matches all of the following:

- artifact kind `resonant_next_attempt`;
- task `probability_of_incorrect_future_attempt`;
- exact `resonant-next-attempt-v2` feature order;
- consented Resonant event provenance;
- incorrect-class label contract;
- declared supported languages;
- automated qualification gates;
- explicit human review; and
- a probabilistic fitted model.

Missing, incompatible, unreviewed, unsupported-language, or failed-inference
artifacts return an explicit deterministic fallback rather than a fabricated
model result.

The AIML mastery runner uses a learner-grouped chronological holdout, configurable
row/learner/ROC-AUC/Brier/language gates, and a separate human approval field.
Promotion is possible only when every gate passes and promotion is explicitly
requested. No production model was trained or promoted.

## End-to-end adaptive flow

1. Flutter scores an assessment with the deterministic Braille dispatcher and
   immediately stores the event plus an explainable offline decision.
2. If a learner account and backend are available, Flutter waits up to 1.5
   seconds for `POST /learners/{learner_id}/assessments`; otherwise it continues
   with the offline decision and retries synchronization later.
3. The backend revalidates question targets, recomputes correctness, classifies
   errors, updates mastery transactionally, and resolves the newest prior
   prediction with the observed outcome.
4. The backend builds the next point-in-time feature snapshot and either uses a
   qualified Resonant model or records deterministic cold-start provenance.
5. Qualified high/low risk may conservatively alter reinforcement or one
   difficulty step. It cannot change verified correctness, mastery evidence,
   prerequisites, curriculum identity, or Braille mappings.
6. The backend selects a question from the validated mapping-backed bank,
   avoids recent IDs, persists its source/version/mapping metadata, and returns
   it inside the adaptive decision.
7. Flutter reconciles the backend decision by assessment submission ID and
   revalidates language, skill, lesson, answer, curriculum membership, and
   authoritative Braille cells before display.
8. Invalid backend question content is discarded. The catalog-backed question
   remains available, and a deterministic `fallback_after_rejection` question
   is accepted only when it passes the same Flutter validation.
9. Remediation/reinforcement leads to focused practice and automatic
   reassessment. Advancement remains prerequisite-safe. Duplicate remediation
   and infinite reassignment are capped by the durable local decision inbox.

## Controlled AI question handling

The backend contains a constrained Ollama rephrasing path. It can change only
question wording and options drawn from verified language content. Language,
skill, difficulty, answer, and Braille cells are validated against the
deterministic base question. Rejected or unavailable generation returns a
validated deterministic fallback.

The production assessment path currently calls question selection with
`try_ai=False`; learning therefore does not depend on the LLM.

## Learner, tutor, and teacher behavior

- Learners receive plain-language recommended-activity and model-mode messages.
  Technical probabilities are not announced or displayed to learners.
- Tutor commands for remediation, testing, revision, resume, and explanation
  are parsed locally and must pass `TutorActionController`; LLM prose cannot
  directly navigate or mutate learner state.
- Teacher reports include adaptive reason, skill, assigned lesson, lifecycle,
  mastery change, prediction source/version/outcome, fallback reason, and
  adaptive-question provenance.
- Probabilities appear in teacher reporting only for a valid qualified-model
  prediction. Cold-start rows are explicitly labelled deterministic fallback.

## Research-data safeguards

`aiml/experiments/mastery_prediction/export_authorized_events.py` requires an
unexpired authorization manifest, a matching explicit approval value, a
minimum 32-byte HMAC pseudonym key, an allowlisted learner set, and an output
under the ignored `aiml/data/processed/` directory. It does not export names,
contact details, learner codes, raw answers, teacher IDs, audio, or transcripts.

No such export was performed in this checkpoint.

## Verification

- Flutter analysis through the direct SDK snapshot: no issues found.
- Full serial Flutter suite: 133 tests passed.
- Full backend pytest suite: 128 tests and 39 subtests passed.
- Full AIML pytest suite: 42 tests passed.
- Backend tests used an ephemeral test-only JWT secret. Production startup
  still fails closed when `RESONANT_JWT_SECRET` is absent.

## Unverified and unfinished

- Migrations `005`, `006`, and `007` have not been applied to a live disposable
  PostgreSQL database in this checkpoint.
- No end-to-end database transaction/API/reconnect test has used real
  PostgreSQL.
- No qualified Resonant model exists, so actual model influence in the learner
  UI has not been exercised outside controlled test artifacts.
- Browser teacher reporting and Android TalkBack, TTS, microphone, haptic,
  offline-restart, and reconnect behavior were not rerun.
- Automatic assessments are still not comprehensive across every word,
  sentence, revision, and retention lesson.
- Controlled AI question rephrasing is implemented but intentionally disabled
  in the production assessment call path.

## Recommended next phase

1. Apply migrations `005` through `007` to a disposable PostgreSQL instance and
   run an end-to-end assessment → prediction/fallback → question → lifecycle →
   teacher-report test.
2. Device-test offline restart/reconnect and accessibility behavior before
   expanding curriculum coverage.
3. Add configurable multi-question definitions only for already verified
   skills.
4. Obtain purpose-specific authorization and sufficient pseudonymized learner
   history before running the Resonant mastery experiment.
5. Promote no model until all automated gates, per-language evidence, privacy
   review, and explicit human approval are satisfied.
