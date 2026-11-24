# Resonant ecosystem implementation progress

**Checkpoint date:** 2026-11-22  
**Working-tree policy:** Existing staged, unstaged, and untracked work is preserved. No reset, checkout, clean, or revert was performed.

## Recovered work already present

- Learner registration, account restoration, preferred-language sync, and offline attempt upload.
- Teacher signup/login, JWT authorization, teacher-scoped learner queries, dashboard data, learner detail, password reset, and account deletion code.
- PostgreSQL migrations `001` through `004` for learner progress, registration, teacher accounts, and teacher dashboard indexes.
- English, Hindi, and Kannada deterministic Braille engines and multilingual Flutter lesson/navigation work.
- Multilingual tutor grounding and deterministic Bharati verification work.
- An isolated `aiml/` research workspace with data contracts, leakage-aware splits, intent baselines, mastery-prediction pipeline code, recommendation-policy evaluation helpers, retrieval diagnostics, audit, reports, and explicit synthetic/external-data labels.

## Completed before this adaptive phase

### Test configuration

- Backend tests now install a test-only `RESONANT_JWT_SECRET` before importing the FastAPI app.
- Production startup behavior is unchanged: the server still fails closed when `RESONANT_JWT_SECRET` is missing.

### Action-capable tutor foundation

- Expanded deterministic intent detection for chapter navigation, named lessons, word/skill/module assessments, revision, targeted practice, difficulty requests, mastery, recommendations, language switching, pause, and resume.
- Added a separate tutor action validator. Parsed commands cannot directly mutate Flutter state.
- Unsupported or unavailable actions return a short clarification or an evidence-based blocked response instead of inventing curriculum content.
- Core commands remain available without Ollama because parsing and validation are local and deterministic.

### Chapter navigation foundation

- Added a dedicated curriculum navigation resolver with prerequisite and boundary checks.
- English Words navigation remains inside the Words module and preserves completed progress.
- Forward navigation cannot skip unfinished prerequisite word chapters.
- Named chapter and lesson destinations are resolved against the existing catalog.
- The English Words screen now supports nonvisual two-finger chapter navigation when it does not conflict with Braille writing, plus TalkBack custom actions for next and previous chapter.

### Tutor action execution

- Validated actions are applied by the existing Flutter state coordinator.
- Supported direct actions include current-skill assessment, eligible word assessment, revision from recorded local events, repeated-error practice, progress/mastery summaries, recommendation summaries, language switching, and pause/resume.
- Restarting a lesson or word chapter preserves prior completion records.

### Automatic character-lesson assessments

- Correct guided practice now transitions automatically into a separate lesson assessment for English, Hindi, and Kannada character lessons.
- Guided practice and assessment attempts have distinct IDs, so restoring progress does not confuse teaching practice with a completed assessment.
- Active assessments cannot be skipped through lesson gestures or tutor navigation.
- The assessment transition updates Flutter state immediately; persistence and speech no longer delay the next screen.

### Assessment persistence and teacher reporting

- Added additive migration `005_lesson_assessments.sql` for normalized sessions, questions, attempts, repeated-error summaries, and explainable adaptive decisions.
- Added `assessment_service.py`. It validates assessment targets against the deterministic English/Bharati engines, recomputes correctness from structured responses, categorizes supported errors, updates mastery transactionally, and records an evidence-based next action.
- Automatic assessments remain durable in the local offline event log and sync idempotently when a learner account and backend are available.
- Assessment upload requires the learner ID and locally held six-digit learner proof; production JWT behavior is unchanged.
- Teacher-scoped learner detail now includes real assessment history, the recorded next action/reason, and repeated-error counts. The Flutter teacher detail page renders those records without hardcoded values.

## Completed in the learner-side adaptive phase

### Durable adaptive decision integration

- Added `AdaptiveDecisionController`, with typed `remediate`, `reinforce`, `advance`, `reassess`, and `revise` actions and safe mappings for legacy backend action names.
- Added a durable local adaptive-decision inbox beside the lesson event log. Offline decisions survive restart, backend decisions reconcile by assessment submission ID, and lifecycle changes synchronize when the learner account and backend are available.
- Backend recommendations are validated against the active language and compiled curriculum before Flutter can execute them. Missing targets, cross-language targets, unsupported actions, and prerequisite-skipping advancement are blocked.
- Adaptive applications are serialized so a later assessment decision cannot be dropped while an earlier transition or announcement is finishing.

### Explainable personalized rules

- Offline and backend decisions use recorded correctness, wrong answers, attempt count, hints, repeated Braille-dot confusion, prior assessment accuracy, skill mastery, remediation history, and prerequisite completion where available.
- Every production adaptive decision is labeled `deterministic_rules` with a rule version and evidence. The separate synthetic scikit-learn demonstration is not presented as the learner decision engine and does not drive this flow.
- Automatic assignment of the same remediation is capped at two cycles. A learner who still struggles remains on a supported reassessment instead of entering an assignment loop.

### Remediation, reassessment, and advancement

- A failed character-lesson assessment now redirects to an explanation and focused verified-dot practice for the weak skill, then automatically opens reassessment.
- Successful reassessment completes the remediation lifecycle and advances only to the next prerequisite-safe lesson.
- Correct but effortful performance can assign short reinforcement before reassessment. Strong first-attempt performance completes an `advance` decision and unlocks the next eligible lesson without bypassing prerequisites.
- Active remediation blocks lesson, chapter, and language skipping while keeping the tutor, semantics actions, gestures, TTS, and Braille keyboard available.

### Teacher-visible adaptive outcomes

- Added migration `006_adaptive_decision_lifecycle.sql` for decision method, status, remediation cycle, mastery before/after, timestamps, and success outcome.
- Added learner-proof-authenticated lifecycle updates at `POST /learners/{learner_id}/adaptive-decisions/{decision_id}/status`.
- Teacher learner reports and Flutter detail views now show why a learner was redirected, the weak skill, assigned lesson, deterministic decision method, lifecycle status, remediation outcome, and mastery change.

### Deterministic tutor actions

- The local tutor command path can start required remediation, start an eligible test, start revision, resume the learner's current work, and explain why a lesson was selected.
- Commands are parsed locally and validated by `TutorActionController`; LLM text cannot directly mutate navigation or bypass an active assessment/remediation prerequisite.

### Regression hardening

- Scoped the assessment double-submit guard to the current exercise and serialized adaptive applications, preventing a fast learner interaction from losing the next decision.
- Remediation opens directly in the accessible Braille practice state instead of waiting for persistence or speech to finish.

## Completed in the public educational ML experiment phase

### Genuine dataset and reproducible task

- Selected the official corrected ASSISTments 2009-2010 Skill Builder dataset
  and verified the local Latin-1 CSV: 64,412,812 bytes, SHA-256
  `162ef8d2d28bcbfea6591a282994062bd8d5eaa00636544292a0d268dca6e5da`,
  346,860 rows, 4,217 learners, 26,688 questions, and 149 non-null skills.
- The original `correct` field is the only target: 123,042 incorrect/help-used
  rows and 223,818 correct-first-attempt rows. No synthetic learner records or
  fabricated metrics are used in this experiment.
- Raw data remains under the ignored `aiml/data/raw/` tree and the trained
  binary remains under ignored `aiml/artifacts/`. Public provenance, citation,
  terms notes, checksums, code, and generated evaluation reports are retained.

### Leakage-safe experiment and genuine results

- Added source/schema/type/target validation, missingness and duplicate
  analysis, and point-in-time learner/same-skill features that use only
  strictly earlier interactions. Learner, question, assignment, class,
  teacher, school, template, and answer identifiers are excluded from the
  predictive matrix.
- Used a reproducible learner-grouped holdout with seed `20261122`: 277,228
  rows from 3,373 learners for training and 69,632 rows from 844 disjoint
  learners for test; learner overlap is zero.
- Trained a prior baseline, balanced Logistic Regression, and fixed
  Random Forest. Random Forest held-out accuracy is 0.6935, correct-class
  precision 0.7858, recall 0.7215, F1 0.7523, macro F1 0.6753, ROC-AUC
  0.7529, PR-AUC 0.8365, and Brier score 0.2012. The confusion matrix is
  `[[15889, 8834], [12506, 32403]]` for `[incorrect, correct]`.
- Generated actual classification reports, confusion matrices/plots,
  calibration plots, model comparison, feature importance, dataset profile,
  experiment metadata, sample prediction files, and a reproducible faculty
  demonstration guide.

### Isolated FastAPI prediction boundary

- Added `educational_ml_service.py` and bounded `POST /aiml/predict`.
  Inference validates the exact feature schema and a trusted local artifact,
  returns model/dataset/experiment metadata plus an explicit experimental
  scope warning, and always returns `learning_action: null`.
- Missing, corrupt, incompatible, or non-probabilistic artifacts fail closed.
  The service never accepts learner identifiers, raw answers, current outcomes,
  or user-uploaded joblib paths.
- The genuine fitted artifact produced prediction `0` with probability
  `0.3918909660537665` for the checked-in held-out sample request. The FastAPI
  handler reproduced that response. End-to-end ASGI transport could not be
  verified on this host because its Python asyncio runtime hung even for a
  zero-work event loop; repeat the documented HTTP demonstration in a normal
  backend runtime.
- Flutter was intentionally not connected to this non-Braille model. Existing
  deterministic prerequisites, remediation caps, duplicate suppression,
  assessment lifecycle, offline operation, synchronization, mastery, and
  teacher reporting remain authoritative and unchanged.

## Completed in the Resonant ML integration phase

### Governed data and prediction foundation

- Added migration `007_resonant_ml_adaptive_foundation.sql` for versioned
  mapping provenance, structured learning-error metadata, model versions,
  point-in-time prediction records, adaptive-question instances, and links
  from adaptive decisions to their prediction/question provenance.
- Added an engine-derived multilingual mapping registry and deterministic
  missing-dot, extra-dot, substitution, multi-dot, cell-order, no-input,
  invalid-input, and technical-failure classification. Technical input failures
  do not lower mastery or trigger remediation.
- Defined the exact `resonant-next-attempt-v2` task: probability of an
  incorrect future eligible attempt from strictly earlier learner history.
  Current/future outcomes and personal identity fields are excluded.

### Qualification-gated hybrid controller

- Added `resonant_ml_service.py`. It loads only a trusted, consented-data,
  schema-compatible, language-qualified, human-reviewed Resonant artifact.
  Missing, unqualified, unsupported-language, or failed artifacts return an
  explicit `cold_start_deterministic` result.
- Qualified model advice may make a validated next exercise more conservative
  or change difficulty by one bounded step. Deterministic correctness,
  curriculum, mastery, prerequisites, mappings, and final action validation
  remain authoritative.
- No authorized Resonant learner dataset or qualified artifact exists in this
  checkout. No production model was trained or promoted, and live operation is
  currently deterministic cold-start.

### Backend-to-Flutter decision and question integration

- After durable local persistence, Flutter waits up to 1.5 seconds for the
  assessment response. A valid backend decision is preferred; the local
  deterministic decision remains the offline/timeout fallback and later syncs.
- Adaptive question instance ID, source, version, mapping/curriculum versions,
  generation result, intervention, and feedback metadata persist locally and
  upload with reassessment evidence.
- Backend questions are revalidated in Flutter against language, skill, lesson,
  answer, compiled curriculum, and authoritative Braille cells. Invalid content
  is discarded; a deterministic `fallback_after_rejection` remains usable only
  after the same validation.
- Adaptive `revise` and `reassess` questions can open directly. Accessible
  learner messaging explains the selected activity and whether qualified model
  advice or deterministic fallback was used without exposing probabilities.

### Teacher provenance and governed AIML pipeline

- Teacher learner detail now renders recent prediction provenance and adaptive
  question provenance. Qualified-model probabilities are visible only to the
  teacher; cold-start rows are clearly labelled deterministic fallback.
- The AIML mastery runner uses the production feature schema, a learner-grouped
  chronological holdout, configurable sample/learner/ROC-AUC/Brier/language
  gates, and mandatory human approval before promotion.
- Added an authorization-manifest/HMAC PostgreSQL exporter that excludes names,
  contacts, codes, teacher identity, answers, audio, and transcripts. No export
  was performed because no authorized learner dataset was provided.
- See `docs/resonant-ml-integration-audit.md` for the detailed boundary audit.

## Completed in the first multilingual writing milestone

### Verified phrase and sentence progression

- Extended the existing English, Hindi, and Kannada catalogs to five ordered
  chapters: basics, characters, words, phrases, and sentences.
- Added authored phrase and sentence transcription only where the existing
  deterministic English or Bharati forward engine can encode every cell.
  Unsupported personalized names fail closed to a verified catalog fallback.
- Added personalized complete-sentence writing such as `My name is Namit.`;
  the learner submits capitalization indicators, letters, blank space cells,
  and punctuation through the existing six-dot keyboard.
- Cell-by-cell progress, repeat/hint actions, backspace, full-response reset,
  TTS, haptics, and screen-reader custom actions remain available without
  depending on visually displayed controls.
- Correct composed responses persist as structured lesson assessments with the
  authoritative target and ordered cells, then use the existing adaptive
  decision, offline inbox, synchronization, mastery, and teacher-report path.

### Explainable adaptive word ordering

- Added `AdaptiveWordRecommender`, an explicitly deterministic cold-start
  policy that ranks only verified curriculum words from local incorrect
  attempts, repeated attempts, hints, and later correct evidence.
- Integrated the ranking into eligible stage word assessments and the English
  Words lessons. It cannot invent a word, change a Braille mapping, alter the
  fixed mastery set, or bypass a prerequisite.
- Hindi and Kannada error evidence remains script-specific and can reorder only
  the validated word bank for that language.

### Prerequisite-safe tutor and resume behavior

- Named navigation can no longer jump directly to a later phrase or sentence
  exercise before earlier verified writing work is complete.
- Tutor validation now distinguishes phrase eligibility after word mastery from
  sentence eligibility after phrase completion; execution remains routed
  through the deterministic action controller.
- A passed saved word-mastery round now resumes at the first incomplete phrase,
  while incomplete word mastery remains in the Words module.
- Added an end-to-end widget test that enters a personalized complete sentence
  as ordered six-dot cells, verifies persisted assessment evidence, and checks
  prerequisite-safe advancement to the next sentence.

## Verification at this checkpoint

- Direct Flutter SDK `analyze --no-pub` — passed, **no issues found**.
- Direct Flutter SDK `test --no-pub --concurrency=1` — passed, **145 tests**.
- Latest backend verification from the preceding checkpoint:
  `python -m pytest resonant_backend/tests -q` — passed, **129 tests plus 39
  subtests**. It was not rerun for this Flutter-only milestone.
- Latest AIML verification from the preceding checkpoint:
  `python -m pytest aiml/tests -q` — passed, **42 tests**. It was not rerun for
  this Flutter-only milestone.
- Pytest verification used `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1` to isolate the
  project from unrelated user-site plugins. Backend tests used an ephemeral
  test-only `RESONANT_JWT_SECRET`; production startup still fails closed when
  the secret is absent.
- The full backend run initially exposed three legacy persistence-fixture
  failures because new telemetry attributes were assumed to exist. Practice
  persistence now supplies backward-compatible schema defaults while retaining
  technical-failure validation; the focused 7-test persistence file and full
  backend suite then passed.
- PostgreSQL migrations `005`, `006`, and `007` were not executed against a live database.
- No browser run was performed for teacher mode.
- No Android emulator, physical device, TalkBack, microphone, TTS, or haptic verification was performed in this checkpoint.
- No real Resonant or Braille learner dataset was inspected or used. The
  ASSISTments result uses genuine historical mathematics interactions as an
  external benchmark; all authored-demo and synthetic results remain labelled
  separately under `aiml/`.

## Important unfinished work

- Normalized lesson assessment now covers character lessons and the new
  authored phrase/sentence transcriptions, but not every basics, word,
  revision, or retention lesson.
- Current automatic character assessments contain one deterministic
  catalog-backed question, and each writing exercise has one authored target.
  Configurable multi-question assessment definitions remain unfinished.
- Curriculum is still primarily compiled into Flutter rather than managed from backend tables.
- The production learner loop has a qualified-model interface but currently
  runs deterministic cold-start because no authorized trained artifact exists.
  Knowledge tracing and the synthetic model remain evaluation/research
  pipelines, not validated real-world learner models.
- Teacher pages exist in Flutter code, but a laptop browser build and end-to-end authorization/database run have not been verified.
- The new sentence subset is engine-validated authored content, not a complete
  language course. Broader sentence/paragraph/contraction coverage, Hindi
  matra/conjunct expansion, and Kannada gunithakshara/ottakshara expansion
  still require standards review.
- Lifecycle synchronization is best effort while offline and requires the saved learner proof when connectivity returns.
- The hybrid interface is complete, but actual qualified-model influence has
  not been exercised with a real Resonant artifact. Current backend responses
  use explicit deterministic cold-start fallback.
- Controlled AI question rephrasing is implemented behind validation but the
  production assessment path currently keeps it disabled.
- Teacher-login and teacher-dashboard administration still use conventional
  Material controls. This milestone guarantees the learner route is
  buttonless; it does not claim the teacher route has been converted.

## Completed in the buttonless learner-interface milestone

- Added one shared `AccessibleActionSurface` that supports direct touch,
  keyboard/switch activation, TalkBack focus, the standard semantic tap action,
  and a named custom action without exposing button semantics or a pill-style
  control.
- Removed conventional button widgets and `button: true` semantics from the
  learner route: role selection, registration/restore, lesson and language
  navigation, assessments, progress/help, word learning, composed writing,
  tutor entry points, and Braille keyboard utilities.
- Replaced assessment answer pills with numbered, mutually exclusive semantic
  rows. Hint, check, progression, lesson selection, and word actions remain
  available through flat touch surfaces, voice, gestures, and TalkBack actions.
- Kept the six-dot Braille surface intact. Its accessible dot alternative now
  uses authoritative toggle semantics rather than circular Material buttons;
  tap and four-direction swipe submission remain tested.
- Added deterministic voice parsing for answers such as `answer b`, `choose
  answer two`, or a validated word choice. The action controller still
  validates the intent, and Flutter accepts only choices present in the current
  verified activity.
- Added a permanent source/semantics regression test for learner-facing button
  removal and updated assessment, onboarding, word-writing, compact-layout,
  role-routing, and keyboard tests.
- Backend and AIML suites were not rerun for this Flutter-only milestone. Their
  latest verified results remain **129 backend tests plus 39 subtests** and
  **42 AIML tests** from the preceding checkpoint.

## Exact next phase

Implement Milestone 2, error-driven dynamic assessment generation, by extending
the existing validated question service rather than randomizing a fixed list:

1. Select new letter, contrast, word, phrase, or sentence items from verified
   language-specific content using recorded wrong cells, missing/extra dots,
   confusions, hint use, attempts, recency, and mastery uncertainty.
2. Prevent immediate question repetition, keep prerequisite and taught-content
   boundaries authoritative, and fall back to deterministic catalog questions
   whenever generated content fails language, curriculum, or Braille checks.
3. Persist the selection reason and error evidence through the existing
   assessment/adaptive-decision lifecycle and expose it in the existing teacher
   report rather than creating another reporting path.
4. Add focused English, Hindi, and Kannada tests for repeated-error targeting,
   vocabulary validity, repetition avoidance, offline fallback, and model
   unavailability.

Infrastructure work from the preceding checkpoint remains required in parallel
before any production-model claim:

1. Apply migrations `005`, `006`, and `007` to a disposable PostgreSQL database and add a real transaction/API integration test covering assessment creation, prediction/fallback persistence, adaptive-question provenance, decision lifecycle synchronization, and teacher reporting.
2. Add configurable multi-question definitions for the already validated
   character and word skills, and extend normalized assessment coverage to the
   remaining word, revision, and retention lessons.
3. Browser-run the teacher dashboard and device-test TalkBack focus, TTS sequencing, haptics, microphone permissions, offline restart, and reconnect synchronization.
4. Expand the authored phrase/sentence banks only after standards review and
   the infrastructure checks above; keep unsupported contractions and language
   structures out of the production curriculum.
5. Use the authorization-gated exporter only after purpose-specific approval.
   Train or promote a Resonant artifact only after sufficient consented,
   pseudonymized data, leakage-safe evaluation, per-language qualification, and
   explicit human review exist.

Resume verification commands:

```powershell
& 'C:\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\flutter\bin\cache\flutter_tools.snapshot' analyze --no-pub
& 'C:\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\flutter\bin\cache\flutter_tools.snapshot' test --no-pub --concurrency=1
$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD = '1'
$env:RESONANT_JWT_SECRET = 'use-an-ephemeral-test-only-secret'
python -m pytest resonant_backend/tests -q
python -m pytest aiml/tests -q
```
