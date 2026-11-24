# Faculty demonstration guide

This demonstration uses the genuine corrected ASSISTments 2009-2010 Skill
Builder dataset. It is an educational mathematics outcome experiment, not a
Braille mastery model and not a replacement for Resonant's deterministic
adaptive controller.

## 1. Verify source and local file

1. Open the official dataset page linked in `README.md` and show the requested
   citation and responsible-use notes.
2. From `aiml/`, run:

   ```powershell
   python experiments/assistments_2009_2010/download_dataset.py --acknowledge-use-conditions
   ```

3. Confirm the script prints SHA-256
   `162ef8d2d28bcbfea6591a282994062bd8d5eaa00636544292a0d268dca6e5da`.
   The ignored CSV must remain under
   `data/raw/assistments_2009_2010/` and must not be committed.
4. Show `reports/assistments_2009_2010/dataset_profile.json` for the observed
   schema, 346,860-row size, target distribution, missingness, and duplicate
   analysis.

## 2. Explain preprocessing and leakage prevention

1. Show `src/data/assistments_2009.py` for schema, hash, target, and numeric
   validation.
2. Show `src/features/assistments_history.py`. Emphasize the cumulative sums
   minus current values: each row uses only strictly earlier interactions.
3. Point out that learner/question/class/teacher identifiers, current outcome,
   current attempts, current hints, current response time, first action, and
   answer text are absent from `FEATURE_COLUMNS`.
4. Show the learner-grouped split in
   `src/evaluation/educational_outcome.py`: 3,373 training learners, 844 test
   learners, and zero overlap with seed `20261122`.

## 3. Reproduce training and evaluation

From `aiml/`:

```powershell
python -m pip install -r requirements.txt
python -m pytest -q tests/test_assistments_educational_outcome.py
python experiments/assistments_2009_2010/run_experiment.py
```

The last command trains the prior baseline, Logistic Regression, and Random
Forest. Show `REPORT.md`, `metrics.json`, confusion-matrix files, calibration
plots, `model_comparison.png`, and the feature-importance CSV/plot. The fitted
joblib stays ignored at `artifacts/assistments_2009_rf_v1.joblib`.

## 4. Demonstrate a real prediction

1. Show `sample_prediction_request.json`. It is one held-out test row's
   feature values with the learner identifier removed; it is not a Resonant
   learner record.
2. Start FastAPI from `resonant_backend/` after setting a development-only JWT
   secret and other normal backend configuration:

   ```powershell
   python -m uvicorn main:app --host 127.0.0.1 --port 8000
   ```

3. In another terminal from the repository root:

   ```powershell
   $body = Get-Content aiml\reports\assistments_2009_2010\sample_prediction_request.json -Raw
   Invoke-RestMethod -Uri http://127.0.0.1:8000/aiml/predict -Method Post -ContentType application/json -Body $body
   ```

4. Compare the response with `sample_prediction_response.json`. The measured
   probability is produced by the saved Random Forest, not hardcoded.

## 5. Show the safety boundary

Open `resonant_backend/educational_ml_service.py` and `main.py`'s
`/aiml/predict` route. The endpoint returns `learning_action: null` and labels
the result experimental. Then show Flutter's `AdaptiveDecisionController` and
backend `assessment_service.py`: prerequisites, remediation limits, duplicate
suppression, progression, offline decisions, and teacher reporting remain
deterministic and unchanged by this model.

## 6. State limitations verbatim

- The data is historical middle-school mathematics interaction data, not
  Braille data.
- The model was not trained on Resonant learners, blind learners, Hindi, or
  Kannada learning records.
- It estimates first-attempt answer correctness, not latent mastery,
  remediation need, readiness, or learning gain.
- Held-out predictive performance does not prove educational effectiveness or
  causal benefit.
- No live Resonant learner study or Braille-learner validation has occurred.
