from czllm import swift_source
from czllm.text import FRAGILE, diacritic_word_ratio, fold_key, normalize


def test_fragile_matches_swift():
    assert FRAGILE == swift_source.fragile_characters()


def test_normalize_replaces_fragile_whitespace_and_composes():
    assert normalize("v úterý š") == "v úterý š"


def test_ratio_counts_words_of_two_letters_or_more():
    assert diacritic_word_ratio("Příliš žluťoučký kůň úpěl") == 1.0
    assert diacritic_word_ratio("Prilis zlutoucky kun upel") == 0.0
    assert diacritic_word_ratio("a v k že") == 1.0
    assert diacritic_word_ratio("123 !!") == 0.0


def test_fold_key_ignores_diacritics_case_and_whitespace_kind():
    assert fold_key("Příliš žluťoučký") == fold_key("prilis  zlutoucky")
    assert fold_key("kůň") != fold_key("kun a")
