# ASSISTments 2009–2010 educational outcome experiment

This report contains measured results from the genuine corrected public Skill Builder dataset. It is not a Braille dataset and the model does not predict Braille mastery.

## Dataset

- Records loaded: **346,860**.
- Learners: **4,217**; questions: **26,688**; non-null skill IDs: **149**.
- Correct target rate: **0.6453**.
- Source SHA-256: `162ef8d2d28bcbfea6591a282994062bd8d5eaa00636544292a0d268dca6e5da`.
- Target: first-attempt correctness as documented by ASSISTments.
- Raw answer text and all learner/question/class/teacher identifiers are excluded from model features.
- Rows excluded: **0**; missing skill IDs mapped to an explicit category: **63,755**.

## Evaluation design

- Split: GroupShuffleSplit by learner_id, seed `20261122`.
- Train: **277,228 rows / 3,373 learners**.
- Test: **69,632 rows / 844 learners**.
- Learner overlap: **0**.
- A test learner's strictly earlier observed interactions may inform that learner's later point-in-time features, matching sequential deployment; no future or current outcome is used.
- Model configurations were fixed before test evaluation; the test set was not used for tuning.

## Actual held-out results

| Model | Accuracy | Precision (correct) | Recall (correct) | F1 (correct) | Macro F1 | ROC-AUC | PR-AUC | Brier |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Majority Baseline | 0.6449 | 0.6449 | 1.0000 | 0.7842 | 0.3921 | 0.5000 | 0.6449 | 0.2290 |
| Logistic Regression | 0.6787 | 0.7850 | 0.6911 | 0.7351 | 0.6635 | 0.7400 | 0.8253 | 0.2056 |
| Random Forest | 0.6935 | 0.7858 | 0.7215 | 0.7523 | 0.6753 | 0.7529 | 0.8365 | 0.2012 |

Random Forest confusion matrix (`[[true incorrect, false correct], [false incorrect, true correct]]`): `[[15889, 8834], [12506, 32403]]`.

## Random Forest feature importance

Impurity-based top features from the fitted pipeline:

- `numeric__skill_prior_success_rate`: 0.193152.
- `numeric__learner_prior_success_rate`: 0.146346.
- `numeric__learner_prior_hint_interaction_rate`: 0.119357.
- `numeric__skill_prior_hint_interaction_rate`: 0.100764.
- `numeric__learner_prior_mean_attempts`: 0.047276.

Artifact: `artifacts/assistments_2009_rf_v1.joblib` (17,257,841 bytes; SHA-256 `6ab5fea50d9991b16ddaca6e65d288a7dbbfa50568f191ccdbed6991f2481cfd`).

## Interpretation limits

- The model estimates an educational first-attempt answer outcome in historical middle-school mathematics interactions.
- It was not trained on Resonant records, Braille tasks, blind learners, Hindi, or Kannada learning data.
- Grouped evaluation measures generalization to held-out learner identities while allowing earlier observed interactions to inform later predictions.
- Impurity-based Random Forest feature importance is descriptive, can favor high-cardinality variables, and does not establish causality.
- The endpoint is experimental and cannot override Resonant's deterministic prerequisites, remediation caps, or progression rules.
