import pandas as pd
import pytest

from data.contracts import (
    validate_intent_examples,
    validate_no_group_overlap,
    validate_practice_events,
)


def test_intent_contract_preserves_authored_origin_and_official_splits():
    frame = pd.DataFrame(
        [
            ["How do I write A?", "mapping", "English", "train", "authored"],
            ["Explain six dots", "concept", "English", "test", "massive"],
        ],
        columns=["text", "intent", "language", "split", "data_origin"],
    )
    checked = validate_intent_examples(frame)
    assert checked["data_origin"].tolist() == ["authored", "massive"]


@pytest.mark.parametrize(
    "field,value", [("intent", ""), ("split", "holdout"), ("text", "How do I write A?")]
)
def test_intent_contract_rejects_blank_invalid_and_duplicate_rows(field, value):
    frame = pd.DataFrame(
        [
            {"text": "How do I write A?", "intent": "mapping", "language": "English", "split": "train", "data_origin": "authored"},
            {"text": "Explain six dots", "intent": "concept", "language": "English", "split": "test", "data_origin": "authored"},
        ]
    )
    if field == "text" and value:
        frame.loc[1, "text"] = value
        frame.loc[1, "split"] = "train"
    else:
        frame.loc[0, field] = value
    with pytest.raises(ValueError):
        validate_intent_examples(frame)


def test_practice_contract_checks_events_without_treating_mastery_as_label():
    frame = pd.DataFrame(
        [{
            "submission_id": "event-1",
            "learner_id": "learner-pseudo-1",
            "skill_id": "letter-a",
            "language": "English",
            "outcome": "correct",
            "response_time_ms": 800,
            "hint_used": False,
            "created_at": "2026-11-20T12:00:00Z",
        }]
    )
    checked = validate_practice_events(frame)
    assert checked.iloc[0]["response_time_ms"] == 800
    assert str(checked.iloc[0]["created_at"].tz) == "UTC"


@pytest.mark.parametrize(
    "updates",
    [
        {"submission_id": ""},
        {"language": "Unknown"},
        {"outcome": "maybe"},
        {"response_time_ms": -1},
        {"created_at": "not-a-time"},
    ],
)
def test_practice_contract_rejects_invalid_events(updates):
    row = {
        "submission_id": "event-1",
        "learner_id": "learner-1",
        "skill_id": "a",
        "language": "English",
        "outcome": "correct",
        "response_time_ms": 100,
        "hint_used": False,
        "created_at": "2026-11-20T12:00:00Z",
    }
    row.update(updates)
    with pytest.raises(ValueError):
        validate_practice_events(pd.DataFrame([row]))


def test_group_leakage_checker_rejects_overlap():
    with pytest.raises(ValueError, match="group leakage"):
        validate_no_group_overlap(
            pd.DataFrame({"learner_id": ["a", "b"]}),
            pd.DataFrame({"learner_id": ["b", "c"]}),
            "learner_id",
        )
