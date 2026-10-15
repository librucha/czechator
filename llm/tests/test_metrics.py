from czllm.eval.metrics import SetScore, build_ambiguity, score_item

AMB = frozenset({"byt"})


def test_exact_match():
    s = score_item("Je to byt.", "Je to byt.", "Je to byt.", AMB)
    assert s.exact and s.verified and s.word_errors == 0 and s.words == 3


def test_missing_spurious_and_wrong_accents():
    s = score_item("dekuji vam ze", "děkuji vám že", "dekují vam žé", AMB)
    assert s.verified and not s.exact
    assert (s.missing, s.spurious, s.wrong) == (2, 2, 0)
    assert s.word_errors == 3 and s.words == 3


def test_wrong_accent_kind():
    s = score_item("pet", "pět", "pét", AMB)
    assert s.wrong == 1 and s.word_errors == 1


def test_ambiguous_errors_are_counted_separately():
    s = score_item("chce byt", "chce být", "chce byt", AMB)
    assert s.word_errors == 1 and s.ambiguous_errors == 1


def test_changed_word_is_not_verified_and_not_scored_per_word():
    s = score_item("schuzka v utery", "schůzka v úterý", "schůzka ve středu", AMB)
    assert not s.verified and s.words == 0


def test_missing_item_is_not_verified():
    s = score_item("kun", "kůň", None, AMB)
    assert not s.verified and not s.exact


def test_set_rates():
    agg = SetScore()
    agg.add(score_item("kun", "kůň", "kůň", AMB))
    agg.add(score_item("pes", "pes", None, AMB))
    agg.format_fail = 1
    agg.en_terms, agg.en_untouched = 4, 3
    r = agg.rates()
    assert r["exact"] == 0.5 and r["verified"] == 0.5 and r["der"] == 0.0 and r["en_untouched"] == 0.75


def test_build_ambiguity():
    lines = ["byt byt byt být být být", "kůň kůň kůň", "rad rad rád"]
    assert build_ambiguity(lines) == frozenset({"byt"})
