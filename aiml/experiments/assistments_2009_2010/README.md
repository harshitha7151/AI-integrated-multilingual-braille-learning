# ASSISTments 2009–2010 outcome experiment

This experiment predicts whether a historical ASSISTments Skill Builder
interaction was correct on the first attempt. It uses the genuine corrected
public dataset and is isolated from Resonant's deterministic learning actions.

## Source and conditions

- Dataset: ASSISTments 2009–2010 Skill Builder, corrected collapsed release.
- Official page: <https://sites.google.com/site/assistmentsdata/home/2009-2010-assistment-data/skill-builder-data-2009-2010>
- Corrected file: `skill_builder_data_corrected_collapsed.csv`.
- Citation requested by the source: Feng, M., Heffernan, N. T., & Koedinger,
  K. R. (2009). *Addressing the assessment challenge with an online system
  that tutors as it assesses*. User Modeling and User-Adapted Interaction,
  19, 243–266. <https://doi.org/10.1007/s11257-009-9063-7>
- The legacy dataset page describes the release as free to use and asks users
  to cite the exact dataset page. Current E-TRIALS responsible-use terms also
  prohibit commercial/de-anonymization misuse and require attribution/open
  research practices. This repository treats the data as research-only,
  excludes identity/contact fields, and does not redistribute the raw CSV.

Review the source page and terms before downloading:

```powershell
cd aiml
python experiments/assistments_2009_2010/download_dataset.py --acknowledge-use-conditions
```

The expected verified SHA-256 is
`162ef8d2d28bcbfea6591a282994062bd8d5eaa00636544292a0d268dca6e5da`.
The raw folder is Git-ignored.

The corrected CSV was verified locally on 2026-11-22: 64,412,812 bytes,
Latin-1 encoding, 346,860 rows and 31 columns. It contains 4,217 learners,
26,688 questions, and 149 non-null skill IDs. The target has 123,042
incorrect/help-used rows and 223,818 correct-first-attempt rows. There are no
full-row duplicates or duplicate `order_id` values. `skill_id` is missing in
63,755 rows; those rows are retained with an explicit missing-skill category.

## Research task and leakage boundary

The target is the source field `correct`: correct on the first attempt (`1`)
versus incorrect on the first attempt or help used (`0`). The model does not
predict remediation, latent mastery, readiness, Braille proficiency, or a
learning action.

Point-in-time features use only interactions with a smaller chronological
`order_id` for the same learner. Current attempts, hints, response time,
answer text, first action, outcome, and opportunity fields are excluded.
Learner, question, assignment, class, teacher, school, and template IDs are
not model inputs. `learner_id` is used only for history construction and the
grouped train/test split.

Historical features are prior learner and same-learner/same-skill interaction
counts, Laplace-smoothed correctness rates, hint-interaction rates, mean
attempts, and mean response time. Current question metadata is `skill_id`,
`tutor_mode`, `answer_type`, `original`, `position`, and `hint_total`.
Attempts below one and negative response times are treated as missing in later
history; attempts above 50 and response times above one hour are capped. No
row is excluded by these sanitization rules.

The test partition contains learner IDs absent from training. Earlier observed
test interactions may inform later predictions for that same test learner,
which simulates sequential use after a new learner has accumulated history.
No future interaction or current answer is used.

## Train and evaluate

```powershell
cd aiml
python experiments/assistments_2009_2010/run_experiment.py
```

The command trains a majority baseline, Logistic Regression, and the required
Random Forest with fixed configurations. It writes genuine held-out metrics,
classification reports, confusion matrices, calibration plots, model
comparison, Random Forest feature importance, experiment metadata, and a local
joblib artifact.

- Reports: `reports/assistments_2009_2010/`
- Model: `artifacts/assistments_2009_rf_v1.joblib`

Both raw data and generated model binaries remain ignored by Git. Reports and
source code are reviewable and the artifact is reproducible from the verified
raw file.

## Measured held-out results

Seed `20261122` produced 277,228 training rows from 3,373 learners and 69,632
test rows from 844 different learners. Learner overlap is zero. Model settings
were fixed before the test run; no test-set tuning was performed.

| Model | Accuracy | Precision (correct) | Recall (correct) | F1 (correct) | Macro F1 | ROC-AUC | PR-AUC | Brier |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Majority/prior | 0.6449 | 0.6449 | 1.0000 | 0.7842 | 0.3921 | 0.5000 | 0.6449 | 0.2290 |
| Logistic Regression | 0.6787 | 0.7850 | 0.6911 | 0.7351 | 0.6635 | 0.7400 | 0.8253 | 0.2056 |
| Random Forest | 0.6935 | 0.7858 | 0.7215 | 0.7523 | 0.6753 | 0.7529 | 0.8365 | 0.2012 |

The Random Forest confusion matrix is `[[15889, 8834], [12506, 32403]]` for
labels `[incorrect, correct]`. Its strongest impurity-based importances were
same-skill prior success rate (0.1932), learner prior success rate (0.1463),
learner prior hint-interaction rate (0.1194), and same-skill prior
hint-interaction rate (0.1008). These values are descriptive, can be biased by
feature cardinality, and do not establish causality.

The complete measured outputs are in `reports/assistments_2009_2010/`. The
ignored fitted artifact is `artifacts/assistments_2009_rf_v1.joblib`; its exact
size, hash, software versions, hyperparameters, split, and held-out metrics are
recorded in `experiment_metadata.json` and `metrics.json`.

## Experimental API

`POST /aiml/predict` accepts only the 16 documented aggregate/question
features. It accepts no learner ID, answer text, current outcome, or learning
action. It returns prediction, probability, model/dataset/experiment metadata,
an explicit experimental label, `learning_action: null`, and a scope warning.
Missing or invalid artifacts return HTTP 503.

From `resonant_backend/`, after setting the normal backend environment:

```powershell
python -m pip install -r requirements.txt
python -m uvicorn main:app --host 127.0.0.1 --port 8000
$body = Get-Content ..\aiml\reports\assistments_2009_2010\sample_prediction_request.json -Raw
Invoke-RestMethod -Uri http://127.0.0.1:8000/aiml/predict -Method Post -ContentType application/json -Body $body
```

The checked-in sample request is a feature-only held-out test example with no
learner identifier. `sample_prediction_response.json` is the genuine fitted
model response. The FastAPI handler reproduced it on 2026-11-22. The current
host could not complete an ASGI transport check because its Python asyncio
runtime hung even on a zero-work event loop; repeat the HTTP command above in
a normal backend runtime before a live demonstration or deployment.

## Resonant boundary

The FastAPI endpoint exposes only an optional experimental probability. It
returns an unavailable error when the artifact is absent. It does not accept
learner IDs or raw records, does not work offline, and cannot replace or
override Resonant's deterministic prerequisite, remediation, duplicate, or
progression safeguards.
