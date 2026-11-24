# Resonant Adaptive AIML Benchmark

Generated (UTC): 2026-11-24T08:24:08.705238+00:00
Database status: unavailable: RESONANT_DATABASE_URL is not configured
Database access: read-only transaction; no schema or row changes performed.

## Results

| Component | Status | N | Accuracy | Precision | Recall | F1 |
|---|---|---:|---:|---:|---:|---:|
| BKT next-response prediction | unavailable | 0 | N/A | N/A | N/A | N/A |
| Qualified Resonant ML next-response model | unavailable | 0 | N/A | N/A | N/A | N/A |
| Error classification | unavailable | 0 | N/A | N/A | N/A | N/A |
| Forgetting-risk estimation | unavailable | 0 | N/A | N/A | N/A | N/A |
| Information-gain selection | unavailable | 0 | N/A | N/A | N/A | N/A |
| LinUCB contextual bandit | unavailable | 0 | N/A | N/A | N/A | N/A |
| Adaptive difficulty | unavailable | 0 | N/A | N/A | N/A | N/A |
| Constraint-based assessment selection | unavailable | 0 | N/A | N/A | N/A | N/A |

## Methods and interpretation

- Positive class is an incorrect response. Binary predictions use a predeclared threshold of 0.5.
- Precision = TP/(TP+FP), recall = TP/(TP+FN), F1 = harmonic mean of precision and recall; accuracy = (TP+TN)/N. Undefined precision/recall edge cases use sklearn zero_division=0; read class support alongside the scores.
- BKT is evaluated prequentially: each correctness probability is computed before incorporating that response, with state isolated by learner and skill. The state is then updated using the existing configured BKT transition.
- BKT parameters: prior=0.2, learning=0.12, guess=0.2, slip=0.1.
- The qualified ML model is evaluated only on valid, resolved persisted predictions paired with observed outcomes. Its probability is thresholded at 0.5; fallback predictions are excluded.
- Mastery estimates are latent-state probabilities, not accuracy labels. This benchmark does not claim mastery probability calibration or mastery classification accuracy.
- Error labels are produced by deterministic response analysis; no independent human annotation is persisted, so classifier accuracy/precision/recall/F1 and its confusion matrix are unavailable.
- Information gain is a ranking signal. LinUCB uses observed binary rewards, but no logged propensities/randomized control or counterfactual outcomes support an unbiased policy-value comparison. Classification metrics are not applied to either ranking policy.
- Forgetting risk is an exponential-decay heuristic without an independent forgetting/recall label. Difficulty and constraint selection have no independent target labels. Their classification metrics are unavailable.
- The assessment selection component selects existing curriculum content subject to validation; this is not arbitrary assessment generation.

## Limitations

Results are descriptive for observed attempts/predictions only. They do not establish causal learning gains, generalization to new learners, or statistical significance. Class counts and metrics should be interpreted with each component's sample size and class distribution.

## Files

- `component_metrics.csv`: component-wise metrics, sample sizes, statuses, methods and unavailability explanations.
- `classification_report.csv`: per-class precision, recall, F1 and support for evaluable classifiers; explicit unavailable rows otherwise.
- `accuracy_precision_recall_f1.png`: chart of evaluable classifiers or an unavailable-state message.
- `confusion_matrices.png`: error-classification unavailable panel plus matrices for available outcome classifiers.
- `component_metrics_table.png`: visual metric/status table.
