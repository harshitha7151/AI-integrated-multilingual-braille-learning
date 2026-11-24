# Changelog

## Unreleased

- Replaced conventional learner-facing Material buttons and button semantics
  with flat focusable action surfaces, voice commands, simple gestures, and
  TalkBack custom actions across role selection, learner registration, lesson
  navigation, assessments, progress/help, word activities, composed writing,
  and the six-dot keyboard. Teacher-administration pages remain outside this
  learner-interface milestone.
- Added deterministic spoken answer selection (`answer`, `choose`, or `select`
  plus an option/number), word-choice routing, and voice-accessible hint,
  repeat, and primary word actions without allowing tutor prose to execute an
  unvalidated curriculum action.
- Added a regression guard that rejects conventional button widgets or
  `button: true` semantics in learner-facing source files and verifies that the
  shared action surface is focusable, tappable, and not announced as a button.
  Full serial Flutter verification now passes 145 tests with clean analysis.
- Extended the existing English, Hindi, and Kannada curricula to verified
  phrase and sentence chapters. Learners can compose complete responses through
  ordered six-dot cells, including personalized `My name is ...` sentences;
  unsupported names fail closed to an encodable catalog sentence.
- Added explainable deterministic adaptive word ordering from recorded errors,
  repeated attempts, and hints. Recommendations stay inside the verified
  language-specific word bank, preserve the fixed mastery set, and cannot
  bypass prerequisites or claim trained-ML behavior.
- Added accessible composed-writing progress, blank space-cell entry,
  backspace/reset, TTS and semantic actions, structured assessment persistence,
  prerequisite-safe phrase/sentence advancement, and separate tutor validation
  for phrase versus sentence eligibility.
- Added end-to-end sentence-writing coverage and updated completed-word resume
  behavior so a passed mastery round continues to the first incomplete phrase.
- Integrated the governed Resonant next-attempt prediction boundary into the
  real assessment flow. The exact `resonant-next-attempt-v2` feature contract
  uses only prior learner history, loads only consented-data artifacts that
  pass schema, task, language, evaluation, and human-review qualification, and
  falls back explicitly to deterministic cold-start rules when unavailable.
- Added migration 007, versioned engine-derived English/Hindi/Kannada mapping
  records, deterministic dot-error/technical-failure separation, prediction
  provenance, adaptive-question instances, and links from adaptive decisions
  to their model/question evidence.
- Connected backend adaptive decisions to Flutter with a bounded 1.5-second
  synchronization window while preserving the durable offline decision.
  Backend questions are revalidated against Flutter language, curriculum,
  skill, answer, and authoritative Braille cells before they can be shown.
- Added accessible learner activity/model-mode messaging without probabilities,
  direct revise/reassess question handling, adaptive-question metadata upload,
  and teacher reporting for qualified predictions, cold-start fallback, model
  outcome, and question provenance.
- Added an authorization-manifest/HMAC learner-event exporter and a
  learner-grouped chronological mastery runner with configurable sample,
  learner, ROC-AUC, Brier, and per-language gates plus mandatory human review.
  No authorized Resonant dataset was exported and no production model was
  trained or promoted.
- Preserved backward compatibility for legacy practice-attempt callers by
  supplying safe defaults for the additive telemetry fields. Technical failures
  still require an explicit code and nonvalid input cannot count as correct.
- Verified this checkpoint with clean Flutter analysis, 143 serial Flutter tests,
  129 backend tests plus 39 subtests, and 42 AIML tests. Live PostgreSQL
  migrations 005-007, browser teacher mode, and Android accessibility/reconnect
  behavior remain unverified.
- Added `docs/resonant-ml-integration-audit.md` with the implemented boundary,
  evidence, limitations, and exact next infrastructure phase.
- Added a reproducible public-data educational outcome experiment using the
  corrected ASSISTments 2009-2010 Skill Builder CSV, with verified provenance,
  schema/missingness analysis, point-in-time history features, a learner-grouped
  holdout, prior and Logistic Regression baselines, and a trained Random Forest.
- Added genuine held-out metrics, confusion matrices, classification reports,
  calibration/model-comparison/feature-importance plots, experiment metadata,
  an ignored fitted joblib artifact, and a faculty demonstration guide.
- Added an isolated, bounded `POST /aiml/predict` route with trusted local
  artifact validation and fail-closed missing-model behavior. It is explicitly
  experimental, accepts no learner identifiers or current outcomes, returns no
  learning action, and does not alter deterministic learner adaptation.
- Earlier public-experiment checkpoint verification recorded 129 serial
  Flutter tests, 109 backend tests plus 39 subtests, and 37 AIML tests. The
  later current totals are recorded above.
- At that earlier checkpoint, migrations `005` and `006` had not run against a
  live PostgreSQL database, ASGI transport could not be exercised on this
  host's hanging asyncio runtime, and browser/device accessibility and reconnect
  behavior remained unverified.
- Set the next phase to disposable-database transaction/API integration,
  configurable multi-question assessments for validated skills, and browser
  plus physical-device accessibility/reconnect verification.
- Added a learner-side adaptive decision controller and durable offline inbox
  for remediate, reinforce, advance, reassess, and revise actions, with
  prerequisite validation, backend reconciliation, and duplicate/loop guards.
- Added focused remediation followed by automatic reassessment, strong-learner
  advancement, reinforcement for effortful success, and restart-safe pending
  decision restoration without disabling offline learning.
- Added deterministic tutor actions for remediation, eligible tests, revision,
  resume, and explaining why a lesson was selected; executable actions remain
  validated outside the LLM response path.
- Added migration 006, learner-proof lifecycle synchronization, and teacher
  reporting for adaptive reason, weak skill, assigned lesson, status, outcome,
  remediation cycle, and mastery change.
- Labeled the original production adaptation explicitly as deterministic rules.
  The separate synthetic trained-model work remains research/demo code and is
  not accepted by the governed learner-history model loader.
- Added automatic per-letter lesson assessments with distinct guided-practice
  and assessment event identities, offline durability, and accessible automatic
  progression for English, Hindi, and Kannada character courses.
- Added migration 005 and a dedicated assessment service for verified question
  targets, normalized sessions/questions/attempts, transactional skill mastery,
  deterministic error categorization, and explainable adaptive decisions.
- Added learner-code-authenticated assessment upload and teacher-scoped
  assessment/error reporting in the learner detail dashboard.

- Corrected the landscape keyboard's screen layout to the requested mapping:
  left column dots 1–3 and right column dots 4–6.
- Cancelled an active chord when a pointer is interrupted or dragged into a
  different zone, rather than treating it as a completed multi-dot input.
- Replaced the obsolete counter widget test with keyboard lifecycle tests and
  added initial English uncontracted Braille engine tests.
- Added a standards note documenting the engine's limited scope and the
  verification gap for Hindi and Kannada Braille-to-text behavior.
- Added bounded Ollama health/configuration and a safe offline tutor response.
- Added a grouped, synthetic-only ML training demonstration, saved model
  artifact, evaluation report, and rule-based inference fallback.
- Replaced the static English lesson index with six offline multiple-choice
  exercises, hints, retry feedback, and in-session completion tracking.
- Added a versioned PostgreSQL migration in an isolated `resonant` schema,
  persistence routes for learners, practice attempts, quizzes, and progress,
  plus UUID-based duplicate submission handling and mocked database tests.
- Added separate Hindi and Kannada forward Grade 1 mapping subsets from the
  NIEPVD 2025 Unicode chart, with published-cell fixtures and explicit errors
  for unsupported characters.
- Added durable on-device lesson attempt history with retry-stable event IDs;
  automatic server synchronization remains future work.
- Added an accessible English voice tutor with Android speech-to-text,
  typed fallback, contextual follow-ups, TTS replay/stop, private in-memory
  conversation handling, and backend-side verification for exact letter patterns.
- Added local-only Android cleartext networking for `localhost` to support a
  USB-forwarded phone demo without enabling cleartext to arbitrary hosts.
