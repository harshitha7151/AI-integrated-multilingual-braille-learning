# Recommendation comparison plan

The backend's current due-first/lowest-mastery recommendation remains the operational rule baseline. `src/recommendations/policies.py` adds an offline-only comparator that accepts a probability function from a separately evaluated model, filters candidates by requested language and prerequisite completion, and falls back to the rule baseline when the model is missing, invalid, or fails.

The current curriculum lacks a complete machine-readable prerequisite graph, and no consented learner event snapshot is available. Therefore no model-backed policy comparison or learning-effect claim has been run. Unit fixtures verify only language/prerequisite gating, fallback behavior and replay metric arithmetic.

Once data and prerequisite metadata are approved, compare rule and model policies on identical time-ordered replay cases. Report recommendation coverage, prerequisite feasibility, language correctness, review relevance, observed next-skill match and subsequent correctness as separate descriptive metrics. These are not causal learning-gain measures. A prospective study would be needed for that claim. Preserve cold-start as the current no-history rule response; never ask the ML policy to recommend a skill outside the learner's language/curriculum.
