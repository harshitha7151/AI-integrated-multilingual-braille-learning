# Resonant AIML interview guide

## 60-second project summary

Resonant is a multilingual Braille learning app whose official Braille answer checking remains deterministic. I built a separate, reproducible AIML workspace to test possible support tools without putting experimental models into the learner app. I audited events and privacy limits, trained text baselines on an external English intent benchmark, created an explicitly assistant-authored Tutor taxonomy smoke test, built a leakage-aware next-answer pipeline that is waiting for eligible data, and compared retrieval/recommendation methods offline. The key engineering decision was to keep rules and verified Braille engines authoritative until real, reviewed evidence supports a change.

## Experiments and concepts to explain

### CLINC150 intent classification

- **Question:** How do classical text classifiers behave on a public English assistant-intent benchmark, including an explicit out-of-scope class?
- **Pipeline:** training-only word TF-IDF features in a scikit-learn pipeline; Logistic Regression, Linear SVM, and a sigmoid-calibrated Linear SVM. Official source splits are kept. Exact text overlap is removed from training only; evaluation partitions remain intact.
- **Concepts to review:** TF-IDF, sparse features, regularization, linear decision boundaries, class imbalance, macro vs weighted F1, confusion matrices, OOS precision/recall, probability calibration, expected calibration error, risk/coverage, and validation-only threshold selection.
- **Caveat:** CLINC's generic English queries are not Braille Tutor queries. Benchmark performance is not product suitability. Calibration and threshold results are benchmark-specific and not a deployment policy.

### Resonant Tutor authored taxonomy

- **Question:** Can the experiment pipeline consume the project's own proposed intent labels?
- **Pipeline:** assistant-authored English example CSV; fixed class-stratified 5/1/2 split; same text baselines; explicit provenance and report caveats.
- **Concepts to review:** annotation guidelines, label ambiguity, train/validation/test separation, representative sampling, inter-annotator agreement, domain shift, and why repeated authorship invalidates generalization claims.
- **Caveat:** It is a software smoke test, not learner data, not reviewed by educators/community, and not connected to FastAPI.

### Next-attempt learning prediction

- **Question:** Given prior history for one learner and skill, can a baseline estimate the next observed answer outcome?
- **Pipeline:** point-in-time same-skill features, learner ID retained only as split metadata, strict chronological split, Logistic Regression and Random Forest, class and calibration metrics, privacy-column rejection.
- **Concepts to review:** target leakage, point-in-time correctness, temporal validation, learner grouping, prevalence baseline, PR-AUC, Brier score, calibration, confounding by hints/practice selection, and the difference between observed answer correctness and latent mastery.
- **Caveat:** No eligible, authorized learner export exists here; there are no learner-performance results.

### Retrieval and recommendations

- Retrieval compared current curated lexical matching to character n-gram TF-IDF over a tiny assistant-authored diagnostic set. Equal results do not justify a production retrieval replacement.
- Recommendation code compares an experimental score with the rule-based due-first/low-mastery baseline under language/prerequisite constraints. Replay match rate and feasibility are descriptive; they do not demonstrate learning gain or causal effect.

## Likely interview questions

1. **Why macro F1?** It gives each class equal weight and exposes weak rare-class behavior; weighted F1 can hide it. Include per-class reports and support counts.
2. **Why calibrate an SVM?** Its raw margins are not probabilities. Sigmoid calibration maps them to probability-like outputs using training-fold held-out predictions. Calibration still needs independent evaluation and can vary by domain.
3. **What is leakage?** A feature, split, or preprocessing step carries information from a held-out/future target into training. Fit vectorizers only on train, filter overlap only from train, and construct each mastery feature from strictly earlier events.
4. **What does ECE mean?** It weights confidence-vs-accuracy gaps across bins. It is bin-sensitive and can look deceptively stable on small samples; inspect reliability bins and proper scores too.
5. **Why not train on the authored set?** It exercises code paths but does not represent the population or natural language diversity, especially with one author and tiny held-out counts.
6. **Why no DKT?** No eligible sequence dataset or adequate volume was verified. A complex model would add risk without evidence over interpretable baselines.
7. **Can the intent model write Braille?** No. It may at most suggest routing; deterministic verified engines alone provide and validate mappings.
8. **What changes before deployment?** Reviewed taxonomy/labels, consented representative multilingual queries, calibration and safety review, independent evaluation, latency/accessibility tests, monitored fallback, and explicit product approval.

## Honest resume framing

Describe CLINC as an external benchmark experiment, authored Tutor examples as pipeline demonstration, and mastery/recommendation modeling as implemented but not evaluated on eligible learner data. Do not describe synthetic or public benchmark scores as Resonant learner gains.
