import random

from czllm.eval.sets import (
    eval_keys, export_review, freeze_web, import_private, import_review, is_heldout, segments,
)
from czllm.jsonl import write_jsonl
from czllm.text import fold_key


def test_heldout_is_deterministic_and_about_two_percent():
    ids = [f"doc-{i}" for i in range(10_000)]
    share = sum(is_heldout(i) for i in ids) / len(ids)
    assert 0.01 < share < 0.03
    assert is_heldout("doc-1") == is_heldout("doc-1")


def test_freeze_web_takes_only_heldout_docs():
    docs = [{"source": "fineweb", "doc_id": f"d{i}", "lines": [f"Věta číslo {i} je tady.", f"Druhá věta {i} je zde."]}
            for i in range(5_000)]
    out = freeze_web(docs, {"fineweb": 30}, random.Random(0))
    assert len(out) == 30
    allowed = {line for d in docs if is_heldout(d["doc_id"]) for line in d["lines"]}
    assert all(r["text"] in allowed for r in out)
    assert len({r["id"] for r in out}) == 30


def test_review_round_trip(tmp_path):
    synth = [
        {"custom_id": "eval--commit--0000", "text": "Fixnul jsem bug.\nDruhý řádek.", "english_terms": ["Fixnul", "bug"]},
        {"custom_id": "eval--commit--0001", "text": "Mergnu to zitra.", "english_terms": ["Mergnu"]},
        {"custom_id": "eval--commit--0002", "text": "Hotovo, díky.", "english_terms": []},
    ]
    for i, r in enumerate(synth):
        r["id"] = f"hybrid-{i:04d}"
    tsv = tmp_path / "review.tsv"
    assert export_review(synth, tsv, 3, random.Random(0)) == 3
    rows = tsv.read_text(encoding="utf-8").splitlines()
    assert rows[0] == "id\tverdict\ttext"
    edited = []
    for row in rows[1:]:
        rid, _, text = row.split("\t")
        if rid == "hybrid-0001":
            edited.append(f"{rid}\tfix\tMergnu to zítra.")
        elif rid == "hybrid-0002":
            edited.append(f"{rid}\tx\t{text}")
        else:
            edited.append(f"{rid}\tok\t{text}")
    tsv.write_text("\n".join([rows[0], *edited]) + "\n", encoding="utf-8")
    out = {r["id"]: r for r in import_review(tsv, {r["id"]: r for r in synth})}
    assert set(out) == {"hybrid-0000", "hybrid-0001"}
    assert out["hybrid-0000"]["text"] == "Fixnul jsem bug.\nDruhý řádek."
    assert out["hybrid-0001"]["text"] == "Mergnu to zítra."
    assert all(r["reviewed"] for r in out.values())


def test_review_accepts_the_verdict_after_the_text(tmp_path):
    # Reviewers append the verdict as a fourth column; it must not end up
    # inside the reference text.
    synth = {
        "hybrid-0000": {"text": "Pushnu to zítra.", "english_terms": ["Pushnu"]},
        "hybrid-0001": {"text": "Mergnu to zitra.", "english_terms": ["Mergnu"]},
        "hybrid-0002": {"text": "Hotovo, díky.", "english_terms": []},
    }
    tsv = tmp_path / "review.tsv"
    tsv.write_text(
        "id\tverdict\ttext\n"
        "hybrid-0000\t\tPushnu to zítra.\tok\n"
        "hybrid-0001\t\tMergnu to zítra.\tfix\n"
        "hybrid-0002\t\tHotovo, díky.\tx\n",
        encoding="utf-8",
    )
    out = {r["id"]: r for r in import_review(tsv, synth)}
    assert set(out) == {"hybrid-0000", "hybrid-0001"}
    assert out["hybrid-0000"]["text"] == "Pushnu to zítra."
    assert out["hybrid-0001"]["text"] == "Mergnu to zítra."
    assert all(r["reviewed"] for r in out.values())


def test_review_rejects_rows_it_cannot_read(tmp_path):
    import pytest

    tsv = tmp_path / "review.tsv"
    tsv.write_text("id\tverdict\ttext\nhybrid-0000\tok\tA\tB\tC\n", encoding="utf-8")
    with pytest.raises(ValueError, match="hybrid-0000"):
        import_review(tsv, {"hybrid-0000": {"text": "A", "english_terms": []}})


def test_import_private_normalizes_like_czechator(tmp_path):
    f = tmp_path / "slack.txt"
    f.write_text("Schůzka je v úterý.\n\n  škola  \n", encoding="utf-8")
    out = import_private([f])
    assert [r["text"] for r in out] == ["Schůzka je v úterý.", "škola"]
    assert out[0]["id"].startswith("private-")


def test_eval_keys_cover_every_segment(tmp_path):
    p = tmp_path / "e.jsonl"
    write_jsonl(p, [{"id": "a", "text": "První řádek.\nDruhý řádek."}])
    assert eval_keys([p, tmp_path / "missing.jsonl"]) == {fold_key("První řádek."), fold_key("Druhý řádek.")}


def test_segments_are_non_empty_lines():
    assert segments("a\n\n b \n") == ["a", " b "]


def test_require_eval_sets_refuses_when_web_or_hybrid_is_missing(tmp_path):
    import pytest

    from czllm.eval.sets import require_eval_sets

    paths = {"web": tmp_path / "web.jsonl", "hybrid": tmp_path / "hybrid.jsonl", "private": tmp_path / "p.jsonl"}
    write_jsonl(paths["web"], [{"id": "w", "text": "Věta."}])
    with pytest.raises(SystemExit, match="hybrid"):
        require_eval_sets(paths)
    write_jsonl(paths["hybrid"], [{"id": "h", "text": "Mergnu to."}])
    require_eval_sets(paths)   # private is optional
