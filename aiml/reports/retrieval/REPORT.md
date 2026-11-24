# Retrieval diagnostic

The current knowledge base uses curated in-code documents and lexical/token ranking with hand-authored rules. It is not embedding-based RAG. This experiment compares it to a character n-gram TF-IDF ranker over the same documents.

The evaluation set contains 13 manually reviewed query/gold-document pairs in English, Hindi and Kannada. It is a small authored diagnostic set, not a broad or independently adjudicated benchmark.

| System | Queries | P@1 | Recall@5 | MRR |
|---|---:|---:|---:|---:|
| existing_keyword_retrieval | 13 | 0.923 | 1.000 | 0.962 |
| char_tfidf_experiment | 13 | 0.923 | 1.000 | 0.962 |

## Limitations

- Small, authored query set; metrics are diagnostic only and not a robust retrieval-quality claim.
- The current corpus is small and curated; there is no embedding/RAG model in this comparison.
- Braille mappings remain deterministically supplied by verified engines and are not produced by retrieval ranking.
