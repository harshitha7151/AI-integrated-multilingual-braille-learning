# CLINC150 intent experiment

This experiment compares TF-IDF + Logistic Regression with TF-IDF + Linear SVM on the downloaded UCI `data_full.json` benchmark. It trains a separate `__out_of_scope__` class and uses the source-provided train, validation, and test partitions. The experiment is intentionally English-only and external to the Resonant tutor.

## Reproduce

From `aiml/`:

```powershell
python -m pip install -r requirements.txt
python experiments/intent_clinc150/run_experiment.py
python -m pytest -q
```

The archive is stored locally at `data/raw/clinc150.zip`, which is excluded from Git. Source: <https://archive.ics.uci.edu/static/public/570/clinc150.zip>. The local archive is 1,053,960 bytes, SHA-256 `0d8ecc3e1edd7b25cabde0177544ce536ddf773844bc80ef1a75f36e7f030ea2`. Its included LICENSE says CC BY 3.0; the UCI catalog currently lists CC BY 4.0. The included license is preserved and its discrepancy is called out in the report.

The original train/validation/test arrays are retained. Exact text duplicates that occur in training and either held-out split are removed from training only; validation and test rows remain unchanged. This creates a documented leakage-filtered benchmark variant, not a claim of an exact leaderboard reproduction.

## Outputs

- `reports/intent_clinc150/REPORT.md` and `metrics.json`
- Per-class validation/test reports, test confusion matrices as CSV/PNG, and small CSV error samples
- Local-only, ignored model artifacts in `artifacts/`

There are no Resonant labels in CLINC150. Do not integrate these models into `/ask` or use them to select/encode Braille patterns.
