# Mastery and knowledge-tracing readiness

## What exists in Resonant

The current pipeline creates a point-in-time row for an eligible correct/incorrect attempt after earlier attempts by the same learner and skill. It uses only earlier same-skill history for features and excludes learner/submission IDs from model features. The target is **the next observed answer outcome**, not latent mastery. The runner enforces a strict chronological boundary, both outcome classes and a minimum learner count, but no authorized learner export is available in this workspace, so no learner prediction was trained.

`skill_progress.mastery` is a smoothed operational summary derived from attempt outcomes. Using it as a target or alongside the same underlying outcomes risks circularity/leakage. It is not an independently validated ground-truth label.

## Methods and suitability

- **Logistic regression with performance/history features:** an interpretable first predictive baseline once point-in-time events exist. Compare with prevalence baseline; report PR-AUC, ROC-AUC when defined, Brier/log loss, calibration, subgroup/language counts, and temporal performance.
- **Bayesian Knowledge Tracing (BKT):** a per-skill latent-state model representing prior mastery and transitions, with guess/slip parameters. It requires a defensible skill assignment/Q-matrix and repeated response sequences for each knowledge component. Resonant's lesson/skill IDs may be a start, but prerequisite and item-skill mappings need curriculum review; the current smoothed progress number is not a BKT target. See [Corbett & Anderson (1995)](https://doi.org/10.1007/BF01099821).
- **Performance-factor/logistic models:** useful next baselines for practice count, successes/failures, spacing and item properties. Their features must be measured before the current response and avoid using current/future progress summaries.
- **Deep Knowledge Tracing (DKT):** recurrent neural sequence modeling can learn latent interaction representations, but adds data, compute, tuning and interpretability requirements. The project has no eligible real histories or evidence of sequence volume adequate to justify it. Revisit only after data volume, stable item/skill metadata, temporal/learner-held-out evaluation and simpler baselines are established. See [Piech et al. (NeurIPS 2015)](https://proceedings.neurips.cc/paper/2015/file/bac9162b47c56fc8a4d2a519803d51b3-Paper.pdf).

## Minimum prerequisites before fitting

1. Purpose-specific, informed, revocable research consent and applicable review; account creation consent does not imply model-training consent.
2. Authorized pseudonymized export with event volume, learner counts, language/skill/item coverage, missingness, sync duplicate and timestamp audits.
3. Frozen prediction question and point-in-time feature contract; target is next observed outcome unless an educator-reviewed independent mastery criterion is prospectively collected.
4. Stable skill/item identifiers, versioned item difficulty, vetted skill prerequisites or a Q-matrix, and exposure/attempt context.
5. Strict chronological evaluation, plus learner-held-out evaluation if making an unseen-learner claim; tune only on training/validation and preserve a final holdout.
6. Compare prevalence, current rule behavior and interpretable logistic baseline before BKT; assess probability calibration and uncertainty. No neural approach until it offers a defensible benefit at actual available volume.

## Public data limits

OULAD and EdNet can support generic learning-analytics workflow practice under their respective access and license terms; neither contains Braille practice and cannot establish Resonant mastery or tutor effectiveness. The project dataset review notes no download/schema validation for these candidates. A public benchmark must remain explicitly external and task-mismatched.
