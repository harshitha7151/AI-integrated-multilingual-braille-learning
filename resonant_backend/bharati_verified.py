"""Forward Bharati Braille tables mirrored from the app's NIEPVD 2025 engines.

These tables support deterministic encoding explanations only. They do not
provide validated reverse translation or current Bharati 2.1 coverage.
"""

import re

_HI = {
    'ँ':[3], 'ं':[56], 'ः':[6], 'अ':[1], 'आ':[345], 'इ':[24], 'ई':[35],
    'उ':[136], 'ऊ':[1256], 'ऋ':[5,1235], 'ऌ':[5,123], 'ए':[15], 'ऐ':[34],
    'ऑ':[1346], 'ओ':[135], 'औ':[246], 'क':[13], 'ख':[46], 'ग':[1245],
    'घ':[126], 'ङ':[346], 'च':[14], 'छ':[16], 'ज':[245], 'झ':[356],
    'ञ':[25], 'ट':[23456], 'ठ':[2456], 'ड':[1246], 'ढ':[123456],
    'ण':[3456], 'त':[2345], 'थ':[1456], 'द':[145], 'ध':[2346], 'न':[1345],
    'प':[1234], 'फ':[124], 'ब':[12], 'भ':[45], 'म':[134], 'य':[13456],
    'र':[1235], 'ल':[123], 'ळ':[456], 'व':[1236], 'श':[146], 'ष':[12346],
    'स':[234], 'ह':[125], '़':[5], 'ऽ':[2], 'ा':[345], 'ि':[24], 'ी':[35],
    'ु':[136], 'ू':[1256], 'ृ':[5,1235], 'ॄ':[6,1235], 'ॅ':[1346], 'े':[15],
    'ै':[34], 'ॉ':[1346], 'ो':[135], 'ौ':[246], '्':[4], 'ॐ':[5,1256],
    'ड़':[12456], 'ढ़':[5,12456], 'ॠ':[6,1235], 'ॡ':[6,123], 'ॢ':[5,123],
    'ॣ':[6,123], 'क्ष':[12345], 'ज्ञ':[156], 'त्र':[4,2345,1235],
    'श्र':[4,146,1235], 'ऩ':[5,1345], 'ऱ':[5,1235],
}
_KN = {
    'ಂ':[56], 'ಃ':[6], 'ಅ':[1], 'ಆ':[345], 'ಇ':[24], 'ಈ':[35], 'ಉ':[136],
    'ಊ':[1256], 'ಋ':[5,1235], 'ಎ':[26], 'ಏ':[15], 'ಐ':[34], 'ಒ':[1346],
    'ಓ':[135], 'ಔ':[246], 'ಕ':[13], 'ಖ':[46], 'ಗ':[1245], 'ಘ':[126],
    'ಙ':[346], 'ಚ':[14], 'ಛ':[16], 'ಜ':[245], 'ಝ':[356], 'ಞ':[25],
    'ಟ':[23456], 'ಠ':[2456], 'ಡ':[1246], 'ಢ':[123456], 'ಣ':[3456],
    'ತ':[2345], 'ಥ':[1456], 'ದ':[145], 'ಧ':[2346], 'ನ':[1345], 'ಪ':[1234],
    'ಫ':[124], 'ಬ':[12], 'ಭ':[45], 'ಮ':[134], 'ಯ':[13456], 'ರ':[1235],
    'ಱ':[12456], 'ಲ':[123], 'ಳ':[456], 'ವ':[1236], 'ಶ':[146], 'ಷ':[12346],
    'ಸ':[234], 'ಹ':[125], '಼':[5], 'ಾ':[345], 'ಿ':[24], 'ೀ':[35], 'ು':[136],
    'ೂ':[1256], 'ೃ':[5,1235], 'ೄ':[6,1235], 'ೆ':[26], 'ೇ':[15], 'ೈ':[34],
    'ೊ':[1346], 'ೋ':[135], 'ೌ':[246], '್':[4], 'ಕ್ಷ':[12345], 'ಜ್ಞ':[156],
    'ೞ':[5,456],
}
_DIGITS = [245,1,12,14,145,15,124,1245,125,24]
_PUNCT = {',':1, ':':3, '!':6, '-':36, '.':4, '?':8, ';':2, ' ':0}


def supported_mappings(language: str) -> dict[str, list[int]]:
    """Return a defensive copy of the verified forward Bharati subset."""
    table = _HI if language == "Hindi" else _KN if language == "Kannada" else None
    if table is None:
        raise ValueError("unsupported_bharati_language")
    return {character: list(dot_numbers) for character, dot_numbers in table.items()}

def requested_target(question: str, language: str) -> str | None:
    """Extract the character/word attached to an explicit encoding request.

    Language names and grammatical prompt words are excluded; we never choose
    the longest script run because it may simply be the language name.
    """
    if not question or language not in {"Hindi", "Kannada"}:
        return None
    script = r"[\u0900-\u097f]+" if language == "Hindi" else r"[\u0c80-\u0cff]+"
    ignored = ({"हिंदी", "में", "कैसे", "लिखते", "हैं", "लिखूं", "अक्षर", "के", "क्या", "डॉट्स", "बताएं"}
               if language == "Hindi" else
               {"ಕನ್ನಡ", "ಕನ್ನಡದಲ್ಲಿ", "ಹೇಗೆ", "ಬರೆಯುವುದು", "ಅಕ್ಷರ", "ಚುಕ್ಕೆ", "ಏನು", "ಎಂಬುದು"})
    # Prefer the explicit target after the language preposition, or before the
    # word for character/letter. Otherwise accept one non-instruction token.
    preferred = re.search(rf"(?:में|ನಲ್ಲಿ)\s+({script})|({script})\s+(?:अक्षर|ಅಕ್ಷರ)", question)
    if preferred:
        return next(group for group in preferred.groups() if group)
    candidates = [token for token in re.findall(script, question) if token not in ignored]
    return candidates[0] if len(candidates) == 1 else None


def encode(text: str, language: str) -> list[int] | None:
    table = _HI if language == 'Hindi' else _KN if language == 'Kannada' else None
    if table is None or not text:
        return None
    digits_start = 0x0966 if language == 'Hindi' else 0x0CE6
    out: list[int] = []
    i = 0
    while i < len(text):
        special = next((part for size in (3, 2)
                        if (part := text[i:i + size]) in table), None)
        if special:
            out.extend(table[special])
            i += len(special)
            continue
        char = text[i]
        code = ord(char)
        if char in table:
            out.extend(table[char])
        elif digits_start <= code <= digits_start + 9:
            out.extend((60, _DIGITS[code - digits_start]))
        elif char in _PUNCT:
            out.append(_PUNCT[char])
        elif char.isspace():
            out.append(0)
        else:
            return None
        i += 1
    return out


def bitmasks(dot_numbers: list[int]) -> list[int]:
    return [sum(1 << (int(digit) - 1) for digit in str(number))
            if number else 0 for number in dot_numbers]

