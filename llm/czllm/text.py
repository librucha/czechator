import hashlib
import re

from czllm.fold import fold, has_diacritics, nfc

# Mirror of FragileWhitespace.characters: czechator replaces these with a plain
# space before the model sees the text, so training and eval must too.
FRAGILE = frozenset(
    "           "
    "　​⁠­‑﻿"
)
WORD_RE = re.compile(r"[^\W\d_]+")


def normalize(s: str) -> str:
    return "".join(" " if c in FRAGILE else c for c in nfc(s))


def words(s: str) -> list[str]:
    return [w for w in WORD_RE.findall(nfc(s)) if len(w) >= 2]


def diacritic_word_ratio(s: str) -> float:
    ws = words(s)
    if not ws:
        return 0.0
    return sum(has_diacritics(w) for w in ws) / len(ws)


def fold_key(s: str) -> str:
    """Identity of a text regardless of diacritics, case and whitespace kind —
    the unit of dedup and of the train/eval leak check."""
    canonical = " ".join(fold(normalize(s)).lower().split())
    return hashlib.sha1(canonical.encode("utf-8")).hexdigest()
