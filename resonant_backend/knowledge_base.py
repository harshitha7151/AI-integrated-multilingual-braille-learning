"""Small, traceable retrieval corpus backed by Resonant's verified subset.

This is intentionally not a complete UEB rulebook. Exact letter cells come
from the same basic-cell table used by verified_braille.py; wider claims are
excluded until documented fixtures exist.
"""
import re
from typing import Iterable

from verified_braille import _LETTERS, verified_single_letter

UEB_URL = "https://iceb.org/Rules%20of%20Unified%20English%20Braille%202024.pdf"
UEB_TITLE = "ICEB, Rules of Unified English Braille, Third Edition (2024)"


def _dots(cell: int) -> str:
    return ", ".join(str(bit + 1) for bit in range(6) if cell & (1 << bit)) or "no raised dots"


_DOCUMENTS: list[dict[str, object]] = [
    {
        "id": "english-six-dot-cell",
        "title": "Six-dot Braille cell and dot numbering",
        "content": (
            "A standard six-dot Braille cell has two columns and three positions. "
            "The left column is dots 1, 2, 3 from top to bottom. The right column "
            "is dots 4, 5, 6 from top to bottom. The dot identifiers do not change "
            "with the device screen layout."
        ),
        "terms": "cell layout columns rows positions upper lower left right numbering dots",
        "source": {"title": UEB_TITLE, "url": UEB_URL},
        "scope": "basic six-dot cell layout",
    },
]

for _letter, _cell in _LETTERS.items():
    _evidence = verified_single_letter(_letter)
    assert _evidence is not None
    _DOCUMENTS.append({
        "id": f"english-letter-{_letter}",
        "title": f"Uncontracted English Braille letter {_letter.upper()}",
        "content": (
            f"In Resonant's verified uncontracted English subset, letter "
            f"{_letter.upper()} uses {_dots(_cell)}. The engine cell value is {_cell}. "
            "This is a single-letter cell and does not describe contractions "
            "or a complete word encoding."
        ),
        "terms": f"letter {_letter} {_letter.upper()} alphabet uncontracted basic english braille pattern dots",
        "source": {"title": UEB_TITLE, "url": UEB_URL},
        "scope": "verified basic uncontracted English letter cell",
    })

_DOCUMENTS.extend([
    {
        "id": "resonant-english-scope",
        "title": "What Resonant currently supports in English Braille",
        "content": (
            "Resonant currently verifies uncontracted English letters and a limited "
            "set of indicators and punctuation. It does not implement full UEB, "
            "Grade 2 contractions, shortforms, or every context rule. Unsupported "
            "cases must be identified instead of guessed."
        ),
        "terms": "scope limitation supported unsupported full UEB grade 2 contractions shortforms context rules",
        "source": {"title": "Resonant verified engine scope", "url": "docs/braille-standards.md#english"},
        "scope": "implementation limitation, not a UEB rule",
    },
    {
        "id": "resonant-language-scope",
        "title": "Language support in the voice tutor",
        "content": (
            "The voice tutor currently accepts English only. Hindi and Kannada "
            "voice tutoring and backend Braille responses are not enabled or "
            "validated end to end. Do not infer speech support from a language "
            "selector or from a model's multilingual claims."
        ),
        "terms": "Hindi Kannada language multilingual speech voice recognition unsupported not enabled",
        "source": {"title": "Resonant project status", "url": "docs/project-status.md"},
        "scope": "current product capability",
    },
])

_BHARATI_URL = "https://cdnbbsr.s3waas.gov.in/s36ee69d3769e832ec77c9584e0b7ba112/uploads/2025/01/20250104954295710.pdf"
_DOCUMENTS.extend([
    {
        "id": "hindi-braille-intro", "language": "Hindi", "chapter": "Introduction",
        "topic": "braille basics", "level": "beginner",
        "objective": "Introduce Braille and the six-dot cell.",
        "title": "ब्रेल का परिचय और छह-बिंदु सेल",
        "content": "ब्रेल पढ़ने और लिखने की एक स्पर्श-आधारित लिपि है। एक मानक छह-बिंदु सेल में बाईं ओर ऊपर से नीचे बिंदु 1, 2, 3 और दाईं ओर बिंदु 4, 5, 6 होते हैं। यह सामान्य सेल संरचना है; अक्षरों के सटीक भारती ब्रेल रूप सत्यापित तालिका से लिए जाने चाहिए।",
        "terms": "ब्रेल क्या है परिचय छह बिंदु सेल बिंदु क्रम स्थान बायां दायां",
        "source": {"title": "NIEPVD, Standard Bharati Braille Codes (2025)", "url": _BHARATI_URL},
        "scope": "Hindi beginner introduction and standard cell layout; not a complete Hindi course",
    },
    {
        "id": "hindi-script-and-scope", "language": "Hindi", "chapter": "Characters",
        "topic": "vowels consonants", "level": "beginner",
        "objective": "Distinguish Hindi vowels and consonants and check supported characters.",
        "title": "हिंदी वर्ण और सत्यापित वर्णों की सीमा",
        "content": "Resonant के पाठ्यक्रम में हिंदी के स्वर और व्यंजन क्रमशः अभ्यास के लिए दिए गए हैं। केवल Bharati सत्यापित तालिका में मौजूद वर्णों का ही रूप बताया जा सकता है। मात्राओं, संयुक्ताक्षरों और शब्दों के नियमों को तभी निश्चित माना जाए जब संबंधित रूप तालिका में दर्ज हो।",
        "terms": "हिंदी स्वर व्यंजन मात्रा अक्षर वर्ण शब्द पढ़ना लिखना अभ्यास",
        "source": {"title": "Resonant Hindi curriculum and NIEPVD Bharati table (2025)", "url": _BHARATI_URL},
        "scope": "Curriculum coverage and verification boundary; not exhaustive orthography guidance",
    },
    {
        "id": "kannada-braille-intro", "language": "Kannada", "chapter": "Introduction",
        "topic": "braille basics", "level": "beginner",
        "objective": "Introduce Braille and the six-dot cell.",
        "title": "ಬ್ರೈಲ್ ಪರಿಚಯ ಮತ್ತು ಆರು ಚುಕ್ಕೆಗಳ ಕೋಶ",
        "content": "ಬ್ರೈಲ್ ಸ್ಪರ್ಶದ ಮೂಲಕ ಓದಲು ಮತ್ತು ಬರೆಯಲು ಬಳಸುವ ಲಿಪಿ. ಸಾಮಾನ್ಯ ಆರು-ಚುಕ್ಕೆ ಕೋಶದಲ್ಲಿ ಎಡಭಾಗದಲ್ಲಿ ಮೇಲಿನಿಂದ ಕೆಳಗೆ 1, 2, 3 ಮತ್ತು ಬಲಭಾಗದಲ್ಲಿ 4, 5, 6 ಚುಕ್ಕೆಗಳಿರುತ್ತವೆ. ಇದು ಕೋಶದ ಸಾಮಾನ್ಯ ವಿನ್ಯಾಸ; ಅಕ್ಷರಗಳ ನಿಖರ ಭಾರತಿ ಬ್ರೈಲ್ ರೂಪವನ್ನು ಪರಿಶೀಲಿತ ಪಟ್ಟಿಯಿಂದಲೇ ಪಡೆಯಬೇಕು.",
        "terms": "ಬ್ರೈಲ್ ಎಂದರೇನು ಪರಿಚಯ ಆರು ಚುಕ್ಕೆ ಕೋಶ ಚುಕ್ಕೆ ಕ್ರಮ ಸ್ಥಾನ ಎಡ ಬಲ",
        "source": {"title": "NIEPVD, Standard Bharati Braille Codes (2025)", "url": _BHARATI_URL},
        "scope": "Kannada beginner introduction and standard cell layout; not a complete Kannada course",
    },
    {
        "id": "kannada-script-and-scope", "language": "Kannada", "chapter": "Characters",
        "topic": "vowels consonants", "level": "beginner",
        "objective": "Distinguish Kannada vowels and consonants and check supported characters.",
        "title": "ಕನ್ನಡ ಸ್ವರಗಳು, ವ್ಯಂಜನಗಳು ಮತ್ತು ಪರಿಶೀಲಿತ ವ್ಯಾಪ್ತಿ",
        "content": "Resonant ಪಠ್ಯಕ್ರಮದಲ್ಲಿ ಕನ್ನಡ ಸ್ವರಗಳು ಮತ್ತು ವ್ಯಂಜನಗಳನ್ನು ಕ್ರಮವಾಗಿ ಅಭ್ಯಾಸ ಮಾಡಲಾಗುತ್ತದೆ. Bharati ಪರಿಶೀಲಿತ ಪಟ್ಟಿಯಲ್ಲಿ ಇರುವ ಅಕ್ಷರಗಳ ರೂಪವನ್ನಷ್ಟೇ ಖಚಿತವಾಗಿ ಹೇಳಬಹುದು. ಮಾತ್ರೆಗಳು, ಸಂಯುಕ್ತಾಕ್ಷರಗಳು ಮತ್ತು ಪದಗಳ ರೂಪಗಳನ್ನು ಪಟ್ಟಿಯಲ್ಲಿ ದಾಖಲಾಗಿರುವಷ್ಟರಲ್ಲೇ ದೃಢೀಕರಿಸಬೇಕು.",
        "terms": "ಕನ್ನಡ ಸ್ವರ ವ್ಯಂಜನ ಮಾತ್ರೆ ಅಕ್ಷರ ಪದ ಓದು ಬರಹ ಅಭ್ಯಾಸ",
        "source": {"title": "Resonant Kannada curriculum and NIEPVD Bharati table (2025)", "url": _BHARATI_URL},
        "scope": "Curriculum coverage and verification boundary; not exhaustive orthography guidance",
    },
])

# Existing course vocabulary, with cell sequences generated from the verified
# translation modules rather than duplicated mapping literals.
from bharati_verified import encode as _bharati_encode, bitmasks as _bharati_masks
from verified_braille import verified_uncontracted_word as _verified_word
_course_words = {
    "English": ["CAT", "BAT", "MAT", "SUN", "DOG", "HAT", "PEN"],
    "Hindi": ["अब", "कमल", "जल", "घर", "मन"],
    "Kannada": ["ಅಮ್ಮ", "ಕಮಲ", "ಮನೆ", "ಜಲ", "ನಮನ"],
}
_localized_word_notes = {
    "English": "The beginner course practises words as ordered sequences of separate uncontracted English cells.",
    "Hindi": "शुरुआती पाठ में शब्दों को क्रम से आने वाली सत्यापित भारती ब्रेल कोशिकाओं के रूप में पढ़ने और लिखने का अभ्यास किया जाता है।",
    "Kannada": "ಆರಂಭಿಕ ಪಾಠದಲ್ಲಿ ಪದಗಳನ್ನು ಕ್ರಮವಾಗಿ ಬರುವ ಪರಿಶೀಲಿತ ಭಾರತಿ ಬ್ರೈಲ್ ಕೋಶಗಳಾಗಿ ಓದುವ ಮತ್ತು ಬರೆಯುವ ಅಭ್ಯಾಸ ಮಾಡಲಾಗುತ್ತದೆ.",
}
for _language, _words in _course_words.items():
    for _word in _words:
        if _language == "English":
            _encoded_word = _verified_word(_word)
            _cells = _encoded_word["cells"] if _encoded_word else None
            _source_title, _source_url = UEB_TITLE, UEB_URL
        else:
            _dots = _bharati_encode(_word, _language)
            _cells = _bharati_masks(_dots) if _dots is not None else None
            _source_title, _source_url = "NIEPVD, Standard Bharati Braille Codes (2025)", _BHARATI_URL
        if _cells is not None:
            _DOCUMENTS.append({
                "id": f"{_language.lower()}-word-{_word}", "language": _language,
                "chapter": "Words", "topic": "reading writing practice",
                "level": "beginner", "objective": "Read and write an existing course word.",
                "title": f"{_language} verified beginner word practice",
                "content": f"{_localized_word_notes[_language]} Verified course example {_word} has cell sequence {_cells}.",
                "terms": f"{_word} word read reading write writing practice exercise cells sequence",
                "examples": [{"text": _word, "cells": _cells}],
                "practice_questions": [{"question": "Read this course word", "answer": _word, "cells": _cells}],
                "source": {"title": _source_title, "url": _source_url},
                "scope": "Existing beginner course example generated from verified engine",
            })

_TOKEN = re.compile(r"[a-z0-9]+", re.IGNORECASE)
_ALIASES = {
    "upper": "top capital",
    "uppercase": "capital letter",
    "lowercase": "small letter",
    "raised": "dot",
    "positions": "layout",
    "column": "left right",
    "columns": "left right",
    "contraction": "contractions",
    "ueb": "unified english braille",
    "language": "Hindi Kannada English",
}


def _tokens(text: str) -> set[str]:
    tokens = set(re.findall(r"[a-z0-9]+|[\u0900-\u097f]+|[\u0c80-\u0cff]+", text.lower()))
    expanded = set(tokens)
    for token in tokens:
        if token in _ALIASES:
            expanded.update(_TOKEN.findall(_ALIASES[token].lower()))
    return expanded


def _effective_query(question: str, history: Iterable[dict] = (), lesson_context: str = "") -> str:
    query = question.strip()
    # Resolve short follow-ups such as "why?" with the preceding learner turn.
    if len(_tokens(query)) <= 2:
        previous_user = next((
            turn.get("content", "") for turn in reversed(list(history))
            if turn.get("role") == "user" and isinstance(turn.get("content"), str)
        ), "")
        if previous_user:
            query = f"{previous_user} {query}"
    return f"{query} {lesson_context[:400]}"


def retrieve_evidence(
    question: str,
    *,
    history: Iterable[dict] = (),
    lesson_context: str = "",
    language: str = "English",
    learning_level: str = "beginner",
    limit: int = 4,
) -> list[dict[str, object]]:
    """Rank verified evidence by lexical overlap; no external service required."""
    effective_query = _effective_query(question, history, lesson_context)
    requested_course_words = [
        doc for doc in _DOCUMENTS
        if doc.get("language", "English") == language
        and doc.get("chapter") == "Words"
        and any(
            re.search(
                rf"(?<!\w){re.escape(str(example.get('text', '')).casefold())}(?!\w)",
                effective_query.casefold(),
            ) is not None
            for example in doc.get("examples", [])
            if isinstance(example, dict)
        )
    ]
    if requested_course_words:
        requested_course_words.sort(key=lambda doc: str(doc["id"]))
        return [dict(requested_course_words[0])]
    # Keep retrieval precise for common intents instead of returning adjacent
    # alphabet entries merely because their documents share generic terms.
    letter = requested_english_letter(effective_query)
    if letter and re.search(r"\b(braille|pattern|letter|dots?|cell|encode)\b", effective_query, re.I):
        exact = evidence_for_letter(letter)
        if exact:
            return exact[:limit]
    if re.search(r"\b(hindi|kannada|bharati|language|multilingual)\b", effective_query, re.I) and language == "English":
        return [dict(next(doc for doc in _DOCUMENTS if doc["id"] == "resonant-language-scope"))]
    language_documents = [
        doc for doc in _DOCUMENTS
        if doc.get("language", "English") == language
        and doc.get("level", learning_level) == learning_level
    ]
    if re.search(r"\b(ueb|contractions?|shortforms?|supported|support|scope)\b", effective_query, re.I) and language == "English":
        return [dict(next(doc for doc in _DOCUMENTS if doc["id"] == "resonant-english-scope"))]
    if re.search(r"\b(six[- ]dot|layout|numbering|columns?)\b", effective_query, re.I):
        if language == "English":
            return [dict(_DOCUMENTS[0])]
        intro_id = "hindi-braille-intro" if language == "Hindi" else "kannada-braille-intro"
        return [dict(next(doc for doc in _DOCUMENTS if doc["id"] == intro_id))]

    query_tokens = _tokens(effective_query)
    scored: list[tuple[int, dict[str, object]]] = []
    for document in language_documents:
        if str(document["id"]).startswith("english-letter-"):
            continue
        title_tokens = _tokens(str(document["title"]))
        term_tokens = _tokens(str(document["terms"]))
        content_tokens = _tokens(str(document["content"]))
        score = (
            4 * len(query_tokens & title_tokens)
            + 3 * len(query_tokens & term_tokens)
            + len(query_tokens & content_tokens)
        )
        if score:
            scored.append((score, document))
    scored.sort(key=lambda item: (-item[0], str(item[1]["id"])))
    return [dict(document) for score, document in scored[:limit] if score >= 2]


def source_references(evidence: Iterable[dict[str, object]]) -> list[dict[str, str]]:
    references: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for item in evidence:
        source = item.get("source")
        if not isinstance(source, dict):
            continue
        title, url = source.get("title"), source.get("url")
        if isinstance(title, str) and isinstance(url, str) and (title, url) not in seen:
            seen.add((title, url))
            references.append({"title": title, "url": url})
    return references


def format_evidence(evidence: Iterable[dict[str, object]]) -> str:
    blocks = []
    for item in evidence:
        source = item.get("source", {})
        source_title = source.get("title", "Resonant verified source") if isinstance(source, dict) else "Resonant verified source"
        blocks.append(
            f"[{item.get('id')}] {item.get('title')} (scope: {item.get('scope')}; source: {source_title})\n"
            f"{item.get('content')}"
        )
    return "\n\n".join(blocks)


def has_braille_scope(question: str) -> bool:
    # Do not treat every question written in Devanagari/Kannada as a Braille
    # question. Match explicit Braille/curriculum terms instead.
    english_term = re.search(
        r"\b(braille|six[- ]dot|dots?|cell|letters?|characters?|contractions?|ueb|bharati|hindi|kannada|pattern|transcrib|vowels?|consonants?)\b",
        question,
        re.IGNORECASE,
    )
    if english_term:
        return True
    hindi_terms = (
        "ब्रेल", "अक्षर", "वर्ण", "स्वर", "व्यंजन", "मात्रा", "बिंदु", "भारती"
    )
    kannada_terms = (
        "ಬ್ರೈಲ್", "ಅಕ್ಷರ", "ಸ್ವರ", "ವ್ಯಂಜನ", "ಮಾತ್ರೆ", "ಚುಕ್ಕೆ", "ಭಾರತಿ"
    )
    return any(term in question for term in (*hindi_terms, *kannada_terms))

def requested_english_letter(question: str) -> str | None:
    patterns = (
        r"\b(?:write|spell|encode)\s+(?:the\s+)?(?:letter\s+)?([^\W\d_])\s+in\s+(?:english\s+)?braille\b",
        r"\b(?:write|show me how to write|encode)\s+(?:the\s+)?(?:letter\s+)?([a-z])\b",
        r"\b(?:what are|show me)\s+the\s+dots\s+for\s+(?:the\s+)?(?:letter\s+)?([a-z])\b",
        r"\bhow\s+do\s+i\s+write\s+(?:the\s+)?(?:letter\s+)?([a-z])\s+in\s+(?:english\s+)?braille\b",
        r"\bletter\s+([a-z])\b",
        r"\b(?:braille|pattern)\s+(?:pattern\s+)?for\s+([a-z])\b",
        r"\bencode\s+([a-z])\b",
        r"(?<![a-zA-Z'’])([a-z])\s+in\s+braille\b",
    )
    for pattern in patterns:
        match = re.search(pattern, question, re.IGNORECASE)
        if match:
            return match.group(1)
    return None


def evidence_for_letter(letter: str) -> list[dict[str, object]]:
    key = f"english-letter-{letter.lower()}"
    return [dict(document) for document in _DOCUMENTS if document["id"] == key]
