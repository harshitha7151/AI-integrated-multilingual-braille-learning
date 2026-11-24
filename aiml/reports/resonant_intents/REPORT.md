# Resonant Tutor authored-intent pipeline smoke test

**Not generalization evidence.** All examples are assistant-authored English demonstrations, not learner data. The fixed per-class split has only one validation and two test examples. No model artifact is produced and nothing is connected to FastAPI.

- Rows: 80 across 10 intents.
- Split: five train, one validation, two test per category; split assignment is designed to test code paths, not estimate out-of-sample quality.
- Label taxonomy: [RESONANT_INTENT_TAXONOMY.md](../../data/RESONANT_INTENT_TAXONOMY.md).

| Model | Validation accuracy | Validation macro F1 | Test accuracy | Test macro F1 |
|---|---:|---:|---:|---:|
| tfidf_logistic_regression | 0.400 | 0.367 | 0.300 | 0.253 |
| tfidf_linear_svm | 0.400 | 0.367 | 0.300 | 0.253 |
| tfidf_calibrated_linear_svm | 0.500 | 0.467 | 0.300 | 0.223 |
