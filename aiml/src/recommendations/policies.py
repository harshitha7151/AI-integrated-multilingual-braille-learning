"""Constraint-aware offline policies; never encodes or validates Braille."""

from collections.abc import Callable, Iterable, Mapping
from datetime import datetime, timezone


def _rule_baseline(skills: list[Mapping]) -> dict:
    """Standalone mirror of Resonant's due-first, then lowest-mastery rule."""
    candidates = [skill for skill in skills if int(skill.get("attempts", 0)) > 0]
    if not candidates:
        return {"skill_id": None, "reason": "no_practice_history", "source": "rule_baseline"}
    now = datetime.now(timezone.utc)

    def normalized_review(skill):
        review = skill.get("next_review_at")
        if review is not None and review.tzinfo is None:
            return review.replace(tzinfo=timezone.utc)
        return review

    def priority(skill):
        review = normalized_review(skill)
        overdue = review is not None and review <= now
        return (
            0 if overdue else 1,
            float(skill.get("mastery", 0.0)),
            review or now,
            skill["skill_id"],
        )

    selected = min(candidates, key=priority)
    due = normalized_review(selected) is not None and normalized_review(selected) <= now
    return {
        "skill_id": selected["skill_id"],
        "reason": "review_due" if due else "lowest_mastery",
        "source": "rule_baseline",
    }


def eligible_candidates(
    candidates: Iterable[Mapping],
    *,
    language: str,
    mastered_skills: set[str],
) -> list[dict]:
    """Filter to known-language candidates with all prerequisite skills met."""
    eligible = []
    for item in candidates:
        if item.get("language") != language:
            continue
        if not item.get("skill_id"):
            continue
        prerequisites = set(item.get("prerequisites", ()))
        if prerequisites.issubset(mastered_skills):
            eligible.append(dict(item))
    return eligible


def recommend_with_model_or_rules(
    *,
    candidates: Iterable[Mapping],
    language: str,
    mastered_skills: set[str],
    skill_progress: Iterable[Mapping],
    predict_correct_probability: Callable[[str], float] | None,
    model_ready: bool,
) -> dict:
    """Pick likely-to-need-practice eligible skill; fall back to rule baseline.

    The caller must supply probabilities from a separately evaluated model.
    This helper does not load or train models and should remain offline until
    adequate data and product evaluation are available.
    """
    eligible = eligible_candidates(
        candidates, language=language, mastered_skills=mastered_skills
    )
    if model_ready and predict_correct_probability is not None and eligible:
        scored = []
        try:
            for item in eligible:
                probability = float(predict_correct_probability(item["skill_id"]))
                if not 0.0 <= probability <= 1.0:
                    raise ValueError("model probability outside [0, 1]")
                scored.append((probability, item["skill_id"]))
        except Exception:
            scored.clear()
        if scored:
            probability, skill_id = min(scored)
            return {
                "skill_id": skill_id,
                "reason": "lowest_predicted_next_correct_probability",
                "source": "experimental_model",
                "predicted_correct_probability": probability,
            }

    allowed = {item["skill_id"] for item in eligible}
    progress = [row for row in skill_progress if row.get("skill_id") in allowed]
    baseline = _rule_baseline(progress)
    if baseline["skill_id"] is not None:
        baseline["reason"] = f"{baseline['reason']}_eligible_for_language_and_prerequisites"
    else:
        baseline["reason"] = "no_eligible_history_or_candidate"
    return baseline


def evaluate_recommendation_replay(cases: Iterable[Mapping]) -> dict:
    """Summarize feasibility and observed next-skill hit rate for offline replay."""
    cases = list(cases)
    if not cases:
        raise ValueError("at least one replay case is required")
    decisions = [case for case in cases if case.get("recommended_skill_id") is not None]
    feasible = [case for case in decisions if case.get("recommendation_feasible") is True]
    observed = [case for case in decisions if case.get("observed_next_skill_id")]
    hits = [
        case
        for case in observed
        if case["recommended_skill_id"] == case["observed_next_skill_id"]
    ]
    return {
        "cases": len(cases),
        "coverage": len(decisions) / len(cases),
        "feasibility_rate": len(feasible) / len(decisions) if decisions else None,
        "observed_next_skill_match_rate": len(hits) / len(observed) if observed else None,
        "observed_cases": len(observed),
        "warning": "Replay matching is a descriptive proxy; it does not establish learning gain or causal recommendation value.",
    }
