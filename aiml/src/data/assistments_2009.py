"""Loader and validation for the corrected ASSISTments 2009-2010 data.

The source CSV uses a legacy single-byte encoding. Raw answer text is loaded
only so the source schema can be audited; it is never selected as a model
feature or written to generated reports.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

import pandas as pd


DATASET_ID = "assistments-2009-2010-skill-builder-corrected-collapsed"
DATASET_PAGE = (
    "https://sites.google.com/site/assistmentsdata/home/"
    "2009-2010-assistment-data/skill-builder-data-2009-2010"
)
DOWNLOAD_FILE_ID = "1NNXHFRxcArrU0ZJSb9BIL56vmUt5FhlE"
EXPECTED_SHA256 = "162ef8d2d28bcbfea6591a282994062bd8d5eaa00636544292a0d268dca6e5da"
DEFAULT_ENCODING = "latin1"

REQUIRED_COLUMNS = {
    "order_id",
    "user_id",
    "problem_id",
    "original",
    "correct",
    "attempt_count",
    "ms_first_response",
    "tutor_mode",
    "answer_type",
    "position",
    "type",
    "skill_id",
    "skill_name",
    "hint_count",
    "hint_total",
    "first_action",
    "opportunity",
}

NUMERIC_SOURCE_COLUMNS = {
    "order_id",
    "user_id",
    "problem_id",
    "original",
    "attempt_count",
    "ms_first_response",
    "position",
    "hint_count",
    "hint_total",
}

IDENTIFIER_COLUMNS = {
    "order_id",
    "assignment_id",
    "user_id",
    "assistment_id",
    "problem_id",
    "sequence_id",
    "student_class_id",
    "base_sequence_id",
    "teacher_id",
    "school_id",
    "template_id",
    "answer_id",
}

NEVER_MODEL_COLUMNS = IDENTIFIER_COLUMNS | {
    "correct",
    "attempt_count",
    "ms_first_response",
    "hint_count",
    "overlap_time",
    "answer_text",
    "first_action",
    "bottom_hint",
    "opportunity",
    "opportunity_original",
    "Unnamed: 0",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_assistments_2009(
    path: Path,
    *,
    encoding: str = DEFAULT_ENCODING,
    verify_known_hash: bool = False,
) -> pd.DataFrame:
    """Load the public corrected CSV and enforce its observed core contract."""

    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"ASSISTments CSV not found: {path}")
    if verify_known_hash:
        actual_hash = sha256_file(path)
        if actual_hash != EXPECTED_SHA256:
            raise ValueError(
                "ASSISTments file hash does not match the verified corrected release: "
                f"expected={EXPECTED_SHA256}, actual={actual_hash}"
            )

    data = pd.read_csv(path, encoding=encoding, low_memory=False)
    missing_columns = sorted(REQUIRED_COLUMNS - set(data.columns))
    if missing_columns:
        raise ValueError(
            "ASSISTments schema is missing required columns: "
            + ", ".join(missing_columns)
        )
    if data.empty:
        raise ValueError("ASSISTments dataset is empty")
    for column in sorted(NUMERIC_SOURCE_COLUMNS):
        converted = pd.to_numeric(data[column], errors="coerce")
        if (converted.isna() & data[column].notna()).any():
            raise ValueError(f"{column} must contain numeric values when present")
        data[column] = converted

    if data["order_id"].isna().any() or data["user_id"].isna().any():
        raise ValueError("order_id and user_id must be present on every row")
    if data["order_id"].duplicated().any():
        raise ValueError("corrected ASSISTments data must have unique order_id values")

    target = pd.to_numeric(data["correct"], errors="coerce")
    if target.isna().any() or not set(target.astype(int).unique()).issubset({0, 1}):
        raise ValueError("correct must be a complete binary 0/1 target")
    data = data.copy()
    data["correct"] = target.astype("int8")
    return data


def dataset_profile(data: pd.DataFrame, *, path: Path | None = None) -> dict[str, Any]:
    """Return JSON-safe observed statistics without exporting raw records."""

    target_counts = data["correct"].value_counts(dropna=False).sort_index()
    rows = int(len(data))
    missing_counts = {column: int(value) for column, value in data.isna().sum().items()}
    return {
        "dataset_id": DATASET_ID,
        "source_page": DATASET_PAGE,
        "file_name": Path(path).name if path else None,
        "file_bytes": int(Path(path).stat().st_size) if path else None,
        "sha256": sha256_file(Path(path)) if path else None,
        "encoding": DEFAULT_ENCODING,
        "rows_loaded": rows,
        "columns_loaded": int(len(data.columns)),
        "column_names": list(data.columns),
        "unique_learners": int(data["user_id"].nunique(dropna=True)),
        "unique_questions": int(data["problem_id"].nunique(dropna=True)),
        "unique_skills_non_null": int(data["skill_id"].nunique(dropna=True)),
        "target": {
            "column": "correct",
            "meaning": "correct on first attempt (1) versus incorrect/help used (0)",
            "counts": {
                str(int(key)): int(value) for key, value in target_counts.items()
            },
            "rates": {
                str(int(key)): float(value / rows)
                for key, value in target_counts.items()
            },
        },
        "missing_counts": missing_counts,
        "missing_rates": {
            column: float(value / rows) for column, value in missing_counts.items()
        },
        "full_row_duplicates": int(data.duplicated().sum()),
        "duplicate_order_ids": int(data["order_id"].duplicated().sum()),
        "model_identifiers_excluded": sorted(IDENTIFIER_COLUMNS),
        "columns_never_used_as_current_prediction_features": sorted(
            NEVER_MODEL_COLUMNS
        ),
    }
