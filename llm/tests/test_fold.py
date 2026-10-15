from czllm import swift_source
from czllm.fold import TABLE, fold, has_diacritics


def test_table_matches_swift_source():
    assert TABLE == swift_source.folding_table()
    assert len(TABLE) == 30


def test_fold_pangram():
    assert fold("Příliš žluťoučký kůň úpěl ďábelské ódy.") == "Prilis zlutoucky kun upel dabelske ody."


def test_fold_leaves_foreign_diacritics_alone():
    assert fold("Müller ä ö") == "Müller ä ö"


def test_fold_handles_decomposed_input():
    assert fold("š") == "s"


def test_has_diacritics():
    assert has_diacritics("kůň")
    assert not has_diacritics("kun")
    assert not has_diacritics("Müller")


def test_fragile_characters_come_from_swift():
    chars = swift_source.fragile_characters()
    assert " " in chars
    assert "‍" not in chars
    assert len(chars) == 17


def test_default_system_is_read_verbatim():
    s = swift_source.default_system()
    assert s.startswith("You restore Czech diacritics. You are a mechanical transformer, not an editor.")
    assert "\n- Output ONLY the numbered list" in s
    assert "The sequences \\n, \\r, \\t and \\\\ are literal two-character escapes." in s
    assert s.endswith("3. This is English, leave it alone.")
