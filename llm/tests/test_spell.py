import shutil
from pathlib import Path

import pytest

from czllm.synth.spell import DEFAULT_DICT, Hunspell, parse_pipe_output, suspicious_words

STDOUT = (
    "@(#) International Ispell Version 3.2.06 (but really Hunspell 1.7.2)\n"
    "*\n"
    "\n"
    "& zlutoucky 3 0: žluťoučký, žlutoučký, zlutoučky\n"
    "\n"
    "# qwxz 0\n"
    "\n"
)


def test_parse_pipe_output():
    assert parse_pipe_output(["příliš", "zlutoucky", "qwxz"], STDOUT) == {
        "příliš": None,
        "zlutoucky": ["žluťoučký", "žlutoučký", "zlutoučky"],
        "qwxz": [],
    }


def test_parse_pipe_output_rejects_misaligned_output():
    with pytest.raises(ValueError):
        parse_pipe_output(["a", "b"], STDOUT)


class FakeChecker:
    def __init__(self, table):
        self.table = table

    def suggestions(self, words):
        return {w: self.table.get(w) for w in words}


def test_suspicious_only_when_a_suggestion_differs_by_diacritics():
    checker = FakeChecker({
        "pristi": ["příští"],          # same fold: generator dropped accents
        "deploynul": ["deployoval"],   # different word: foreign term, fine
        "qwxz": [],                    # unknown, no suggestion
    })
    words = ["příští", "pristi", "deploynul", "qwxz", "pristi"]
    assert suspicious_words(words, checker) == ["pristi"]


@pytest.mark.integration
@pytest.mark.skipif(
    not shutil.which("hunspell") or not Path(f"{DEFAULT_DICT}.dic").exists(),
    reason="hunspell or data/dict/cs_CZ missing (make dict)",
)
def test_real_hunspell_lists_misspelled_words():
    assert Hunspell(DEFAULT_DICT).misspelled(["žluťoučký", "zlutoucky", "kůň"]) == {"zlutoucky"}


@pytest.mark.integration
@pytest.mark.skipif(
    not shutil.which("hunspell") or not Path(f"{DEFAULT_DICT}.dic").exists(),
    reason="hunspell or data/dict/cs_CZ missing (make dict)",
)
def test_real_hunspell_flags_missing_hacek():
    result = suspicious_words(["žluťoučký", "zlutoucky"], Hunspell(DEFAULT_DICT))
    assert "zlutoucky" in result
    assert "žluťoučký" not in result
