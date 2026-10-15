"""Catches diacritic mistakes in generated Czech.

A word hunspell rejects while suggesting a variant with the same fold is a
missing or wrong accent — exactly the error the model would learn as truth.
English terms hunspell does not know produce no such suggestion and pass.
"""

import subprocess
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from czllm.fold import fold

DEFAULT_DICT = Path("data/dict/cs_CZ")


class Checker(Protocol):
    def suggestions(self, words: list[str]) -> dict[str, list[str] | None]: ...


def parse_pipe_output(words: list[str], stdout: str) -> dict[str, list[str] | None]:
    lines = stdout.splitlines()
    if lines and lines[0].startswith("@(#)"):
        lines = lines[1:]
    blocks: list[list[str]] = []
    current: list[str] = []
    for line in lines:
        if line == "":
            blocks.append(current)
            current = []
        else:
            current.append(line)
    if current:
        blocks.append(current)
    if len(blocks) != len(words):
        raise ValueError(f"hunspell returned {len(blocks)} results for {len(words)} words")

    result: dict[str, list[str] | None] = {}
    for word, block in zip(words, blocks):
        suggestions: list[str] | None = None
        for line in block:
            if line.startswith("&"):
                suggestions = (suggestions or []) + [s.strip() for s in line.split(":", 1)[1].split(",")]
            elif line.startswith("#"):
                suggestions = suggestions or []
        result[word] = suggestions
    return result


@dataclass(frozen=True)
class Hunspell:
    dictionary: Path = DEFAULT_DICT

    def suggestions(self, words: list[str]) -> dict[str, list[str] | None]:
        if not words:
            return {}
        # "^" makes hunspell treat each line as text, never as a command.
        proc = subprocess.run(
            ["hunspell", "-a", "-i", "utf-8", "-d", str(self.dictionary)],
            input="".join(f"^{w}\n" for w in words),
            capture_output=True, text=True, encoding="utf-8", check=True,
        )
        return parse_pipe_output(words, proc.stdout)


def suspicious_words(words: Iterable[str], checker: Checker) -> list[str]:
    unique = list(dict.fromkeys(words))
    found = checker.suggestions(unique)
    return [
        w for w in unique
        if found[w] and any(s != w and fold(s) == fold(w) for s in found[w])
    ]
