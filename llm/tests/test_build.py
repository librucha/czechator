import random

import pytest

from czllm.format.build import (
    BuildConfig, InsufficientData, build, chunk_lines, doc_units, join_newlines, synth_units,
)
from czllm.format.contracts import systems
from czllm.format.validate import validate_record
from czllm.text import fold_key

LINE = "Včera jsem koupil nový počítač a přinesl ho domů."


def test_chunk_lines_respects_budget_and_keeps_order():
    lines = [f"{LINE} {i}" for i in range(40)]
    chunks = chunk_lines(lines, random.Random(0), BuildConfig())
    assert [l for c in chunks for l in c] == lines
    assert all(sum(map(len, c)) <= 1500 for c in chunks)


def test_doc_units_skip_heldout_docs_and_excluded_lines():
    from czllm.eval.sets import is_heldout
    docs = [{"doc_id": f"d{i}", "lines": [f"{LINE} {i}"]} for i in range(500)]
    excluded = {fold_key(f"{LINE} 7")}
    units = doc_units(docs, excluded, random.Random(0), BuildConfig())
    texts = {l for u in units for l in u}
    assert f"{LINE} 7" not in texts
    assert all(not is_heldout(f"d{i}") for i in range(500) if f"{LINE} {i}" in texts)


def test_synth_units_split_lines_and_drop_excluded():
    records = [{"text": "Fixnul jsem to.\n\nDíky."}, {"text": "Mergnu to zítra."}]
    assert synth_units(records, {fold_key("Mergnu to zítra.")}) == [["Fixnul jsem to.", "Díky."]]


def test_join_newlines_merges_neighbours():
    assert join_newlines(["a", "b", "c"], random.Random(0), 1.0) == ["a\nb", "c"]
    assert join_newlines(["a", "b"], random.Random(0), 0.0) == ["a", "b"]


def _units(n, tag):
    return [[f"{LINE} {tag} {i}"] for i in range(n)]


def test_build_mix_contracts_and_validity():
    cfg = BuildConfig(total=200, valid=20, mix={"fineweb": 0.5, "hybrid": 0.5})
    train, valid, stats = build({"fineweb": _units(200, "w"), "hybrid": _units(200, "h")}, cfg, random.Random(0))
    assert len(train) == 200 and len(valid) == 20
    assert stats["source"] == {"fineweb": 110, "hybrid": 110}
    assert 0.45 < stats["contract"]["drop_in"] / 220 < 0.75
    known = set(systems().values())
    for record in train + valid:
        validate_record(record, known, set())


def test_build_cli_takes_the_total_and_keeps_the_mix():
    import argparse

    from czllm.format.build import config_from_args, register

    parser = argparse.ArgumentParser()
    register(parser.add_subparsers())
    args = parser.parse_args(["build", "--id", "s01", "--total", "38875"])
    cfg = config_from_args(args)
    assert cfg.total == 38875 and cfg.valid == 1000 and cfg.mix == BuildConfig().mix
    assert config_from_args(parser.parse_args(["build", "--id", "s01"])).total == 40_000


def test_joining_never_pushes_a_full_unit_over_the_batch_limit():
    from dataclasses import replace

    full = [["a" * 750, "b" * 750]]   # exactly 1500 chars; a join adds "\n"
    cfg = replace(BuildConfig(total=1, valid=0, mix={"fineweb": 1.0}), join_newline=1.0)
    train, _, _ = build({"fineweb": full}, cfg, random.Random(0))
    validate_record(train[0], set(systems().values()), set())


def test_build_refuses_when_a_source_is_short():
    cfg = BuildConfig(total=100, valid=0, mix={"fineweb": 1.0})
    with pytest.raises(InsufficientData, match="fineweb"):
        build({"fineweb": _units(10, "w")}, cfg, random.Random(0))
