# Tutor retrieval diagnostic

From `aiml/`, run:

```powershell
python experiments/retrieval/run_evaluation.py
```

It compares the existing backend lexical retrieval against a char n-gram TF-IDF ranking over the same curated documents using `gold_queries.json`. The set is small and manually assembled from repository coverage/tests, so its P@1, Recall@5 and MRR are diagnostic only. No content is sent to an LLM during this retrieval evaluation, and verified encoding routes are not changed.
