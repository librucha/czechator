import pytest

from czllm.numbered_list import (
    BadNumbering, CountMismatch, UnexpectedContinuation, decode, encode,
)


def test_encodes_items_with_one_based_numbering():
    assert encode(["prvni", "druhy"]) == "1. prvni\n2. druhy"


def test_escapes_newlines_and_backslashes():
    assert encode(["a\nb", "c\\d"]) == "1. a\\nb\n2. c\\\\d"


def test_decode_round_trips_encode():
    items = ["prvni radek", "s\nnovym radkem", "zpetne \\ lomitko", "tabulator\tuvnitr"]
    assert decode(encode(items), 4) == items


def test_literal_backslash_sequences_survive():
    items = ["C:\\new\\temp", "regex \\d+\\n", "konec \\"]
    assert encode(items[:1]) == "1. C:\\\\new\\\\temp"
    assert decode(encode(items), 3) == items


def test_crlf_is_two_escapes():
    assert encode(["a\r\nb"]) == "1. a\\r\\nb"
    assert decode("1. a\\r\\nb", 1) == ["a\r\nb"]


def test_decode_tolerates_code_fences_and_blank_lines():
    assert decode("```\n\n1. prvni\n\n2. druhy\n```\n", 2) == ["prvni", "druhy"]


def test_decode_rejects_wrong_count():
    with pytest.raises(CountMismatch):
        decode("1. a\n2. b", 3)


def test_decode_rejects_continuation_line():
    with pytest.raises(UnexpectedContinuation):
        decode("1. prvni\n2. druhy radek\npokracovani druheho", 2)


def test_decode_rejects_wrong_numbering():
    with pytest.raises(BadNumbering):
        decode("1. a\n3. b", 2)


def test_decode_tolerates_preamble():
    assert decode("Zde je opraveny seznam:\n1. prvni\n2. druhy", 2) == ["prvni", "druhy"]


def test_decode_resolves_unicode_escape():
    assert decode("1. a\\u00e1b", 1) == ["aáb"]
