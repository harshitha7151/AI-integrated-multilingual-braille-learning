# Resonant AIML workspace

This is the isolated workspace for reproducible machine-learning and learning-analytics experiments. It does not replace Flutter, FastAPI, the deterministic Braille engines, or the current rule-based learner flow.

## Current status

- [Project audit](PROJECT_AUDIT.md): current architecture, data fields, real AI/ML inventory, gaps and risks.
- [Dataset research](data/DATASET_RESEARCH.md): primary-source candidates, scope, license/access notes and limitations. CLINC150 and the corrected ASSISTments 2009-2010 Skill Builder data were verified locally; raw archives remain ignored.
- [Data collection plan](data/DATA_COLLECTION_PLAN.md): minimum event additions
  and privacy/readiness gates. Migration 007 now implements the governed event,
  prediction, and adaptive-question foundation in code, but it was not applied
  to a live database and no learner export was performed.
- Phase 2 validation/provenance helpers and English CLINC150 intent baselines are implemented; the benchmark now includes calibrated-SVM, ECE, selective risk/coverage, and validation-selected OOS threshold analysis; see [experiment report](reports/intent_clinc150/REPORT.md).
- The separate [Resonant Tutor taxonomy](data/RESONANT_INTENT_TAXONOMY.md) and assistant-authored English dataset have a runnable smoke-test baseline (`python experiments/resonant_intents/run_authored_experiment.py`). These are not learner data or production routing.
- Multilingual intent and knowledge-tracing readiness are documented in [MULTILINGUAL_INTENT_PLAN.md](data/MULTILINGUAL_INTENT_PLAN.md) and [KNOWLEDGE_TRACING_RESEARCH.md](data/KNOWLEDGE_TRACING_RESEARCH.md); neither was represented as a measured multilingual or learner result.
- The earlier proposal at `schema_proposals/005_ml_event_context_PROPOSAL.sql`
  remains a research document. The application uses the separately reviewed
  additive `resonant_backend/migrations/007_resonant_ml_adaptive_foundation.sql`,
  which is also unverified against live PostgreSQL.
- Portfolio and interview notes: [PORTFOLIO_REPORT.md](reports/PORTFOLIO_REPORT.md), [INTERVIEW_GUIDE.md](reports/INTERVIEW_GUIDE.md).
- The governed next-attempt pipeline now matches the production
  `resonant-next-attempt-v2` feature schema, uses learner-grouped chronological
  evaluation, enforces configurable data/performance/per-language gates, and
  requires explicit human approval before promotion. There is no authorized
  Resonant learner dataset, trained artifact, or performance result.
- An authorization-manifest/HMAC PostgreSQL exporter is available under
  `experiments/mastery_prediction/`; it excludes direct identity, answers,
  teacher IDs, audio, and tutor transcripts. It was not run in this checkpoint.
- [Retrieval diagnostic](reports/retrieval/REPORT.md): lexical baseline and char TF-IDF tie on a small authored query set; this does not justify a production retrieval change.
- [ASSISTments educational outcome experiment](experiments/assistments_2009_2010/README.md): genuine public data, point-in-time history features, learner-grouped evaluation, fixed baselines, a trained Random Forest, measured reports, and an isolated experimental FastAPI prediction route. It is not a Braille or Resonant mastery model.

## Pipeline

`source/provenance → validation → EDA → point-in-time features → leakage-safe splits → baselines → model comparison → evaluation/error analysis → reviewed integration`

Planned module boundaries:

- `src/data/`: loaders, schema checks, provenance and split validation.
- `src/features/`: point-in-time feature builders; no identifiers as model features.
- `src/models/`: standalone experiment models and serialization.
- `src/evaluation/`: metrics, reports, calibration and plots.
- `src/recommendations/`: offline recommendation policies and constraint checks.
- `src/analysis/`: event/error summaries and visualizations.
- `experiments/`, `reports/`, `notebooks/`, `tests/`: reproducible runs, results, exploration and checks.
- `data/raw/`, `processed/`, `synthetic/`: local-only data areas. Do not commit learner exports or restricted raw corpora. Synthetic fixtures are for software mechanics only and must be labelled.

## Remaining work

1. Acquire and review an external multilingual intent corpus only after confirming source revision, locale coverage and license; collect separate, consented, reviewed Resonant examples before target-domain modeling.
2. Obtain purpose-specific authorization, use the allowlisted HMAC exporter,
   and run the leakage-safe future-attempt evaluation only when event and
   language coverage are sufficient.
3. Compare constrained, data-driven recommendation candidates against the current transparent rules after event volume and curriculum prerequisite data are adequate.
4. Expand Braille error-pattern analysis only after approved dot-error telemetry exists.

## Experiments completed so far

| Experiment | Status | Conclusion |
|---|---|---|
| English intent | Run on CLINC150 | Logistic Regression and Linear SVM results are in the report. Generic English assistant benchmark only. |
| Public educational outcome | Run on corrected ASSISTments 2009-2010 | Random Forest held-out accuracy 0.6935, macro F1 0.6753, ROC-AUC 0.7529 on 844 unseen learner identities. Mathematics first-attempt outcome prototype only; no learning action. |
| Hindi/Kannada intent | Not run | MASSIVE contains both languages but is not Braille-specific. No dataset download or model result yet. |
| Resonant future-attempt error | Production-schema pipeline and integration implemented; no eligible data | Exact point-in-time features, grouped chronological split, qualification/human-review gates, trusted inference, cold-start fallback, Flutter validation, and teacher provenance are implemented. No authorized export, trained artifact, or model metrics. |
| Recommendations | Offline comparator implemented | No real learner replay comparison. Existing rules remain operational. |
| Error analytics | Descriptive skill summary implemented | Current records support binary outcome summaries, not dot-level confusion analysis. |
| Retrieval | Small authored diagnostic run | Existing lexical retrieval ties char TF-IDF; no basis for replacement. |

## Reproduction environment

Python 3.12.3 was used. Exact dependency versions are pinned in `requirements.txt`. Intent seed: `20261120`; mastery pipeline seed: `20261121`.

From `aiml/`:

```powershell
python -m pip install -r requirements.txt
python -m pytest -q
python experiments/intent_clinc150/run_experiment.py
python experiments/retrieval/run_evaluation.py
python experiments/assistments_2009_2010/run_experiment.py
python experiments/mastery_prediction/export_authorized_events.py --help
python experiments/mastery_prediction/run_experiment.py --help
```

The mastery runner requires an authorized, pseudonymized CSV and a UTC cutoff; see [its experiment notes](experiments/mastery_prediction/README.md). Do not interpret the existing backend synthetic artifact as a result from this workspace.
