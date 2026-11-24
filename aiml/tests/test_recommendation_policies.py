import pytest

from recommendations.policies import (
    eligible_candidates,
    evaluate_recommendation_replay,
    recommend_with_model_or_rules,
)


def test_eligibility_enforces_language_and_prerequisites():
    items = [
        {"skill_id": "a", "language": "English", "prerequisites": []},
        {"skill_id": "b", "language": "English", "prerequisites": ["a"]},
        {"skill_id": "c", "language": "Hindi", "prerequisites": []},
    ]
    assert [item["skill_id"] for item in eligible_candidates(
        items, language="English", mastered_skills=set()
    )] == ["a"]
    assert [item["skill_id"] for item in eligible_candidates(
        items, language="English", mastered_skills={"a"}
    )] == ["a", "b"]


def test_model_policy_only_ranks_eligible_candidates_and_is_labelled_experimental():
    result = recommend_with_model_or_rules(
        candidates=[
            {"skill_id": "basic", "language": "English", "prerequisites": []},
            {"skill_id": "advanced", "language": "English", "prerequisites": ["basic"]},
            {"skill_id": "hindi", "language": "Hindi", "prerequisites": []},
        ],
        language="English",
        mastered_skills=set(),
        skill_progress=[],
        predict_correct_probability=lambda skill: 0.1 if skill == "advanced" else 0.7,
        model_ready=True,
    )
    assert result["skill_id"] == "basic"
    assert result["source"] == "experimental_model"


def test_missing_or_invalid_model_falls_back_to_rules():
    candidates = [
        {"skill_id": "a", "language": "English", "prerequisites": []},
        {"skill_id": "b", "language": "English", "prerequisites": []},
    ]
    progress = [
        {"skill_id": "a", "attempts": 3, "mastery": 0.8, "next_review_at": None},
        {"skill_id": "b", "attempts": 3, "mastery": 0.2, "next_review_at": None},
    ]
    for predictor, ready in (
        (None, False),
        (lambda _: 1.5, True),
        (lambda _: (_ for _ in ()).throw(TimeoutError()), True),
    ):
        result = recommend_with_model_or_rules(
            candidates=candidates,
            language="English",
            mastered_skills=set(),
            skill_progress=progress,
            predict_correct_probability=predictor,
            model_ready=ready,
        )
        assert result["skill_id"] == "b"
        assert result["source"] == "rule_baseline"


def test_replay_metrics_report_feasibility_coverage_and_matching_only():
    summary = evaluate_recommendation_replay(
        [
            {"recommended_skill_id": "a", "observed_next_skill_id": "a", "recommendation_feasible": True},
            {"recommended_skill_id": "b", "observed_next_skill_id": "c", "recommendation_feasible": False},
            {"recommended_skill_id": None, "observed_next_skill_id": None, "recommendation_feasible": True},
        ]
    )
    assert summary["coverage"] == pytest.approx(2 / 3)
    assert summary["feasibility_rate"] == pytest.approx(1 / 2)
    assert summary["observed_next_skill_match_rate"] == pytest.approx(1 / 2)
    assert "does not establish learning gain" in summary["warning"]
