"""Skill-level descriptive error summaries from approved practice events."""

import pandas as pd

from data.contracts import validate_practice_events


def summarize_skill_errors(events: pd.DataFrame) -> pd.DataFrame:
    """Summarize binary submitted-answer outcomes; this is not dot analysis."""
    checked = validate_practice_events(events)
    answers = checked.loc[checked["outcome"].isin({"correct", "incorrect"})].copy()
    if answers.empty:
        return pd.DataFrame(
            columns=[
                "language", "skill_id", "answered_attempts", "incorrect_count",
                "error_rate", "mean_response_time_ms",
            ]
        )
    answers["is_incorrect"] = answers["outcome"].eq("incorrect").astype(int)
    summary = (
        answers.groupby(["language", "skill_id"], as_index=False)
        .agg(
            answered_attempts=("submission_id", "count"),
            incorrect_count=("is_incorrect", "sum"),
            mean_response_time_ms=("response_time_ms", "mean"),
        )
    )
    summary["error_rate"] = summary["incorrect_count"] / summary["answered_attempts"]
    return summary.sort_values(
        ["language", "error_rate", "answered_attempts", "skill_id"],
        ascending=[True, False, False, True],
    ).reset_index(drop=True)
