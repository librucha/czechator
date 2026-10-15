from czllm.eval.harness import batches, latency_texts, run_set
from czllm.eval.ollama import ChatResult
from czllm.eval.report import render
from czllm.numbered_list import decode


def test_batches_mirror_segment_batcher():
    assert batches(["a" * 1000, "b" * 400, "c" * 200, "d" * 2000, "e"], 1500) == [[0, 1], [2], [3], [4]]


class FakeClient:
    """Answers with a canned correction table; can misbehave on demand."""

    def __init__(self, table, mode="ok"):
        self.table, self.mode, self.calls = table, mode, 0

    def chat(self, model, system, user):
        self.calls += 1
        items = decode(user, user.count("\n") + 1)
        fixed = [self.table.get(i, i) for i in items]
        if self.mode == "think":
            content = "<think>hmm</think>\n" + "\n".join(f"{n}. {t}" for n, t in enumerate(fixed, 1))
        elif self.mode == "drop":
            content = "\n".join(f"{n}. {t}" for n, t in enumerate(fixed[:-1], 1))
        else:
            content = "\n".join(f"{n}. {t}" for n, t in enumerate(fixed, 1))
        return ChatResult(content=content, thinking="", prompt_tokens=10, eval_tokens=5, wall_s=0.1, eval_s=0.05)


RECORDS = [
    {"id": "h1", "text": "Mergnul jsem PR.\nZítra pushnu.", "english_terms": ["Mergnul", "PR", "pushnu"]},
    {"id": "h2", "text": "Kůň.", "english_terms": []},
]
TABLE = {"Zitra pushnu.": "Zítra pushnu.", "Kun.": "Kůň."}


def test_run_set_scores_items_and_english_terms():
    score, failures = run_set(FakeClient(TABLE), "m", "sys", RECORDS, frozenset())
    r = score.rates()
    assert r["items"] == 3 and r["exact"] == 1.0 and r["format_fail"] == 0
    assert r["en_untouched"] == 1.0
    assert failures == []


def test_think_tags_count_as_format_failure():
    score, _ = run_set(FakeClient(TABLE, mode="think"), "m", "sys", RECORDS, frozenset())
    assert score.format_fail == 3 and score.rates()["verified"] == 0.0


def test_dropped_item_fails_the_whole_batch():
    score, failures = run_set(FakeClient(TABLE, mode="drop"), "m", "sys", RECORDS, frozenset())
    assert score.format_fail == 3
    assert failures and failures[0]["id"] == "h1"


def test_latency_texts_pick_closest_to_target():
    recs = [{"text": "x" * n} for n in (50, 290, 310, 900, 305)]
    assert [len(t) for t in latency_texts(recs, n=3, target=300)] == [305, 290, 310]


def test_render_contains_models_and_sets():
    result = {
        "model": "czechator-qwen35-0.8b:v1-q8_0", "contract": "drop_in",
        "sets": {"web": {"items": 10, "exact": 0.9, "verified": 1.0, "format_fail": 0, "der": 0.01,
                         "missing": 1, "spurious": 0, "wrong": 0, "ambiguous_errors": 1, "en_untouched": 0.0}},
        "latency": {"cold_s": 1.2, "p50_s": 0.4, "p95_s": 0.6, "tokens_per_s": 180.0},
    }
    md = render([result])
    assert "czechator-qwen35-0.8b:v1-q8_0" in md and "| web |" in md and "0.40" in md
