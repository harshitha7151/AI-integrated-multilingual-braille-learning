# Adaptive learning model status

## Authoritative learner adaptation

The learner assessment loop now uses transparent deterministic rules on both
Flutter and the backend. It considers verified assessment accuracy, wrong
answers, attempts, hints, repeated dot-confusion evidence, prior assessment
history, current mastery, remediation cycles, and prerequisite completion.
Returned actions are limited to remediate, reinforce, advance, reassess, and
revise. Flutter persists them in a local inbox, validates the target against
the active curriculum, prevents duplicate remediation, caps automatic
remediation at two cycles, and synchronizes lifecycle outcomes when online.

These rules are intentionally not described as trained ML. A decision remains
`deterministic_rules` unless a qualified Resonant artifact actually contributes
advice. Evidence and version metadata let learners and teachers see why the
path changed.

`AdaptiveWordRecommender` is another deterministic learner-side rule. Each
word-writing submission is stored as its own local event with a stable UUID for
safe retry. The event includes engine-segmented per-character (or Bharati
conjunct) correctness observations. Online, the same event is inserted once
and each validated observation updates that learner's corresponding
`skill_progress` row in the same transaction. The authenticated teacher
profile reads those skill rows and the separate attempt history. Offline, the
local recommender consumes the recorded observations and ranks only words
already eligible in the current curriculum. Repeated errors increase priority;
subsequent correct observations reduce priority without deleting historical
error evidence. It preserves catalog order without evidence and cannot create
content, change Braille cells, alter the fixed mastery set, or unlock
prerequisites. This word ordering is not a trained model and is reported as
`deterministic_rules`.

The shared persistence helper estimates per-skill mastery with Bayesian
Knowledge Tracing (BKT): the configured prior is updated from the observed
correct/incorrect result using guess, slip, and learning probabilities, then
the learning transition is applied. Defaults are prior `0.20`, learning
`0.12`, guess `0.20`, and slip `0.10`; deployments can set
`RESONANT_BKT_PRIOR`, `RESONANT_BKT_LEARN`, `RESONANT_BKT_GUESS`, and
`RESONANT_BKT_SLIP`. The estimate is not measured accuracy: accuracy remains
`correct_count / attempts`. Incorrect answers are scheduled immediately;
successful reviews use 1, 3, 7, or 14-day intervals according to updated
mastery. These are transparent initial policy values, not empirically tuned
learning-effectiveness claims.

The existing `submitted_response` JSON field carries observations, so this
change requires no schema migration. Server synchronization and persistent
skill updates still require the configured PostgreSQL service; local durable
attempts and recommendations are available offline. Bharati observation units
follow the current forward encoder's greedy Unicode segmentation. This does not
assert complete Hindi or Kannada curriculum coverage.

### Adaptive candidate decision policy

After a persisted assessment, the backend ranks only skills present in that
assessment (the candidate pool is therefore curriculum- and language-bounded).
It computes expected information gain as binary entropy before an observation
minus expected posterior entropy under the configured BKT guess/slip model.
For previously practiced skills it also estimates forgetting risk with
`1 - mastery * 2^(-days_since_practice / 14)`; the 14-day half-life is an
initial heuristic, not a validated forgetting predictor. Due review and
recorded error-summary counts have priority, with information gain used to
differentiate eligible candidates. The persisted decision evidence contains
the candidate scores and selected skill.

Difficulty changes by at most one step in the 1–5 bank: a perfect first-attempt,
hint-free assessment can raise the next difficulty; low accuracy or repeated
errors can lower it; otherwise it stays stable. The next question is selected
from the verified skill/language/lesson bank, with deterministic answer cells
and options checked against the mapping registry. This generates a validated
next question, not an unconstrained multi-question exam.

The contextual policy is a small LinUCB re-ranker using persisted candidate
context snapshots (BKT mastery, information gain, forgetting estimate, due
status, and error count) and the actual completed `succeeded` outcome recorded
for prior recommendations. It activates only after five usable outcomes for
that learner; otherwise the deterministic policy remains in force. The reward
is completion success, which is a limited proxy and does not prove learning
gain. This policy has unit coverage but has not yet been evaluated on an
authorized live learner cohort. It is not deep reinforcement learning.

Braille response error categories come from deterministic expected/submitted
cell comparison (`learning_error_service.py`), not a trained classifier. This
supports missing/extra-dot, substitution, sequence, and invalid-input labels
only where the submitted structure provides enough evidence. The existing
offline AIML comparison suite remains experimental; its reported metrics are
not outcomes from Resonant learners.

## Governed Resonant prediction integration

The production prediction task is the probability of an incorrect **future**
eligible attempt for a learner and skill. `resonant_ml_service.py` constructs
the `resonant-next-attempt-v2` feature snapshot from strictly earlier valid
events. It includes prior attempt/error counts, recent and smoothed accuracy,
hint and response-time history, spacing, consecutive errors, dot-error rates,
revision/intervention history, question type, language, skill, and current
difficulty. It excludes the current outcome, future events, personal identity,
and raw tutor content.

The assessment service asks this prediction layer for advice before selecting
the next validated question. A qualified high-risk prediction can turn a
deterministically permitted advance into reinforcement or reduce the next
difficulty by one step. A qualified low-risk prediction can increase a valid
next exercise by one step. It cannot change verified correctness, mastery,
prerequisites, curriculum targets, Braille mappings, or the Flutter validator's
final decision.

Artifacts load only from trusted local directories and must match the exact
task/schema/class contract, declare supported languages, be trained from
authorized consented Resonant events, pass configured evaluation gates, and
carry explicit human approval. All other cases return
`cold_start_deterministic` with a reason. There is currently no authorized
Resonant dataset or qualified artifact, so operational decisions remain
deterministic fallback and no production ML performance is claimed.

Flutter stores its offline decision first, waits briefly for the backend,
reconciles by assessment submission ID, and revalidates any returned question
against language, curriculum, answer, skill, and authoritative Braille cells.
This preserves offline learning and prevents a model or LLM from inventing a
mapping or bypassing a prerequisite.

The controlled Ollama question path may rephrase only a verified base question;
invalid output becomes a deterministic validated fallback. The production
assessment path currently leaves that optional generation disabled.

See [resonant-ml-integration-audit.md](resonant-ml-integration-audit.md) for the
end-to-end audit and qualification limitations.

## Public-dataset educational outcome experiment

An isolated experiment now trains on the genuine corrected ASSISTments
2009-2010 Skill Builder dataset. It predicts historical first-attempt
correctness from strictly earlier learner/same-skill interactions and current
question metadata. A learner-grouped split with seed `20261122` produced
277,228 training rows (3,373 learners) and 69,632 test rows (844 different
learners), with zero learner overlap.

The held-out Random Forest measured accuracy 0.6935, correct-class precision
0.7858, correct-class recall 0.7215, correct-class F1 0.7523, macro F1 0.6753,
ROC-AUC 0.7529, PR-AUC 0.8365, and Brier score 0.2012. These are educational
mathematics interaction results, not Braille-learning or Resonant mastery
results. They do not establish learning gain or causal effectiveness.

The fitted pipeline is reproducible from the verified ignored raw CSV and is
stored locally at `aiml/artifacts/assistments_2009_rf_v1.joblib`. The optional
`POST /aiml/predict` endpoint returns only an explicitly experimental outcome
probability plus model metadata and `learning_action: null`. Missing or invalid
artifacts fail closed with HTTP 503. It cannot replace or override the
deterministic assessment, prerequisite, remediation, progression, offline, or
teacher-reporting paths.

See `aiml/experiments/assistments_2009_2010/README.md` and the measured files
under `aiml/reports/assistments_2009_2010/`.

## Synthetic model research

The backend now contains an isolated, reproducible ML demonstration for the
target “probability that a skill is answered correctly on the next attempt.”
The trainer creates synthetic histories only; it does not read learner data.

Run it from `resonant_backend` with the installed requirements:

```powershell
python train_adaptive_demo.py
```

The script groups the split by synthetic learner (75% train, 25% test), fits a
standardized logistic regression, compares it with a training-prevalence
baseline, and writes `artifacts/adaptive_v1.joblib` plus the report at
`docs/ml-synthetic-demo.json`. Features use prior accuracy, attempt count,
response time, hint rate, days since practice, smoothed mastery, and exercise
difficulty. The held-out set does not share learner IDs with training.

`adaptive_ml.predict_probability` checks the version and feature values and
returns the supplied rule-based probability when the model is missing or
invalid. The model is not connected to the production assessment decision
loop. The synthetic metrics are reproducibility evidence for the
training pipeline only; they are not evidence of real learning effectiveness
and must not drive real learner recommendations.

`recommendation_service.recommend_from_progress` is the deterministic
operational baseline: it selects a due skill first, then lower mastery, and
returns no recommendation for a learner with no answer history. It is unit
tested but not exposed as a learner-specific endpoint because authentication
and authorization are not yet present.

Before enabling qualified model advice for real learners, the project still
needs a purpose-authorized pseudonymized export, sufficient event and language
coverage, data-quality review, learner-grouped chronological evaluation,
configured qualification gates, and explicit human approval. The implemented
deterministic cold-start path remains operational until those conditions are
met.
