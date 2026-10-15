import pytest

from czllm.format.contracts import SHORT_SYSTEM, chat_record, systems
from czllm.format.validate import DatasetError, validate_record
from czllm.text import fold_key

SYSTEMS = set(systems().values())
GOOD = chat_record(SHORT_SYSTEM, ["Prilis zlutoucky kun", "C:\\new"], ["Příliš žluťoučký kůň", "C:\\new"])


def test_drop_in_system_is_the_swift_default():
    from czllm import swift_source
    assert systems()["drop_in"] == swift_source.default_system()
    assert systems()["short"] == "Restore Czech diacritics in each numbered item. Change nothing else."


def test_good_record_passes():
    validate_record(GOOD, SYSTEMS, set())


def test_rejects_changed_word():
    bad = chat_record(SHORT_SYSTEM, ["schuzka je v utery"], ["schůzka je ve středu"])
    with pytest.raises(DatasetError, match="fold"):
        validate_record(bad, SYSTEMS, set())


def test_rejects_unknown_system():
    bad = chat_record("Be helpful.", ["kun"], ["kůň"])
    with pytest.raises(DatasetError, match="system"):
        validate_record(bad, SYSTEMS, set())


def test_rejects_item_count_mismatch():
    bad = chat_record(SHORT_SYSTEM, ["kun", "pes"], ["kůň"])
    with pytest.raises(DatasetError, match="items"):
        validate_record(bad, SYSTEMS, set())


def test_rejects_eval_leak_even_without_diacritics():
    keys = {fold_key("Příliš žluťoučký kůň")}
    with pytest.raises(DatasetError, match="eval"):
        validate_record(GOOD, SYSTEMS, keys)


def test_rejects_oversized_batch():
    long = "kůň " * 400   # 1600 chars
    bad = chat_record(SHORT_SYSTEM, ["kun " * 400], [long])
    with pytest.raises(DatasetError, match="1500"):
        validate_record(bad, SYSTEMS, set())
