import random

from czllm.fold import fold, has_diacritics
from czllm.format.augment import AugmentConfig, augment, check_pair, recase, strip_partial

SAMPLES = [
    "Příliš žluťoučký kůň úpěl ďábelské ódy.",
    "Mergnul jsem PR do mainu, pushnu to na staging zítra.",
    "This is English, leave it alone.",
    "Cena je 1 500 Kč, splatnost 14 dní.",
]


def test_invariant_holds_for_every_mode_and_seed():
    for seed in range(300):
        inputs, targets, _ = augment(SAMPLES, random.Random(seed), AugmentConfig())
        assert all(check_pair(i, t) for i, t in zip(inputs, targets))


def test_strip_mode_removes_all_diacritics():
    cfg = AugmentConfig(strip=1, partial=0, identity=0, lower=0, upper=0)
    inputs, targets, mode = augment(SAMPLES, random.Random(0), cfg)
    assert mode == "strip"
    assert targets == SAMPLES
    assert inputs == [fold(s) for s in SAMPLES]


def test_identity_mode_keeps_input():
    cfg = AugmentConfig(strip=0, partial=0, identity=1, lower=0, upper=0)
    inputs, targets, _ = augment(SAMPLES, random.Random(0), cfg)
    assert inputs == targets == SAMPLES


def test_partial_keeps_some_accents():
    text = SAMPLES[0] * 5
    assert strip_partial(text, 0.0, random.Random(1)) == fold(text)
    assert strip_partial(text, 1.0, random.Random(1)) == text
    middle = strip_partial(text, 0.5, random.Random(1))
    assert has_diacritics(middle) and middle != text


def test_recase_refuses_length_changing_case_maps():
    assert recase("Straße", "upper") == "Straße"
    assert recase("Kůň", "upper") == "KŮŇ"
    assert recase("Kůň", "lower") == "kůň"
