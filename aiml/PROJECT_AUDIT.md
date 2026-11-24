# Resonant AIML project audit

**Audit date:** 2026-11-21  
**Scope:** Repository code and checked-in migrations/tests. No live PostgreSQL instance or production learner export was inspected. This document describes code as it exists in this checkout, not every deployment.

## Executive summary

Resonant already records useful practice events and computes a transparent, deterministic mastery estimate. It also contains a separately trained logistic-regression demonstration built only from generated synthetic histories. That artifact is not connected to practice records or learner-facing recommendations. The current recommendation selector is rules-based. The tutor combines deterministic mapping routes, small keyword-scored curated evidence, and Ollama-generated explanations; it is not an ML intent classifier or embedding-based RAG system.

Since the initial audit, the repository has added a separate governed
`resonant-next-attempt-v2` integration. It can consume only a qualified model
trained from authorized consented Resonant events and otherwise records an
explicit deterministic cold-start result. The interface, qualification runner,
question provenance, Flutter validation, and teacher reporting are implemented;
no authorized dataset, qualified artifact, or real Resonant metric exists.

The project can support carefully defined future experiments, but the checked-in data is not evidence of real-world learning effectiveness. Database availability, learner-event volume, event quality, and consented research eligibility were not verified here. No real learner records were copied, inspected, or used for modeling in this audit.

## Existing architecture and flow

### Flutter learner app

- `lib/main.dart` coordinates language, lesson/chapter navigation, keyboard practice, tutor activation, TTS, haptics, and persisted resume state.
- `lib/learning/lesson_catalog.dart` provides the current lesson and exercise definitions. `lib/core/braille/braille_dispatcher.dart` routes language mappings to the deterministic English, Hindi, and Kannada engines.
- `lib/learning/lesson_progress_store.dart` writes a device-local JSON event log and per-language resume state. Events include a random submission UUID, exercise/skill IDs, language, exercise type, binary correct/incorrect outcome, response time, hint-used flag, attempt number, and creation time. Pending events can be uploaded to `/practice/attempts` when a learner account and network are available; unique submission IDs make retries idempotent.
- `lib/tutor/voice_tutor_controller.dart`, `http_tutor_gateway.dart`, `local_braille_tutor.dart`, and `voice_tutor_panel.dart` implement speech/typed tutor interaction, remote requests and deterministic/offline responses.
- These parts are relevant to ML only as event producers and consumers. The Flutter interface itself does not train models.

### FastAPI and PostgreSQL

- `resonant_backend/main.py` defines tutor, learner, practice, quiz, registration, and teacher routes. Practice payload validation bounds the outcome, language, exercise type, timing, and attempt number.
- `progress_service.py` inserts attempts and quiz results idempotently. Correct and incorrect outcomes update `skill_progress` in the same transaction. Non-answer events are retained but excluded from mastery calculations.
- Migrations `001`–`007` create the isolated `resonant` schema and add
  registration, teacher, dashboard, normalized assessment, adaptive lifecycle,
  and governed ML/question provenance. Migration 007 is ML-specific and
  additive, but it has not been executed against live PostgreSQL here.
- `database.py` reads `RESONANT_DATABASE_URL`. The actual configured database, deployed schema version, and whether production records exist were not inspected.

### Checked-in data structures

| Structure | Stored fields | ML-relevant meaning and gaps |
|---|---|---|
| `resonant.learners` | UUID, username, preferred language, creation time; later migrations add name, phone, email, batch, consent timestamp, registration code hash, registering teacher and teacher FK | A UUID is available for grouping/temporal splits. Contact/identity fields are present and must never enter features. Consent timestamp exists for teacher-assisted registration, but its wording/scope does not by itself establish permission for research/model training. |
| `resonant.practice_attempts` | Core attempt fields plus migration-007 session/question/character, difficulty, structured expected/submitted response, input status, mapping/curriculum version, intervention, and feedback fields | Supports point-in-time outcome prediction and richer provenance. Older rows may retain defaults or missing optional values. Prerequisite/exposure/app-version context remains incomplete, and live data quality is unmeasured. |
| `resonant.skill_progress` | Learner/skill/language key, attempts, correct count, smoothed mastery, average response ms, next-review time, update time | This is a derived operational summary. `mastery` and `next_review_at` are generated by deterministic update rules, not observed ground truth. They must not be treated as independent labels or as input to a target that leaks the same future outcomes. Prefer reconstructing features from the event log as-of each prediction time. |
| `resonant.quiz_results` | Unique submission ID, learner ID, quiz ID, language, score, max score, duration, completion time | Supports quiz-score analysis. No per-item answers or stable item-level difficulty are stored in this table. |
| Local JSON progress log | Same core practice fields, optional learner ID, group ID, timestamps and sync marker | Offline events exist before sync. For research exports, avoid mixing duplicate server copies with local copies; use `submission_id` for deduplication and document missing/unsynced events. |

Teacher registration stores personal contact data. The ML pipeline must export a pseudonymous learner key and a minimal allowlisted feature schema; it must exclude name, username, phone, email, batch, teacher identity, registration codes/hashes, and raw tutor text/audio. Existing teacher and learner routes also need a deployment-level authorization/privacy review before any training export is enabled.

## Current AI/ML inventory (truthful labels)

| Component | Actual method | Current use | Status |
|---|---|---|---|
| English/Hindi/Kannada Braille mapping and validation | Deterministic lookup/encoding engines | Produces and validates Braille cells; remains authoritative | Not ML; mapping coverage is governed by engine fixtures and standards references. |
| Tutor evidence retrieval (`knowledge_base.py`) | Curated in-code documents with token/keyword matching and hand-authored relevance rules | Supplies language/lesson evidence to tutor requests | Rule-based lexical retrieval. It does not use embeddings or a vector database. |
| Tutor prose (`main.py` → Ollama) | External local LLM generation, bounded by prompt/evidence and output checks | Explains supported educational concepts when model service works | LLM, not a trained Resonant classifier. Mapping answers are routed through deterministic tables. |
| Learner mastery update | Smoothed correctness counts, response-time average, fixed review intervals | Updates persisted skill summaries | Deterministic online aggregation/rules, not learned from data. The formula is an operational heuristic, not a validated mastery instrument. |
| Operational recommendation selector (`recommendation_service.py`) | Due-first then lowest-mastery sorting with deterministic tie breaks | Unit-tested helper; no learner-facing app integration found in this checkout | Rule-based baseline, not ML. No evaluated relevance or learning-gain result. |
| Adaptive probability demo (`train_adaptive_demo.py`, `adaptive_ml.py`) | Generated synthetic longitudinal data; `StandardScaler` + Logistic Regression; grouped train/test split by synthetic learner; `joblib` artifact | Artifact tested for bounded inference/fallback but not called from the production recommendation path | ML software demonstration only. Synthetic distribution/label are authored by a simulator. Its metrics do not measure real Resonant learners and must not be used for learner decisions. |
| Governed future-attempt prediction (`resonant_ml_service.py`, mastery runner) | Exact point-in-time feature schema; qualified probabilistic artifact or explicit cold-start fallback | Integrated into assessment decisions, validated questions, Flutter reconciliation, and teacher provenance | Production interface exists, but no authorized export/model/result. Current behavior is deterministic fallback. |

The demo predicts synthetic next-attempt correctness from synthetic prior accuracy, attempt count, average response seconds, hint rate, days since practice, smoothed mastery, and exercise difficulty. In this checkout the script compares Brier score/log loss to a train-prevalence baseline. It does not provide real-data evidence, production validation, or proof that these features are available in the database in the same form.

## Tests inspected

- Flutter tests cover lesson/catalog behavior, progress log persistence/sync, language/navigation, keyboard-related behavior, tutor gateway/controller, Braille engines, and teacher/account flows. They are software behavior tests, not evidence of live database or real-learner model quality.
- Backend tests cover API validation/routes, curated retrieval, persistence with mocked connections, recommendation baseline behavior, synthetic model loading/fallback, and grouped splitting of the synthetic demo.
- No tests train on a consented real Resonant export or establish calibration,
  recommendation quality, learning gain, or multilingual performance on real
  Braille learners.
- New tests do exercise point-in-time feature construction, learner-grouped
  chronological splitting, qualification and human-review gates, trusted
  loading/fallback, bounded hybrid advice, adaptive-question validation, and
  teacher/Flutter provenance. These remain software tests, not learner-model
  performance evidence.

## Defensible experiment architecture

1. Keep source acquisition and license/provenance metadata separate from processing. Never commit restricted learner exports or downloaded benchmark archives.
2. Validate schema, event uniqueness, temporal ordering, language and outcome domains, missingness, duplicate sync records, and learner-level counts before feature creation.
3. Build point-in-time features only from events strictly earlier than the prediction timestamp. Keep learner IDs for split logic but never as predictive features.
4. Use the official dataset split when available for benchmark reproduction. For Resonant data, prefer forward-in-time evaluation; additionally report learner-held-out performance if the intended use includes unseen learners. Do not randomly scatter one learner's future attempts across train and test.
5. Establish simple baselines first. Report per-class metrics for intent work, and learner/sample counts, prevalence, PR-AUC/F1, ROC-AUC where defined, Brier/log loss and calibration for binary outcome prediction. Treat small or imbalanced samples as a limitation, not something to hide.
6. Keep the rule-based recommendation baseline as the production behavior until a data-driven alternative is evaluated offline and then in a consented, reviewed study. A predictive score alone does not demonstrate better learning.
7. Make model artifacts versioned with feature schema, training data fingerprint/provenance, split definition, dependency versions, seed, and evaluation report. Inference must fail closed to the established deterministic behavior.
8. Preserve deterministic Braille engines as the sole authority for encodings and answer validation.

## Data gaps and risks

- No verified live database URL or research export was available to audit; database sample size and usable learner event coverage are unknown.
- The API permits event rows to be submitted, but counts and data-quality distributions are unmeasured.
- The event schema lacks dot-level error details, stable item difficulty, prerequisites, exposure records, and structured hint interactions. It cannot support all requested feature analyses today.
- `skill_progress.mastery` is a smoothed historical summary created from attempts and is not independent ground truth.
- Existing teacher-assisted registration includes personal data. Minimize exported data, gate any research use by purpose-specific informed consent and applicable institutional/privacy review, pseudonymize, restrict access, and set retention/deletion procedures.
- No public dataset reviewed here is Braille learner practice data. Educational datasets can support method development, but not claims about Braille learning or Resonant outcomes.
- Intent datasets describe generic virtual assistant requests; none reviewed supplies Resonant's Braille-specific labels. Domain transfer should be framed as an external benchmark, not target-domain training evidence.
- Offline practice may remain only on devices. A server-only export would systematically omit unsynced activity unless the export design explicitly accounts for it.
- Language preference is stored, but this is not a sufficient/appropriate learner attribute for inferring ability or performance.

## Historical Phase 1 conclusion

The safe next step is a standalone, reproducible pipeline with documented provenance, schemas, and evaluation contracts. Start with intent classification using separate authored Resonant examples plus an external multilingual benchmark, clearly distinguishing these sources. Do not begin mastery prediction on current Resonant records until consent, event volume, feature definitions, target definition, and a leakage-safe chronological evaluation set are available. Braille error analytics require a future versioned event schema that records selected dots or error categories only when necessary and consented. No model is integrated into FastAPI in this phase.

## Follow-on phase results (2026-11-21)

- **Phase 2:** Added standalone normalized data contracts, provenance manifest validation, and learner-group split checks. Python 3.12 dependency versions are pinned in the AIML workspace.
- **Phase 3:** Trained TF-IDF + Logistic Regression and Linear SVM on the official English CLINC150 `data_full.json` splits. The 1,053,960-byte archive was checked; SHA-256 is `0d8ecc3e1edd7b25cabde0177544ce536ddf773844bc80ef1a75f36e7f030ea2`. Five exact text overlaps were removed from training only. Held-out Logistic Regression test accuracy/macro F1: 0.7660/0.8327; Linear SVM: 0.7649/0.8300. This is a generic English assistant benchmark, not evidence for Resonant intents. Hindi/Kannada model evaluation remains incomplete; MASSIVE is the researched external candidate but was not downloaded.
- **Phase 4:** Implemented point-in-time same-learner/same-skill features, an observed next-answer target, chronological splitting, Logistic Regression/Random Forest runners, class/baseline/calibration metrics and input privacy gates. No learner model was trained because `RESONANT_DATABASE_URL` is absent and no consented export exists. No predictive performance result exists.
- **Phase 5:** Implemented an offline model-vs-rule recommendation policy with language and prerequisite constraints and rule fallback, plus replay metrics. No policy comparison on learner records was possible. The backend rule baseline remains unchanged.
- **Phase 6:** Verified current tutor retrieval as keyword/lexical matching, not embeddings. A 13-query authored diagnostic compared it to char n-gram TF-IDF; both tied at P@1 0.923, Recall@5 1.0, MRR 0.962. This small set is diagnostic only.
- **Phase 7:** No FastAPI model integration was made. The external benchmark is not relevant enough for production tutor routing; the Resonant learner model lacks eligible data and evaluation. Deterministic Braille routes remain untouched.
- **AIML tests:** 29 passed. Backend and Flutter integration suites are run separately in final validation; this workspace did not change Flutter or FastAPI application code.

## Follow-on portfolio work (2026-11-21)

- Added an assistant-authored English Resonant Tutor taxonomy and an 80-row explicitly labelled demonstration set. Enforced five train, one validation and two test rows per class. Three baselines ran; test accuracy was 0.30 each. These numbers are a pipeline smoke test only, not evidence of learner-query generalization. No artifacts or backend integration were produced.
- Extended CLINC150 with a sigmoid-calibrated Linear SVM, validation-only OOS-threshold selection, top-label ECE/reliability bins, and selective risk/coverage. Test macro F1: Logistic Regression 0.8327, Linear SVM 0.8300, calibrated Linear SVM 0.8383. Test ECE where probabilities are available: 0.1935 and 0.0754 respectively. Raw LinearSVC margins are correctly reported as unavailable for probability-based metrics. All CLINC measurements are external benchmark results, not Resonant tutor evidence.
- Documented multilingual comparison design, script normalization cautions, knowledge-tracing choices/readiness, an unapplied privacy-aware additive schema proposal, and interview explanation guidance. No Hindi/Kannada experiment was run because no qualified local target data was available; MASSIVE remains an unacquired, generic-intent candidate.
- **Validation:** AIML suite 33 passed. Backend suite 91 passed with 39 subtests when supplied an ephemeral test-only `RESONANT_JWT_SECRET`; no production credentials or database were used. Flutter was not run because this phase changed only the isolated AIML workspace.

## Public educational outcome experiment (2026-11-22)

- Verified and retained locally the official corrected ASSISTments 2009-2010
  Skill Builder CSV (346,860 rows, 4,217 learners, 26,688 questions, 149
  non-null skills; SHA-256
  `162ef8d2d28bcbfea6591a282994062bd8d5eaa00636544292a0d268dca6e5da`).
  The raw file remains ignored and is not redistributed.
- Implemented schema/type/target validation, complete missingness/duplicate
  profiling, and point-in-time learner/same-skill history features. Learner and
  item identifiers are retained only for sequencing and the grouped split,
  never as model inputs.
- Used a fixed learner-grouped split (seed `20261122`) with 3,373 train and 844
  test learners, zero overlap. Earlier observed events for a held-out learner
  may inform that learner's later predictions; current and future outcomes do
  not.
- Measured Random Forest accuracy 0.6935, macro F1 0.6753, ROC-AUC 0.7529,
  PR-AUC 0.8365, and Brier score 0.2012 on 69,632 held-out rows. A prior
  baseline and Logistic Regression are reported beside it. These are genuine
  historical mathematics-outcome results, not Resonant/Braille mastery or
  learning-effectiveness results.
- Added an isolated trusted-artifact service and `POST /aiml/predict`. It
  accepts no learner ID/current outcome/raw answer, returns an explicit
  experimental scope and `learning_action: null`, and cannot affect the
  deterministic adaptive controller. Missing or invalid artifacts fail closed.
- Added measured reports/plots, ignored joblib output, tests, API/demo
  documentation, and a faculty walkthrough under
  `experiments/assistments_2009_2010/`.

## Governed Resonant integration update (2026-11-22)

- Added an authorization-manifest/HMAC PostgreSQL exporter that allowlists
  learner IDs and excludes direct identity, answers, teacher IDs, audio, and
  tutor transcripts. It was not run because no research authorization/export
  was supplied.
- Upgraded the mastery pipeline to the exact production
  `resonant-next-attempt-v2` schema and future-incorrect target, with a
  learner-grouped chronological holdout, configurable sample/learner/ROC-AUC/
  Brier/per-language gates, and mandatory human review before promotion.
- Added a trusted production inference service and migration 007 provenance
  tables. Missing, unqualified, schema-mismatched, unsupported-language, or
  failed artifacts return deterministic cold-start rather than fake output.
- Integrated the result into assessment decisions and mapping-backed adaptive
  questions. Flutter persists the offline action first, briefly synchronizes,
  then independently verifies the returned language, lesson, skill, answer,
  curriculum, and Braille cells.
- Teacher reporting distinguishes qualified advice from fallback and records
  later observed outcomes. Learners receive plain-language activity/mode text
  without probabilities.
- No production artifact was trained or promoted. The detailed current audit is
  `docs/resonant-ml-integration-audit.md`.
