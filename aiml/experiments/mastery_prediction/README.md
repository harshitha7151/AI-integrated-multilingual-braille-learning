# Resonant future-attempt error experiment contract

The pipeline and production integration contract are implemented, but no
learner prediction experiment has been trained or reported. There is no
authorized consented Resonant export or qualified artifact in this checkout.

## Task

Predict the observed incorrect outcome of a **future eligible attempt** for the
same learner and skill using only events strictly earlier than that attempt.
This is not latent mastery. `skill_progress.mastery` is a deterministic summary
and is neither the target nor a model feature.

Production task name: `probability_of_incorrect_future_attempt`  
Feature schema: `resonant-next-attempt-v2`

Features are language, skill ID, question type, prior attempt and incorrect
counts, smoothed and recent accuracy, prior hint rate, mean response time, days
since practice, consecutive incorrect count, missing/extra-dot rates, revision
count, prior intervention success rate, and current difficulty. Learner IDs,
prediction timestamps, and target submission IDs are split/trace metadata only.
Current outcomes, future outcomes, invalid/technical input, identity/contact
fields, answers, audio, and tutor transcripts are excluded.

## Authorized export

`export_authorized_events.py` is intentionally opt-in. It requires:

- an unexpired authorization manifest with an allowlisted learner set and
  purpose `resonant_next_attempt_research`;
- a matching `RESONANT_RESEARCH_EXPORT_APPROVAL` value;
- a minimum 32-byte `RESONANT_RESEARCH_PSEUDONYM_KEY` for HMAC pseudonyms;
- `RESONANT_DATABASE_URL`; and
- an output path under the ignored `aiml/data/processed/` directory.

It exports only the minimum event fields needed by the feature pipeline and
writes a provenance manifest with the snapshot hash. No export was performed
for this checkpoint.

## Split, models, and qualification

The runner uses a learner-grouped chronological holdout: training rows precede
the cutoff, test rows follow it, and test learner identities do not occur in
training. Class-weighted Logistic Regression and Random Forest share a
train-fitted preprocessing pipeline.

Evaluation includes precision, recall, F1, accuracy, ROC-AUC, PR-AUC, Brier
score, prevalence baseline, calibration, confusion matrices, learner/row counts,
and per-language eligibility. Configurable gates cover minimum train/test rows,
minimum train/test learners, both-class presence, minimum ROC-AUC, maximum Brier
score, and minimum per-language rows/learners.

Passing automated gates is not enough. `qualification_approved_by` must identify
an explicit human review, and artifact promotion occurs only when
`promote_qualified` is also requested. Supported languages are derived only from
language partitions that pass their gates.

The resulting artifact contract must match the backend trusted loader exactly:
artifact kind, prediction task, feature order/version, consented-data label,
incorrect-class label, qualification record, supported languages, model
version, and probabilistic model.

## Current result

No dataset was exported, no runner result exists, and no artifact was promoted.
The backend therefore uses explicit deterministic cold-start fallback. Unit
tests use small authored software fixtures only; their outputs are not model
performance evidence.

Use `--help` on both scripts for the full required arguments:

```powershell
python experiments/mastery_prediction/export_authorized_events.py --help
python experiments/mastery_prediction/run_experiment.py --help
```
