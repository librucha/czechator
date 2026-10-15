"""Turns correct Czech into (input, target) pairs.

The target always carries the full diacritics and the same letter case as the
input: czechator verifies `fold(output) == fold(input)`, so the model must
never learn to touch case.
"""

import random
from dataclasses import dataclass

from czllm.fold import DIACRITICS, TABLE, fold


@dataclass(frozen=True)
class AugmentConfig:
    strip: float = 0.82       # all accents removed — the main case
    partial: float = 0.15     # the writer typed some accents
    identity: float = 0.03    # already correct, must come back unchanged
    lower: float = 0.07       # per item: whole item lowercase
    upper: float = 0.02       # per item: ALL CAPS
    max_keep: float = 0.5     # partial mode keeps up to this share of accents


def strip_partial(text: str, keep: float, rng: random.Random) -> str:
    return "".join(
        c if c not in DIACRITICS or rng.random() < keep else TABLE[c]
        for c in text
    )


def recase(text: str, mode: str) -> str:
    if mode == "keep":
        return text
    out = text.lower() if mode == "lower" else text.upper()
    # "ß".upper() == "SS": a length change would break the positional invariant.
    return out if len(out) == len(text) else text


def check_pair(inp: str, tgt: str) -> bool:
    return len(inp) == len(tgt) and fold(inp) == fold(tgt)


def augment(targets: list[str], rng: random.Random, cfg: AugmentConfig) -> tuple[list[str], list[str], str]:
    mode = rng.choices(("strip", "partial", "identity"), weights=(cfg.strip, cfg.partial, cfg.identity))[0]
    keep = rng.uniform(0.0, cfg.max_keep)
    inputs: list[str] = []
    cased: list[str] = []
    for target in targets:
        r = rng.random()
        case = "lower" if r < cfg.lower else "upper" if r < cfg.lower + cfg.upper else "keep"
        target = recase(target, case)
        cased.append(target)
        if mode == "strip":
            inputs.append(fold(target))
        elif mode == "partial":
            inputs.append(strip_partial(target, keep, rng))
        else:
            inputs.append(target)
    return inputs, cased, mode
