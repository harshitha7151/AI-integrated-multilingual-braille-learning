"""Loader and leakage guard for the official CLINC150 UCI full split."""

import json
from pathlib import Path
import zipfile

import pandas as pd

from data.contracts import validate_intent_examples


DATA_KEYS = {
    "train": ("train", "oos_train"),
    "validation": ("val", "oos_val"),
    "test": ("test", "oos_test"),
}


def load_clinc150_zip(path: str | Path) -> dict[str, pd.DataFrame]:
    """Read the dataset directly from the source zip without extracting files."""
    with zipfile.ZipFile(path) as archive:
        candidates = [name for name in archive.namelist() if name.endswith("/data_full.json")]
        if len(candidates) != 1:
            raise ValueError("archive must contain exactly one data_full.json")
        payload = json.loads(archive.read(candidates[0]))

    splits: dict[str, pd.DataFrame] = {}
    for split_name, (in_scope_key, oos_key) in DATA_KEYS.items():
        records = payload.get(in_scope_key)
        oos_records = payload.get(oos_key)
        if not isinstance(records, list) or not isinstance(oos_records, list):
            raise ValueError(f"archive is missing CLINC150 {split_name} data")
        rows = []
        for record in [*records, *oos_records]:
            if not isinstance(record, list) or len(record) != 2:
                raise ValueError(f"invalid CLINC150 row in {split_name}")
            text, intent = record
            rows.append(
                {
                    "text": text,
                    "intent": "__out_of_scope__" if intent == "oos" else intent,
                    "language": "English",
                    "split": split_name,
                    "data_origin": "CLINC150-authored/crowdsourced benchmark",
                }
            )
        splits[split_name] = validate_intent_examples(pd.DataFrame(rows))

    if splits["train"]["intent"].nunique() != 151:
        raise ValueError("CLINC150 full training split must contain 150 intents plus OOS")
    return splits


def remove_train_text_leakage(
    train: pd.DataFrame, validation: pd.DataFrame, test: pd.DataFrame
) -> tuple[pd.DataFrame, dict[str, int]]:
    """Remove training text duplicated in held-out splits; never alter eval rows."""
    normalize = lambda values: values.astype("string").str.casefold().str.strip()
    held_out = set(normalize(validation["text"])) | set(normalize(test["text"]))
    normalized_train = normalize(train["text"])
    overlap_mask = normalized_train.isin(held_out)
    stats = {
        "training_rows_removed": int(overlap_mask.sum()),
        "distinct_overlapping_texts": int(normalized_train[overlap_mask].nunique()),
        "validation_rows_unchanged": len(validation),
        "test_rows_unchanged": len(test),
    }
    filtered = train.loc[~overlap_mask].reset_index(drop=True)
    if set(normalize(filtered["text"])) & held_out:
        raise RuntimeError("training text overlap remains after leakage filter")
    return filtered, stats
