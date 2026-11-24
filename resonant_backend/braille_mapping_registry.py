"""Versioned multilingual Braille mapping records derived from source engines.

This module never supplies an alternative encoder.  It exposes structured,
read-only records for validation, question provenance, dataset export and
consistency tests while the deterministic encoding modules remain authoritative.
"""

from __future__ import annotations

from collections import defaultdict
import unicodedata

from bharati_verified import bitmasks as bharati_bitmasks, supported_mappings
from verified_braille import supported_letter_mappings


REGISTRY_VERSION = "resonant-braille-mappings-v1"
ENGLISH_MAPPING_VERSION = "ueb-grade1-iceb-2024-subset-v1"
BHARATI_MAPPING_VERSION = "niepvd-bharati-2025-subset-v1"

ENGLISH_SOURCE = "ICEB Rules of Unified English Braille, third edition, 2024"
BHARATI_SOURCE = "NIEPVD Bharati Braille Unicode chart, 2025 verified subset"

HINDI_CURRICULUM_CHARACTERS = tuple(
    "अ आ इ ई उ ऊ ए ऐ ओ औ क ख ग घ च छ ज झ ट ठ ड ढ ण त थ द ध न प फ ब भ म य र ल व श ष स ह".split()
)
KANNADA_CURRICULUM_CHARACTERS = tuple(
    "ಅ ಆ ಇ ಈ ಉ ಊ ಎ ಏ ಐ ಒ ಓ ಔ ಕ ಖ ಗ ಘ ಚ ಛ ಜ ಝ ಟ ಠ ಡ ಢ ಣ ತ ಥ ದ ಧ ನ ಪ ಫ ಬ ಭ ಮ ಯ ರ ಲ ವ ಶ ಷ ಸ ಹ ಳ".split()
)


def _dot_positions(cell: int) -> list[int]:
    return [dot for dot in range(1, 7) if cell & (1 << (dot - 1))]


def _unicode_label(text: str) -> str:
    return " ".join(f"U+{ord(character):04X}" for character in text)


def _category(text: str) -> str:
    if len(text) > 1:
        return "sequence"
    category = unicodedata.category(text)
    if category.startswith("L"):
        return "letter"
    if category.startswith("M"):
        return "mark"
    if category.startswith("N"):
        return "number"
    if category.startswith("P"):
        return "punctuation"
    if text.isspace():
        return "space"
    return "symbol"


def _record(
    *,
    language: str,
    character: str,
    cells: list[int],
    mapping_version: str,
    source: str,
    lesson_id: str | None,
    skill_id: str | None,
    encoding_rule: str,
) -> dict:
    language_code = {"English": "en", "Hindi": "hi", "Kannada": "kn"}[language]
    mapping_key = "-".join(f"{ord(part):04x}" for part in character)
    return {
        "mapping_id": f"{language_code}:{mapping_key}",
        "registry_version": REGISTRY_VERSION,
        "language": language,
        "character": character,
        "unicode_character": _unicode_label(character),
        "braille_cells": cells,
        "dot_positions": [_dot_positions(cell) for cell in cells],
        "character_category": _category(character),
        "skill_id": skill_id,
        "lesson_id": lesson_id,
        "encoding_rule": encoding_rule,
        "rule_description": (
            "Forward deterministic Grade 1 mapping. The source encoder remains "
            "authoritative; this record is not a learned mapping."
        ),
        "mapping_source": source,
        "source_provenance": "Repository-verified deterministic engine table",
        "validation_status": "verified_subset",
        "mapping_version": mapping_version,
        "applicable_context": (
            "Validated forward encoding and exercise checking only; coverage is "
            "not a claim of complete contracted or reverse Braille support."
        ),
        "curriculum_reference": lesson_id,
    }


def mapping_records() -> list[dict]:
    """Build stable records directly from the authoritative engine tables."""
    records: list[dict] = []
    for character, cell in sorted(supported_letter_mappings().items()):
        records.append(
            _record(
                language="English",
                character=character,
                cells=[cell],
                mapping_version=ENGLISH_MAPPING_VERSION,
                source=ENGLISH_SOURCE,
                lesson_id=f"letter-{character}",
                skill_id=f"english-letter-{character}",
                encoding_rule="uncontracted_english_grade_1_letter",
            )
        )

    curriculum = {
        "Hindi": set(HINDI_CURRICULUM_CHARACTERS),
        "Kannada": set(KANNADA_CURRICULUM_CHARACTERS),
    }
    language_codes = {"Hindi": "hi", "Kannada": "kn"}
    for language in ("Hindi", "Kannada"):
        for character, dot_numbers in sorted(supported_mappings(language).items()):
            lesson_id = (
                f"{language_codes[language]}-char-{character}"
                if character in curriculum[language]
                else None
            )
            skill_id = (
                f"{language_codes[language]}-bharati-{character}"
                if lesson_id is not None
                else None
            )
            records.append(
                _record(
                    language=language,
                    character=character,
                    cells=bharati_bitmasks(dot_numbers),
                    mapping_version=BHARATI_MAPPING_VERSION,
                    source=BHARATI_SOURCE,
                    lesson_id=lesson_id,
                    skill_id=skill_id,
                    encoding_rule="bharati_forward_grade_1_verified_subset",
                )
            )
    validate_mapping_records(records)
    return records


def validate_mapping_records(records: list[dict]) -> None:
    """Reject duplicate IDs, conflicting mappings and malformed cell values."""
    seen_ids: set[str] = set()
    by_character: dict[tuple[str, str], set[tuple[int, ...]]] = defaultdict(set)
    for record in records:
        mapping_id = record.get("mapping_id")
        if not isinstance(mapping_id, str) or not mapping_id:
            raise ValueError("braille_mapping_id_required")
        if mapping_id in seen_ids:
            raise ValueError(f"duplicate_braille_mapping_id:{mapping_id}")
        seen_ids.add(mapping_id)
        language = record.get("language")
        character = record.get("character")
        cells = record.get("braille_cells")
        if language not in {"English", "Hindi", "Kannada"}:
            raise ValueError("braille_mapping_language_invalid")
        if not isinstance(character, str) or not character:
            raise ValueError("braille_mapping_character_required")
        if not isinstance(cells, list) or not cells or not all(
            isinstance(cell, int) and 0 <= cell <= 63 for cell in cells
        ):
            raise ValueError("braille_mapping_cells_invalid")
        by_character[(language, character)].add(tuple(cells))
    conflicts = [
        key for key, variants in by_character.items() if len(variants) > 1
    ]
    if conflicts:
        raise ValueError(f"conflicting_braille_mapping:{conflicts[0]}")


def mapping_for_skill(skill_id: str, language: str) -> dict | None:
    """Return a curriculum-associated record for a validated skill."""
    return next(
        (
            record
            for record in mapping_records()
            if record["skill_id"] == skill_id and record["language"] == language
        ),
        None,
    )

