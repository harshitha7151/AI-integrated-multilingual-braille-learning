"""Small backend verifier for one-letter examples from the Flutter engine.

Each cell is a six-bit mask: bit 0 means dot 1 and bit 5 means dot 6.
Sequences are ordered Braille cells, so uppercase letters include a capital
indicator cell before the letter cell.
"""
import re

_LETTERS = {
    "a": 1, "b": 3, "c": 9, "d": 25, "e": 17, "f": 11, "g": 27,
    "h": 19, "i": 10, "j": 26, "k": 5, "l": 7, "m": 13,
    "n": 29, "o": 21, "p": 15, "q": 31, "r": 23, "s": 14,
    "t": 30, "u": 37, "v": 39, "w": 58, "x": 45, "y": 61, "z": 53,
}
_PUNCTUATION = {
    ",": 2,
    ";": 6,
    ":": 18,
    ".": 50,
    "?": 22,
    "'": 4,
    "-": 36,
}


def supported_letter_mappings() -> dict[str, int]:
    """Return a defensive copy of the verified English Grade 1 subset.

    The mapping remains private and authoritative inside this module.  This
    read-only view is used to build versioned validation datasets and must not
    be mutated by callers.
    """
    return dict(_LETTERS)
_LANGUAGE_NAMES = {"english", "hindi", "kannada"}


def verified_single_letter(text):
    if not isinstance(text, str) or len(text) != 1 or text.lower() not in _LETTERS:
        return None
    cells = [_LETTERS[text.lower()]]
    if text.isupper():
        cells.insert(0, 32)
    return {"text": text, "cells": cells}


def verified_uncontracted_word(text):
    """Encode a simple A–Z word as separate, verified English cells.

    This supports uncontracted alphabetic words only. It intentionally does
    not claim UEB contractions, punctuation, numbers, or language-specific
    rules.
    """
    details = verified_uncontracted_word_details(text)
    return {"text": text, "cells": details["cells"]} if details else None


def verified_uncontracted_word_details(text):
    """Return encoder-ordered cells and verified per-letter teaching data."""
    if not isinstance(text, str) or not 1 < len(text) <= 32:
        return None
    if not re.fullmatch(r"[A-Za-z]+", text):
        return None

    cells = []
    letters = []
    index = 0
    while index < len(text):
        character = text[index]
        if character.isupper():
            end = index + 1
            while end < len(text) and text[end].isupper():
                end += 1
            indicators = [32, 32] if end - index > 1 else [32]
            cells.extend(indicators)
            capitalization = "capital_word" if len(indicators) == 2 else "capital_letter"
            for uppercase in text[index:end]:
                cell = _LETTERS[uppercase.lower()]
                cells.append(cell)
                letters.append({
                    "letter": uppercase,
                    "cells": [cell],
                    "dots": [bit + 1 for bit in range(6) if cell & (1 << bit)],
                    "capitalization": capitalization,
                })
            index = end
            continue

        cell = _LETTERS[character]
        cells.append(cell)
        letters.append({
            "letter": character,
            "cells": [cell],
            "dots": [bit + 1 for bit in range(6) if cell & (1 << bit)],
            "capitalization": "lowercase",
        })
        index += 1

    return {"text": text, "cells": cells, "letter_examples": letters}


def verified_uncontracted_text(text):
    """Encode bounded English Grade 1 text using the Flutter engine subset.

    This supports letters, spaces, capitalization, and the explicitly mapped
    punctuation above. It does not add contractions, numbers, or unsupported
    UEB context rules.
    """
    if not isinstance(text, str) or not 1 < len(text) <= 160:
        return None
    cells = []
    index = 0
    while index < len(text):
        character = text[index]
        if character == " ":
            cells.append(0)
            index += 1
            continue
        if character.isascii() and character.isupper():
            end = index + 1
            while (
                end < len(text)
                and text[end].isascii()
                and text[end].isupper()
            ):
                end += 1
            cells.extend((32, 32) if end - index > 1 else (32,))
            cells.extend(_LETTERS[item.lower()] for item in text[index:end])
            index = end
            continue
        if character in _LETTERS:
            cells.append(_LETTERS[character])
        elif character in _PUNCTUATION:
            cells.append(_PUNCTUATION[character])
        else:
            return None
        index += 1
    return {"text": text, "cells": cells}


def requested_english_word(question):
    """Return an explicit alphabetic word requested for Braille encoding."""
    if not isinstance(question, str):
        return None
    patterns = (
        r"\b(?:why\s+is|why\s+does)\s+(?:the\s+word\s+)?['\"]?([A-Za-z]+)['\"]?\s+(?:written|spelled|use|uses)\b",
        r"\bword\s+['\"]?([A-Za-z]+)['\"]?(?=$|\s|[?.!,;:])",
        r"\b(?:read|spell|write)\s+(?:the\s+)?['\"]?([A-Za-z]+)['\"]?(?=$|\s|[?.!,;:])",
        r"\b(?:braille|pattern)\s+(?:pattern\s+)?for\s+(?:the\s+)?(?:word\s+)?['\"]?([A-Za-z]+)['\"]?(?![A-Za-z0-9'’-])",
        r"\b(?:encode|transcribe)\s+(?:the\s+)?(?:word\s+)?['\"]?([A-Za-z]+)['\"]?(?![A-Za-z0-9'’-])",
        r"\b(?:write|spell)\s+(?:the\s+)?(?:word\s+)?['\"]?([A-Za-z]+)['\"]?\s+in\s+braille",
        r"\btranslate\s+(?:the\s+)?word\s+['\"]?([A-Za-z]+)['\"]?\s+to\s+braille",
        r"\b(?:show|give|tell me)\s+(?:the\s+)?(?:word\s+)?['\"]?([A-Za-z]+)['\"]?\s+in\s+braille",
    )
    for pattern in patterns:
        match = re.search(pattern, question, re.IGNORECASE)
        if match and len(match.group(1)) > 1:
            requested = match.group(1)
            if requested.lower() not in _LANGUAGE_NAMES:
                return requested
    return None


def is_pattern_question(question):
    text = question.lower()
    return bool(
        re.search(r"\b(?:write|spell|encode)\s+(?:the\s+)?(?:letter\s+)?[a-z]\b|\bhow\s+do\s+i\s+write\s+(?:the\s+)?(?:letter\s+)?[a-z]\s+in\s+(?:english\s+)?braille\b|\b(?:what are|show me)\s+the\s+dots\s+for\s+(?:the\s+)?(?:letter\s+)?[a-z]\b", text)
        or
        requested_english_word(question)
        or
        re.search(r"\bbraille\s+for\b|\bencode\b|\bpattern\s+for\b", text)
        or re.search(r"\b(?:which|what|show|give|tell me)\b.{0,80}\b(?:dots?|pattern|cells?)\b", text)
        or re.search(r"\b(?:write|spell)\b.{0,60}\bin braille\b", text)
    )


def contains_unverified_dot_claim(answer):
    return bool(re.search(r"\bdots?\s*(?:number\s*)?[1-6]\b", answer, re.IGNORECASE))


def verify_client_examples(examples):
    verified = []
    for example in examples:
        expected = (
            verified_single_letter(example.text)
            if len(example.text) == 1
            else verified_uncontracted_word(example.text)
        )
        if expected and expected["cells"] == example.cells:
            verified.append(expected)
    return verified
