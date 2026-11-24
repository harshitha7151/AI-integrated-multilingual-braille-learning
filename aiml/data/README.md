# Data workspace

No raw dataset files are tracked. Keep downloaded data local unless its terms
expressly allow redistribution and the repository's data policy is updated.

- `raw/`: immutable source archives and provenance manifests; never commit private learner exports.
- `processed/`: derived data with reproducible transformation scripts and checksums.
- `synthetic/`: small, explicitly labelled fixtures for testing software mechanics only; not evidence about real learners.
- `manifests/`: checked-in provenance metadata, hashes and license notes without dataset contents.
- [Dataset research](DATASET_RESEARCH.md)
- [Collection and privacy plan](DATA_COLLECTION_PLAN.md)

The locally verified ASSISTments corrected CSV belongs under
`raw/assistments_2009_2010/`; `raw/*` is ignored. Its public provenance, hash,
observed schema, and experiment are documented without redistributing rows.
