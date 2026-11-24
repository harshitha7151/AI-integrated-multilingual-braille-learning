"""Validation for benchmark intent data and Resonant interaction events.

These checks fail early on malformed data. They do not infer labels, repair
events, or make a data source eligible for research use.
"""

from collections.abc import Iterable

import pandas as pd


INTENT_REQUIRED_COLUMNS = frozenset(
    {"text", "intent", "language", "split", "data_origin"}
)
PRACTICE_REQUIRED_COLUMNS = frozenset(
    {
        "submission_id",
        "learner_id",
        "skill_id",
        "language",
        "outcome",
        "response_time_ms",
        "hint_used",
        "created_at",
    }
)
SUPPORTED_LANGUAGES = frozenset({"English", "Hindi", "Kannada"})
INTENT_SPLITS = frozenset({"train", "validation", "test"})
PRACTICE_OUTCOMES = frozenset(
    {"correct", "incorrect", "cancelled", "accidental_touch", "timeout"}
)
PRACTICE_INPUT_STATUSES = frozenset(
    {"valid", "no_input", "invalid_input", "technical_failure"}
)


def _require_columns(frame: pd.DataFrame, required: Iterable[str], name: str) -> None:
    missing = sorted(set(required) - set(frame.columns))
    if missing:
        raise ValueError(f"{name} is missing required columns: {', '.join(missing)}")
    if frame.empty:
        raise ValueError(f"{name} must contain at least one row")


def _parse_bool(value):
    if pd.isna(value):
        return None
    if isinstance(value, bool):
        return value
    if value in (1, 0):
        return bool(value)
    return {"true": True, "false": False, "1": True, "0": False}.get(
        str(value).strip().lower()
    )


def validate_intent_examples(frame: pd.DataFrame) -> pd.DataFrame:
    """Validate the normalized intent-example contract and return a copy."""
    _require_columns(frame, INTENT_REQUIRED_COLUMNS, "intent examples")
    clean = frame.copy()
    for column in ("text", "intent", "language", "split", "data_origin"):
        clean[column] = clean[column].astype("string").str.strip()
        if clean[column].isna().any() or clean[column].eq("").any():
            raise ValueError(f"intent examples contain blank {column} values")
    invalid_splits = sorted(set(clean["split"]) - INTENT_SPLITS)
    if invalid_splits:
        raise ValueError(f"unsupported split labels: {', '.join(invalid_splits)}")
    if clean["intent"].nunique() < 2:
        raise ValueError("intent examples must contain at least two classes")
    if clean.duplicated(["text", "language", "split"]).any():
        raise ValueError("duplicate text/language rows exist within an official split")
    return clean


def validate_practice_events(frame: pd.DataFrame) -> pd.DataFrame:
    """Validate minimal event rows; preserve identifiers only as grouping keys."""
    _require_columns(frame, PRACTICE_REQUIRED_COLUMNS, "practice events")
    clean = frame.copy()
    for column in ("submission_id", "learner_id", "skill_id", "language", "outcome"):
        clean[column] = clean[column].astype("string").str.strip()
        if clean[column].isna().any() or clean[column].eq("").any():
            raise ValueError(f"practice events contain blank {column} values")

    if clean["submission_id"].duplicated().any():
        raise ValueError("practice events contain duplicate submission_id values")
    invalid_languages = sorted(set(clean["language"]) - SUPPORTED_LANGUAGES)
    if invalid_languages:
        raise ValueError(f"unsupported languages: {', '.join(invalid_languages)}")
    invalid_outcomes = sorted(set(clean["outcome"]) - PRACTICE_OUTCOMES)
    if invalid_outcomes:
        raise ValueError(f"unsupported outcomes: {', '.join(invalid_outcomes)}")

    response_ms = pd.to_numeric(clean["response_time_ms"], errors="coerce")
    if response_ms.isna().any() or response_ms.lt(0).any():
        raise ValueError("response_time_ms must be a nonnegative number")
    if response_ms.mod(1).ne(0).any():
        raise ValueError("response_time_ms must contain integer milliseconds")
    clean["response_time_ms"] = response_ms.astype("int64")

    parsed_hints = clean["hint_used"].map(_parse_bool)
    if parsed_hints.isna().any():
        raise ValueError("hint_used must contain boolean values")
    clean["hint_used"] = parsed_hints.astype(bool)

    timestamps = pd.to_datetime(clean["created_at"], errors="coerce", utc=True)
    if timestamps.isna().any():
        raise ValueError("created_at contains invalid timestamps")
    clean["created_at"] = timestamps

    if "input_status" not in clean:
        clean["input_status"] = "valid"
    clean["input_status"] = clean["input_status"].astype("string").str.strip()
    invalid_statuses = sorted(set(clean["input_status"]) - PRACTICE_INPUT_STATUSES)
    if invalid_statuses:
        raise ValueError(f"unsupported input statuses: {', '.join(invalid_statuses)}")

    if "counts_for_learning" not in clean:
        clean["counts_for_learning"] = True
    parsed_learning = clean["counts_for_learning"].map(_parse_bool)
    if parsed_learning.isna().any():
        raise ValueError("counts_for_learning must contain boolean values")
    clean["counts_for_learning"] = parsed_learning.astype(bool)

    if "difficulty" not in clean:
        clean["difficulty"] = 1
    difficulty = pd.to_numeric(clean["difficulty"], errors="coerce")
    if difficulty.isna().any() or difficulty.lt(1).any() or difficulty.gt(5).any():
        raise ValueError("difficulty must be an integer from 1 through 5")
    if difficulty.mod(1).ne(0).any():
        raise ValueError("difficulty must contain integer values")
    clean["difficulty"] = difficulty.astype("int64")

    if "question_type" not in clean:
        clean["question_type"] = clean.get(
            "exercise_type",
            pd.Series("letter_recognition", index=clean.index),
        )
    clean["question_type"] = (
        clean["question_type"].fillna("letter_recognition").astype("string").str.strip()
    )
    if clean["question_type"].eq("").any():
        raise ValueError("question_type cannot be blank")

    for column in ("error_category", "intervention_type", "assessment_type"):
        if column not in clean:
            clean[column] = ""
        clean[column] = clean[column].fillna("").astype("string").str.strip()
    return clean


def validate_no_group_overlap(
    train: pd.DataFrame, evaluation: pd.DataFrame, group_column: str
) -> None:
    """Raise when a learner/group appears on both sides of an evaluation split."""
    if group_column not in train or group_column not in evaluation:
        raise ValueError(f"both splits must contain {group_column}")
    if train[group_column].isna().any() or evaluation[group_column].isna().any():
        raise ValueError(f"{group_column} cannot be missing for grouped evaluation")
    overlap = set(train[group_column]) & set(evaluation[group_column])
    if overlap:
        raise ValueError(
            f"group leakage: {len(overlap)} {group_column} value(s) appear in both splits"
        )
