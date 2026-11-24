# Resonant AIML data collection plan

**Status:** Design only; no collection or database changes performed.  
**Reviewed:** 2026-11-20.

## Principle

Use the least data needed to answer a pre-registered learning/reliability question. Participation and use for research/model training must be optional, purpose-specific, understandable, and revocable where practical. App availability and ordinary progress saving must not depend on consenting to research. Obtain applicable institutional/privacy review before collecting research data, especially from minors or disabled learners.

## Current data and limitations

See [PROJECT_AUDIT.md](../PROJECT_AUDIT.md). The server can store pseudonymous learner UUIDs, attempted skill/exercise, language, outcome, response duration, hint-used, attempt number and timestamp. It also stores quiz totals. It does not retain a submitted dot mask or structured mistake category. Teacher-assisted accounts can contain names, phone numbers, email, batch and teacher relationship; these must be kept outside any model-training table/export.

## Proposed minimum event contract for future data

Retain existing fields for application functionality. For research-eligible events only, add or version fields after review:

- `event_schema_version` and `client_version` for reproducibility.
- `event_time` and stable `session_id` generated without identity-bearing content.
- `item_version` and a curated `difficulty_level`/prerequisite reference owned by curriculum metadata, not inferred from the learner outcome.
- Optional structured `hint_count` or `hint_used` (avoid storing free-text tutor conversations).
- If dot-error analysis is approved, store the target cell and the submitted dot set or a minimal symmetric-difference error mask; avoid raw touch trajectories. Store only for exercises where the learner entered a Braille pattern, and document retention and accessibility implications.
- Separate opt-in `research_consent_version`, consent timestamp, withdrawal state and eligibility link. Keep this linkage in a restricted service; research exports use a rotating or project-specific pseudonym.

Do not add microphone recordings, transcripts, disability diagnosis, precise location, contact fields, or unnecessary demographics to the ML dataset. Speech transcripts may contain sensitive material and should not be logged into analytics by default.

## Target definitions to evaluate before collecting for modeling

1. **Intent classifier:** human-reviewed category for a tutor utterance and a separate in-scope/out-of-scope decision. Label guidelines must define ambiguous, multi-intent, mapping, and language-mixed cases. A classifier never decides Braille cell values.
2. **Next-attempt performance (exploratory):** whether a specified skill is answered correctly on the next eligible attempt after a prediction timestamp. The target is observed outcome, not `skill_progress.mastery`. For attempts with hints, report stratified performance or define eligibility prospectively; do not silently remove difficult events.
3. **Mastery:** do not claim ground-truth mastery from a single correctness event. If a mastery target is needed, define a prospective criterion with Braille educators (e.g. repeated independent performance across sessions) and validate that criterion. Treat it as an operational proxy, not latent knowledge truth.
4. **Recommendation quality:** first evaluate feasibility, prerequisite compliance, and offline replay relevance. Outcome prediction metrics do not establish that a recommendation improves learning. Any causal benefit claim requires an appropriately reviewed prospective study.

## Quality, access and governance

- Deduplicate on `submission_id`; reconcile offline pending events and server acknowledgements before building a snapshot.
- Validate timestamps, event outcome, language, skill/item identifiers, duration bounds, repeated attempts and missingness; report counts before dropping records.
- Exclude direct identifiers and all personal teacher-registration fields from features. Keep a separate access-controlled mapping only if necessary for withdrawal/deletion.
- Restrict raw events and exports to named maintainers; encrypt at rest/in transit; keep access logs; define deletion and retention periods before enrollment.
- Use a versioned consent notice that explains what events are collected, the purpose, retention, who can access them, whether models may be trained, and how withdrawal works. Obtain guardian consent/assent where required.
- Keep raw voice/audio disabled for analytics. Do not attach tutor chat text to attempt events.
- Publish only aggregate results with small-cell suppression and review for re-identification risk.

## Readiness gate before real-data experiments

Proceed only when all are true: (a) a reviewed purpose-specific consent process exists, (b) a database snapshot is authorized and pseudonymized, (c) the event schema and missingness are audited, (d) target and prediction time are frozen, (e) split is chronological and/or learner-grouped to match the claim, and (f) a baseline and analysis plan are recorded before viewing the final test results. No real learner model should be deployed from this plan alone.
