"""Compare existing lexical retrieval with an experimental char TF-IDF ranker."""

import json
from pathlib import Path
import sys

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT.parent / "resonant_backend"
sys.path.insert(0, str(BACKEND))
import knowledge_base


CASES = json.loads((Path(__file__).with_name("gold_queries.json")).read_text(encoding="utf-8"))


def _rank_tfidf(question, language, documents):
    scoped = [
        doc for doc in documents
        if doc.get("language", "English") == language
    ]
    text = [
        " ".join(
            str(doc.get(field, ""))
            for field in ("title", "content", "terms", "topic", "objective")
        )
        for doc in scoped
    ]
    vectorizer = TfidfVectorizer(
        analyzer="char",
        ngram_range=(2, 5),
        lowercase=True,
        sublinear_tf=True,
        min_df=1,
    )
    matrix = vectorizer.fit_transform(text)
    query = vectorizer.transform([question])
    scores = cosine_similarity(query, matrix).ravel()
    order = scores.argsort()[::-1]
    return [scoped[index]["id"] for index in order if scores[index] > 0]


def _rank_existing(question, language):
    return [
        item["id"]
        for item in knowledge_base.retrieve_evidence(question, language=language)
    ]


def _metrics(name, ranked_cases):
    reciprocal_ranks = []
    precision_at_1 = 0
    recall_at_5 = 0
    for case, ranked in ranked_cases:
        gold = case["gold_id"]
        try:
            rank = ranked.index(gold) + 1
        except ValueError:
            rank = None
        if rank == 1:
            precision_at_1 += 1
        if rank is not None and rank <= 5:
            recall_at_5 += 1
        reciprocal_ranks.append(1 / rank if rank is not None else 0.0)
    count = len(ranked_cases)
    return {
        "system": name,
        "queries": count,
        "precision_at_1": precision_at_1 / count if count else 0.0,
        "recall_at_5": recall_at_5 / count if count else 0.0,
        "mean_reciprocal_rank": sum(reciprocal_ranks) / count if count else 0.0,
        "per_query": [
            {
                "language": case["language"],
                "gold_id": case["gold_id"],
                "rank": ranked.index(case["gold_id"]) + 1 if case["gold_id"] in ranked else None,
                "top_ids": ranked[:5],
            }
            for case, ranked in ranked_cases
        ],
    }


def run():
    baseline, tfidf = [], []
    documents = knowledge_base._DOCUMENTS
    for case in CASES:
        baseline.append((case, _rank_existing(case["question"], case["language"])))
        tfidf.append((case, _rank_tfidf(case["question"], case["language"], documents)))
    report = {
        "corpus": "existing in-code curated knowledge_base._DOCUMENTS",
        "corpus_documents": len(documents),
        "test_set": "13 manually reviewed query/gold-document pairs, stored in gold_queries.json; not independent annotator agreement",
        "systems": [
            _metrics("existing_keyword_retrieval", baseline),
            _metrics("char_tfidf_experiment", tfidf),
        ],
        "limitations": [
            "Small, authored query set; metrics are diagnostic only and not a robust retrieval-quality claim.",
            "The current corpus is small and curated; there is no embedding/RAG model in this comparison.",
            "Braille mappings remain deterministically supplied by verified engines and are not produced by retrieval ranking.",
        ],
    }
    target = ROOT / "reports" / "retrieval"
    target.mkdir(parents=True, exist_ok=True)
    (target / "metrics.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    lines = [
        "# Retrieval diagnostic",
        "",
        "The current knowledge base uses curated in-code documents and lexical/token ranking with hand-authored rules. It is not embedding-based RAG. This experiment compares it to a character n-gram TF-IDF ranker over the same documents.",
        "",
        "The evaluation set contains 13 manually reviewed query/gold-document pairs in English, Hindi and Kannada. It is a small authored diagnostic set, not a broad or independently adjudicated benchmark.",
        "",
        "| System | Queries | P@1 | Recall@5 | MRR |",
        "|---|---:|---:|---:|---:|",
    ]
    for system in report["systems"]:
        lines.append(
            f"| {system['system']} | {system['queries']} | {system['precision_at_1']:.3f} | {system['recall_at_5']:.3f} | {system['mean_reciprocal_rank']:.3f} |"
        )
    lines += ["", "## Limitations", "", *[f"- {item}" for item in report["limitations"]], ""]
    (target / "REPORT.md").write_text("\n".join(lines), encoding="utf-8")
    return report


if __name__ == "__main__":
    result = run()
    print(json.dumps(
        [{key: system[key] for key in ("system", "queries", "precision_at_1", "recall_at_5", "mean_reciprocal_rank")} for system in result["systems"]],
        indent=2,
    ))
