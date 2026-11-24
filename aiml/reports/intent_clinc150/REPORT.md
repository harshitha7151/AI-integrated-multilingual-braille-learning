# CLINC150 intent classification experiment

This is a public English virtual-assistant benchmark experiment. It is not Resonant user data and does not validate Braille tutoring intents.

- Dataset: CLINC150 `data_full.json`; 151 classes including explicit OOS.
- Archive SHA-256: `0d8ecc3e1edd7b25cabde0177544ce536ddf773844bc80ef1a75f36e7f030ea2`.
- Official rows: train 15100, validation 3100, test 5500.
- Exact text duplicates removed from training only: 5 rows; validation/test remained unchanged.
- Seed: 20261120; features: word TF-IDF uni/bi-grams; vectorizer fit inside each sklearn Pipeline on training text only.
- Models: Logistic Regression, Linear SVM, and sigmoid-calibrated Linear SVM (3-fold calibration internal to training only). Hyperparameters were fixed; test results were not used for selection.
- Confidence: top-label expected calibration error (ECE), fixed-bin reliability summaries, and accuracy/risk at confidence-ranked 50%, 80%, and 100% coverage. ECE depends on binning and is descriptive.
- OOS: reports argmax OOS metrics plus a validation-selected OOS probability threshold and held-out test precision/recall/F1. This benchmark threshold is not a production safety policy.
- License observed in downloaded archive: CC BY 3.0. The UCI catalog lists CC BY 4.0; check the authoritative terms before any redistribution.
- Full per-class reports, confusion matrices, error samples and metrics are in this report folder.

## Validation and test metrics

| Model | Split | Accuracy | Macro precision | Macro recall | Macro F1 | Weighted F1 |
|---|---|---:|---:|---:|---:|---:|
| tfidf_logistic_regression | validation | 0.8816 | 0.8921 | 0.8973 | 0.8899 | 0.8775 |
| tfidf_logistic_regression | test | 0.7660 | 0.7929 | 0.9003 | 0.8327 | 0.7282 |
| tfidf_linear_svm | validation | 0.8845 | 0.8926 | 0.9032 | 0.8928 | 0.8771 |
| tfidf_linear_svm | test | 0.7649 | 0.7825 | 0.9049 | 0.8300 | 0.7185 |
| tfidf_calibrated_linear_svm | validation | 0.8829 | 0.8936 | 0.8983 | 0.8911 | 0.8786 |
| tfidf_calibrated_linear_svm | test | 0.7800 | 0.7982 | 0.9027 | 0.8383 | 0.7501 |

## Confidence and OOS operating points

| Model | Test top-label ECE | Test accuracy at 50% coverage | OOS threshold selected on validation | Test OOS precision | Test OOS recall | Test OOS F1 |
|---|---:|---:|---:|---:|---:|---:|
| tfidf_logistic_regression | 0.1935 | 0.9753 | 0.0349 | 0.8293 | 0.2720 | 0.4096 |
| tfidf_linear_svm | N/A | N/A | N/A | N/A | N/A | N/A |
| tfidf_calibrated_linear_svm | 0.0754 | 0.9756 | 0.0481 | 0.7581 | 0.3980 | 0.5220 |

## Error analysis

- **tfidf_logistic_regression OOS:** precision 0.885, recall 0.139, F1 0.240.
  Validation-selected threshold test OOS metrics: precision 0.829, recall 0.272, F1 0.410 (threshold 0.0349).
- **tfidf_logistic_regression validation confidence:** top-label ECE 0.2403; selective risk bins are in metrics.json.
- **tfidf_logistic_regression test confidence:** top-label ECE 0.1935; selective risk bins are in metrics.json.
  Largest non-diagonal class confusions: __out_of_scope__ → calculator (38); __out_of_scope__ → recipe (34); __out_of_scope__ → who_made_you (30); __out_of_scope__ → w2 (30); __out_of_scope__ → restaurant_suggestion (23).
- **tfidf_linear_svm OOS:** precision 0.917, recall 0.111, F1 0.198.
  Probability-threshold OOS analysis unavailable for uncalibrated SVM margins.
- **tfidf_linear_svm validation confidence:** not available from uncalibrated margins.
- **tfidf_linear_svm test confidence:** not available from uncalibrated margins.
  Largest non-diagonal class confusions: __out_of_scope__ → who_made_you (29); __out_of_scope__ → calculator (27); __out_of_scope__ → restaurant_suggestion (25); __out_of_scope__ → w2 (21); __out_of_scope__ → recipe (21).
- **tfidf_calibrated_linear_svm OOS:** precision 0.920, recall 0.207, F1 0.338.
  Validation-selected threshold test OOS metrics: precision 0.758, recall 0.398, F1 0.522 (threshold 0.0481).
- **tfidf_calibrated_linear_svm validation confidence:** top-label ECE 0.1200; selective risk bins are in metrics.json.
- **tfidf_calibrated_linear_svm test confidence:** top-label ECE 0.0754; selective risk bins are in metrics.json.
  Largest non-diagonal class confusions: __out_of_scope__ → calculator (35); __out_of_scope__ → who_made_you (24); __out_of_scope__ → restaurant_suggestion (24); __out_of_scope__ → recipe (24); __out_of_scope__ → bill_balance (20).

## Interpretation limits

CLINC150 utterances were crowd-authored for generic assistant intents, are English-only, and are single-intent. Resonant's multilingual Braille questions require their own reviewed training/evaluation set. The OOS label is benchmark-specific; it must not become a policy for encoding Braille. Exact string overlap was found between the official training data and held-out partitions, so overlapping training rows were excluded before fitting; evaluation rows and official split membership were preserved. No deployed tutor behavior uses these models.
