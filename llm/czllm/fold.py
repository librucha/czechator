"""Czech diacritic folding.

The same 30-character table as the Swift `DiacriticFolding`; a test parses the
Swift source so the two cannot drift apart. Anything else (ä, ö, …) is left
alone, exactly as the verifier in czechator does.
"""

import unicodedata

TABLE: dict[str, str] = {
    "á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ý": "y",
    "č": "c", "ď": "d", "ě": "e", "ň": "n", "ř": "r",
    "š": "s", "ť": "t", "ů": "u", "ž": "z",
    "Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ú": "U", "Ý": "Y",
    "Č": "C", "Ď": "D", "Ě": "E", "Ň": "N", "Ř": "R",
    "Š": "S", "Ť": "T", "Ů": "U", "Ž": "Z",
}
DIACRITICS = frozenset(TABLE)
_TRANSLATION = str.maketrans(TABLE)


def nfc(s: str) -> str:
    # Swift compares Characters by canonical equivalence; NFC gives Python the
    # same view of a decomposed "s" + U+030C.
    return unicodedata.normalize("NFC", s)


def fold(s: str) -> str:
    return nfc(s).translate(_TRANSLATION)


def has_diacritics(s: str) -> bool:
    return any(c in DIACRITICS for c in nfc(s))
