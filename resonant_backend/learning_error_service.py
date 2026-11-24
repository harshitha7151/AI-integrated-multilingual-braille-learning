"""Deterministic Braille response differences and bounded error taxonomy."""

from __future__ import annotations


VALID_INPUT_STATUSES = frozenset(
    {"valid", "no_input", "invalid_input", "technical_failure"}
)
LEARNING_ERROR_CATEGORIES = frozenset(
    {
        "correct",
        "missing_dot",
        "extra_dot",
        "dot_substitution",
        "multiple_dot_error",
        "cell_order",
        "character_confusion",
        "no_input",
        "invalid_input",
        "technical_input_failure",
        "prerequisite_gap",
        "unknown",
    }
)


def response_cells(response: object) -> list[int] | None:
    if not isinstance(response, dict):
        return None
    value = response.get("cells")
    if not isinstance(value, list) or not all(
        isinstance(cell, int) and 0 <= cell <= 63 for cell in value
    ):
        return None
    return value


def _dots(cell: int) -> set[int]:
    return {dot for dot in range(1, 7) if cell & (1 << (dot - 1))}


def analyze_response(
    expected: dict,
    submitted: dict,
    *,
    input_status: str = "valid",
    technical_failure_code: str | None = None,
) -> dict:
    """Return exact dot differences without treating technical input as learning.

    `counts_for_learning` is false for missing, invalid or technically failed
    input.  Those records remain useful for reliability monitoring but must not
    lower mastery or trigger remediation.
    """
    if input_status not in VALID_INPUT_STATUSES:
        raise ValueError("assessment_input_status_invalid")
    if input_status == "technical_failure":
        if not technical_failure_code or len(technical_failure_code) > 80:
            raise ValueError("technical_failure_code_required")
        return {
            "category": "technical_input_failure",
            "counts_for_learning": False,
            "missing_dots": [],
            "extra_dots": [],
            "technical_failure_code": technical_failure_code,
        }
    if input_status == "no_input":
        return {
            "category": "no_input",
            "counts_for_learning": False,
            "missing_dots": [],
            "extra_dots": [],
            "technical_failure_code": None,
        }
    if input_status == "invalid_input":
        return {
            "category": "invalid_input",
            "counts_for_learning": False,
            "missing_dots": [],
            "extra_dots": [],
            "technical_failure_code": None,
        }

    expected_cells = response_cells(expected)
    submitted_cells = response_cells(submitted)
    if expected_cells is not None and submitted_cells is not None:
        if expected_cells == submitted_cells:
            return {
                "category": "correct",
                "counts_for_learning": True,
                "missing_dots": [],
                "extra_dots": [],
                "technical_failure_code": None,
            }
        if sorted(expected_cells) == sorted(submitted_cells):
            return {
                "category": "cell_order",
                "counts_for_learning": True,
                "missing_dots": [],
                "extra_dots": [],
                "technical_failure_code": None,
            }
        missing_details: list[dict] = []
        extra_details: list[dict] = []
        width = max(len(expected_cells), len(submitted_cells))
        for index in range(width):
            expected_cell = expected_cells[index] if index < len(expected_cells) else 0
            submitted_cell = submitted_cells[index] if index < len(submitted_cells) else 0
            missing = sorted(_dots(expected_cell) - _dots(submitted_cell))
            extra = sorted(_dots(submitted_cell) - _dots(expected_cell))
            if missing:
                missing_details.append({"cell_index": index, "dots": missing})
            if extra:
                extra_details.append({"cell_index": index, "dots": extra})
        missing_count = sum(len(item["dots"]) for item in missing_details)
        extra_count = sum(len(item["dots"]) for item in extra_details)
        if missing_count == 1 and extra_count == 0:
            category = "missing_dot"
        elif extra_count == 1 and missing_count == 0:
            category = "extra_dot"
        elif missing_count == 1 and extra_count == 1:
            category = "dot_substitution"
        elif missing_count + extra_count > 0:
            category = "multiple_dot_error"
        else:
            category = "unknown"
        return {
            "category": category,
            "counts_for_learning": True,
            "missing_dots": missing_details,
            "extra_dots": extra_details,
            "technical_failure_code": None,
        }

    expected_choice = expected.get("choice") or expected.get("text")
    submitted_choice = submitted.get("choice") or submitted.get("text")
    category = (
        "correct"
        if expected_choice is not None and expected_choice == submitted_choice
        else "character_confusion"
        if expected_choice is not None and submitted_choice is not None
        else "unknown"
    )
    return {
        "category": category,
        "counts_for_learning": True,
        "missing_dots": [],
        "extra_dots": [],
        "technical_failure_code": None,
    }

