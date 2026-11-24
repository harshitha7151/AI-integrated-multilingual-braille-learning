# Resonant AIML engineering portfolio report

**Status date:** 2026-11-22  
**Scope:** Isolated `aiml/` research workspace plus one optional experimental FastAPI prediction endpoint. No Flutter integration, production migration, learner export, adaptive-policy replacement, or learner-facing model deployment is performed here.

## Executive summary

This workspace contains data validation/provenance helpers, text classification experiments, point-in-time answer-outcome feature construction, an offline recommendation comparator, and a retrieval diagnostic. CLINC150 and the corrected ASSISTments 2009-2010 Skill Builder release were verified locally. The ASSISTments experiment trains a genuine public-data Random Forest and exposes only an optional first-attempt correctness estimate; it is not a Braille or Resonant mastery model. A separate English Resonant Tutor taxonomy and assistant-authored examples exercise a project-specific baseline pipeline but are not representative learner data. Hindi/Kannada intent experimentation remains unrun. No consented Resonant learner model was trained, and deterministic learner decisions remain untouched.

The principle throughout is that **verified Braille engines remain the only authority for Braille cells**. Intent, retrieval, outcome, and recommendation experiments must not author encodings.

## Architecture and source-of-truth boundaries

| Capability | Actual implementation | Status and boundary |
|---|---|---|
| Braille encoding/validation | Deterministic English, Hindi and Kannada engines in the application/backend | Authoritative for the mappings each engine supports; not ML. |
| Tutor retrieval | Curated knowledge plus keyword/lexical matching | Rule-based retrieval; the tiny offline comparison did not justify a replacement. |
| Tutor prose | Local Ollama integration in backend | LLM-generated explanation, bounded by backend validation/evidence. Not a trained Resonant intent classifier. |
| Operational progress/mastery | Database event insertion and deterministic smoothed aggregates | Rule/aggregation behavior, not a validated mastery label. |
| Operational recommendation | Due-first/low-mastery deterministic selector | Transparent rule baseline. Its effect on learning has not been measured. |
| Synthetic adaptive model | Separate backend demonstration trained on generated data | ML software demonstration only; not connected to current recommendations and not evidence about learners. |
| Public educational outcome model | Corrected ASSISTments data; point-in-time features; learner-grouped Random Forest | Optional `/aiml/predict` research endpoint only. Returns no learning action and has no Flutter/adaptive-controller connection. |
| Other `aiml/` experiments | Standalone scikit-learn/pandas evaluation pipelines | Research only; no connection to learner progression. |

## Intent classification

### CLINC150 external benchmark

The experiment uses the source-provided English train/validation/test partitions, including the explicit OOS class. It removes exact-text overlaps from training only, keeps evaluation rows unchanged, fits TF-IDF inside each pipeline, and reports per-class performance and error samples. Models are Logistic Regression, Linear SVM, and sigmoid-calibrated Linear SVM. Evaluation includes accuracy, macro/weighted metrics, class reports, confusion matrices, argmax OOS performance, validation-selected OOS probability threshold on test, top-label ECE/reliability bins, and confidence-ranked selective risk at 50/80/100% coverage.

The downloaded UCI archive is 1,053,960 bytes with SHA-256 `0d8ecc3e1edd7b25cabde0177544ce536ddf773844bc80ef1a75f36e7f030ea2`. Its embedded license says CC BY 3.0 while the UCI catalog lists CC BY 4.0; check the archive's included terms and resolve discrepancy before redistribution. See the [CLINC experiment report](intent_clinc150/REPORT.md), [metrics](intent_clinc150/metrics.json), and [Logistic Regression confusion matrix](intent_clinc150/tfidf_logistic_regression_test_confusion_matrix.png).

| CLINC150 model | Test accuracy | Test macro F1 | Test top-label ECE | OOS test F1 (argmax) |
|---|---:|---:|---:|---:|
| TF-IDF Logistic Regression | 0.7660 | 0.8327 | 0.1935 | 0.2403 |
| TF-IDF Linear SVM (uncalibrated) | 0.7649 | 0.8300 | Not available | 0.1980 |
| TF-IDF sigmoid-calibrated Linear SVM | 0.7800 | 0.8383 | 0.0754 | 0.3380 |

The calibrated SVM has the strongest measured test values in this run, but this is only a small within-benchmark comparison. Top-label ECE uses ten fixed-width bins and is sample/bin dependent. The validation-selected OOS threshold test F1 is 0.4096 for Logistic Regression and 0.5220 for calibrated SVM; raw SVM margins are not treated as probabilities. Confusion, reliability, and risk/coverage plots are included in the CLINC report folder. No classifier is deployed.

These are generic English assistant intents, not Braille Tutor requests. OOS thresholds, ECE, and scores must not be used as production routing or safety guarantees.

### Resonant Tutor taxonomy and authored baseline

The proposed taxonomy contains `mapping_request`, `dot_pattern_explanation`, `lesson_explanation`, `practice_hint`, `mistake_explanation`, `navigation_help`, `progress_help`, `language_learning_question`, `general_braille_question`, and `out_of_scope`. Its safe-route proposal is documented in [the taxonomy](../data/RESONANT_INTENT_TAXONOMY.md).

The 80-row dataset is explicitly tagged `assistant_authored`, English-only, with five train, one validation and two test examples per category. It runs three text baselines and writes a report, but the tiny held-out counts and single-author source make all scores pipeline smoke-test numbers only. No model artifact is exported. Mapping-intent examples are labels only: they do not establish or encode any Braille pattern. The classifier is not integrated into the live `/ask` route.

The actual held-out smoke-test accuracy was 0.30 for Logistic Regression, 0.30 for raw Linear SVM, and 0.30 for calibrated Linear SVM (20 test rows total). This low number is recorded rather than hidden and should not guide product routing.

## Multilingual feasibility

No Hindi/Kannada classifier result was measured. MASSIVE is documented as an external candidate with Hindi and Kannada locale annotations and generic localized assistant intents, under CC BY 4.0 per its official notice. It is not Braille-domain data. Dataset size/revision should be checked before acquisition. See [the experiment plan](../data/MULTILINGUAL_INTENT_PLAN.md) and [dataset research](../data/DATASET_RESEARCH.md).

Planned comparison: per-language word TF-IDF, script-preserving character n-gram TF-IDF, and pooled multilingual variants on identical official locale splits. Preserve Indic combining marks; do not apply the English vectorizer's accent-stripping setting. Sentence embeddings remain a later candidate after license, runtime, model-size and evaluation review. Do not translate benchmark test rows to manufacture evaluation data.

## Public educational outcome prediction

The official corrected ASSISTments 2009-2010 Skill Builder CSV was verified at
346,860 rows from 4,217 learners. The binary `correct` field is the target.
Features use only strictly prior learner and same-skill counts, smoothed
success rates, hint-interaction rates, mean attempts/response time, plus
current question metadata. Current outcome-derived fields and all unrestricted
learner/question/class/teacher identifiers are excluded.

The seed-`20261122` learner-grouped split contains 277,228 training rows from
3,373 learners and 69,632 test rows from 844 disjoint learners. The fitted
Random Forest measured accuracy 0.6935, correct-class precision 0.7858, recall
0.7215, F1 0.7523, macro F1 0.6753, ROC-AUC 0.7529, PR-AUC 0.8365, and Brier
score 0.2012. Full reports, calibration/confusion/model-comparison plots, and
feature importance are in `assistments_2009_2010/`.

These are historical middle-school mathematics interaction results. They do
not establish Braille mastery, remediation need, learning gain, causal benefit,
or validity for blind learners, Resonant, Hindi, or Kannada. The optional API
is explicitly experimental and always returns `learning_action: null`.

## Mastery / knowledge tracing

Implemented code constructs point-in-time same-learner/same-skill features from prior correct/incorrect events and targets the next observed outcome. It excludes learner IDs from features and uses a strict chronological split. The runner supports Logistic Regression and Random Forest and checks input columns, sample/learner counts and label presence. There is no authorized, consented export or verified live database snapshot, so no learner model was fit and there are no learner metrics.

The target is next answer correctness, not latent mastery. `skill_progress.mastery` is derived from the same events and is not independent ground truth. BKT would require reviewed skill/item assignment and repeated per-skill sequences. DKT is not justified absent sufficient real histories and baseline evidence. Sources and readiness requirements are in [the knowledge-tracing note](../data/KNOWLEDGE_TRACING_RESEARCH.md).

## Event schema and privacy readiness

Current practice events include pseudonymous/account UUID, skill and exercise IDs, language, exercise type, outcome, response duration, hint-used, attempt number, submission UUID and timestamp. Gaps include session ID, event/client/item version, difficulty, structured expected/submitted responses, structured errors, and a versioned prerequisite map.

An additive **proposal only** is at [005_ml_event_context_PROPOSAL.sql](../schema_proposals/005_ml_event_context_PROPOSAL.sql). It is not an applied migration. Expected/submitted answers are proposed as minimal structured response values (e.g. ordered dot bitmasks), not audio, transcripts, raw free text, or touch trajectories. Research exports still require purpose-specific consent, access restriction, retention/deletion policy, pseudonymization, and review. Account UUIDs must be transformed to project-specific research pseudonyms before export; contact and teacher fields stay excluded.

## Recommendation evaluation

The current due-first/lowest-mastery rule remains operational. The offline comparator applies language and prerequisite constraints, ranks eligible candidates by predicted next-correct probability if a separately validated predictor is supplied, and falls back to rules when the model is missing/invalid/fails. Metrics cover recommendation coverage, feasibility, and observed next-skill match. These are descriptive replay measures; next-skill matching is not evidence of learning gain, and no real replay comparison is available. The existing comparator was not changed because no evidence justified a policy change.

## Experiments and measured results

| Experiment | Data | Measurement/status |
|---|---|---|
| CLINC150 baselines | Public English benchmark, official splits, train-only overlap filter | Logistic Regression: accuracy 0.7660 / macro F1 0.8327; Linear SVM: 0.7649 / 0.8300; sigmoid-calibrated SVM: 0.7800 / 0.8383. Test ECE: 0.1935 Logistic Regression, 0.0754 calibrated SVM. |
| Resonant Tutor text baselines | 80 assistant-authored English demo examples | Runs as code smoke test only; split sizes 5/1/2 per class are too small for quality claims. |
| Multilingual intent | None locally acquired | Not run. MASSIVE is a researched external candidate only. |
| Public educational outcome | Corrected ASSISTments 2009-2010 | Random Forest accuracy 0.6935 / macro F1 0.6753 / ROC-AUC 0.7529 on 844 held-out learner identities; not Braille-specific. |
| Resonant next-answer prediction | No eligible learner data | Pipeline only; no consented Resonant model result. |
| Recommendations | Unit fixtures only | Metric arithmetic and constraints tested; no replay effectiveness result. |
| Retrieval | 13 authored diagnostic queries | Lexical and char TF-IDF tied at P@1 0.923, Recall@5 1.0, MRR 0.962; not a generalizable comparison. |

## Validation, limitations, and remaining work

- Tests establish code behavior, not educational validity, learner benefit, accessibility on device, or multilingual voice quality.
- CLINC data is domain-mismatched and English-only; authored Tutor examples are not user data.
- No live PostgreSQL status or authorized learner records were inspected for training.
- Recommendation replay and retrieval sets are authored and small.
- The only backend integration is the optional experimental prediction route;
  no experiment changes the learner-facing app or deterministic decisions.
- No Flutter tests, Android phone behavior, TalkBack, or live backend/Ollama behavior is established by this AIML phase.

Next research steps: obtain reviewed taxonomy and bilingual annotation guidelines; acquire/licence-check MASSIVE only if the external benchmark serves the project; collect optional consented multilingual Tutor queries with community and educator review; implement/version the additive event schema only after approval; verify dataset counts and event quality; compare interpretable chronological baselines; then conduct prospective evaluation before any recommendations are changed.

For an interview walkthrough and likely questions, see [INTERVIEW_GUIDE.md](INTERVIEW_GUIDE.md).
