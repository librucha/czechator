import json
from types import SimpleNamespace as NS

from czllm.synth.batch import SynthPlan, accept_message, build_requests, estimate_usd, parse_result
from czllm.synth.prompts import HYBRID, NEGATIVE, SCHEMA

PLAN = SynthPlan(model="claude-opus-5-5", per_request=20, train_hybrid=16, train_negative=4, eval_hybrid=8)


def test_build_requests_counts_ids_and_shape():
    reqs = build_requests(PLAN)
    assert len(reqs) == 28
    ids = [r["custom_id"] for r in reqs]
    assert len(set(ids)) == len(ids)
    assert all(len(i) <= 64 and set(i) <= set("abcdefghijklmnopqrstuvwxyz0123456789_-") for i in ids)
    first = reqs[0]["params"]
    assert first["model"] == "claude-opus-5-5"
    assert first["output_config"] == {"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}}
    assert "temperature" not in first and "thinking" not in first
    cats = {r["custom_id"].split("--")[1] for r in reqs}
    assert cats == set(HYBRID) | set(NEGATIVE)


def test_eval_requests_use_only_eval_topics():
    from czllm.synth.prompts import TOPICS_EVAL, TOPICS_TRAIN
    assert not set(TOPICS_EVAL) & set(TOPICS_TRAIN)
    evals = [r for r in build_requests(PLAN) if r["custom_id"].startswith("eval--")]
    assert all(any(t in r["params"]["messages"][0]["content"] for t in TOPICS_EVAL) for r in evals)


def test_estimate_is_half_price_batch():
    # 900 in, 3000 out at $4/$20 per MTok, halved by Batch API
    assert round(estimate_usd(100, "claude-opus-5-5"), 2) == 3.18


def _entry(result_type="succeeded", stop="end_turn", text='{"messages": []}'):
    message = NS(stop_reason=stop, content=[NS(type="thinking", thinking=""), NS(type="text", text=text)])
    return NS(custom_id="train--slack_dev--0000", result=NS(type=result_type, message=message))


def test_parse_result():
    payload = {"messages": [{"text": "Mergnu to zítra.", "english_terms": ["Mergnu"]}]}
    assert parse_result(_entry(text=json.dumps(payload))) == payload["messages"]
    assert parse_result(_entry(result_type="errored")) is None
    assert parse_result(_entry(stop="refusal")) is None
    assert parse_result(_entry(stop="max_tokens")) is None
    assert parse_result(_entry(text="not json")) is None


def test_accept_message():
    none_suspicious = lambda ws: []
    assert accept_message("hybrid", "Pushnu to na staging zítra.", none_suspicious) is None
    assert accept_message("hybrid", "Pushnu to na staging zitra.", none_suspicious) == "no-diacritics"
    assert accept_message("hybrid", "Pushnu to zitra ráno.", lambda ws: ["zitra"]) == "spelling"
    assert accept_message("negative", "git push origin main", none_suspicious) is None
    assert accept_message("negative", "Hotovo, díky.", none_suspicious) == "has-diacritics"
    assert accept_message("hybrid", "   ", none_suspicious) == "empty"


def test_default_plan_has_headroom_over_the_build_mix():
    from czllm.format.build import BuildConfig

    plan, cfg = SynthPlan(), BuildConfig()
    wanted = cfg.total + cfg.valid
    assert plan.train_hybrid * plan.per_request >= 1.25 * round(cfg.mix["hybrid"] * wanted)
    assert plan.train_negative * plan.per_request >= 1.25 * round(cfg.mix["negative"] * wanted)


def test_dry_run_states_the_estimate_is_a_lower_bound(capsys):
    from czllm.synth.batch import submit

    assert submit(NS(model="claude-opus-5-5", yes=False)) == 0
    out = capsys.readouterr().out
    assert "at least $" in out and "thinking" in out and "Dry run" in out
