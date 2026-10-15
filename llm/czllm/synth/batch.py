"""Generates the synthetic corpus through the Message Batches API (50 % price).

`submit` without --yes only prints the request count and a cost estimate: the
run spends real money and must be confirmed by a person.
"""

import json
import time
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from czllm.fold import has_diacritics
from czllm.jsonl import write_jsonl
from czllm.synth.prompts import HYBRID, NEGATIVE, SCHEMA, SYSTEM, TOPICS_EVAL, TOPICS_TRAIN, user_prompt
from czllm.synth.spell import Hunspell, suspicious_words
from czllm.text import fold_key, normalize, words

# $ per MTok (input, output), first-party list prices.
PRICES = {
    "claude-opus-5-5": (4.0, 20.0),
    "claude-sonnet-5-5": (2.0, 10.0),
    "claude-haiku-5-5": (0.10, 0.50),
}
STATE = Path("data/synth/batch.json")


@dataclass(frozen=True)
class SynthPlan:
    model: str = "claude-opus-5-5"
    per_request: int = 20
    # >= 25 % headroom over the build mix: hunspell, duplicates and failed
    # requests all cost units, and a shortfall means a second paid batch.
    train_hybrid: int = 520      # ~10 400 messages for 8 200 units
    train_negative: int = 260    # ~5 200 messages for 4 100 units
    eval_hybrid: int = 24        # ~480 messages, 300 go to review


def build_requests(plan: SynthPlan) -> list[dict]:
    requests: list[dict] = []

    def add(split: str, categories: dict[str, str], topics: list[str], count: int) -> None:
        names = sorted(categories)
        for i in range(count):
            category = names[i % len(names)]
            topic = topics[(i // len(names)) % len(topics)]
            requests.append({
                "custom_id": f"{split}--{category}--{i:04d}",
                "params": {
                    "model": plan.model,
                    "max_tokens": 16000,
                    "system": SYSTEM,
                    "output_config": {"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}},
                    "messages": [{"role": "user", "content": user_prompt(category, topic, plan.per_request)}],
                },
            })

    add("train", HYBRID, TOPICS_TRAIN, plan.train_hybrid)
    add("train", NEGATIVE, TOPICS_TRAIN, plan.train_negative)
    add("eval", HYBRID, TOPICS_EVAL, plan.eval_hybrid)
    return requests


def estimate_usd(n_requests: int, model: str, in_tokens: int = 900, out_tokens: int = 3000) -> float:
    price_in, price_out = PRICES[model]
    return n_requests * (in_tokens * price_in + out_tokens * price_out) / 1e6 * 0.5


def parse_result(entry) -> list[dict] | None:
    result = entry.result
    if result.type != "succeeded":
        return None
    message = result.message
    if message.stop_reason != "end_turn":   # refusal, max_tokens
        return None
    text = next((b.text for b in message.content if b.type == "text"), None)
    if text is None:
        return None
    try:
        return json.loads(text)["messages"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return None


def accept_message(kind: str, text: str, suspicious: Callable[[list[str]], list[str]]) -> str | None:
    text = normalize(text).strip()
    if not text:
        return "empty"
    if kind == "negative":
        return "has-diacritics" if has_diacritics(text) else None
    if not has_diacritics(text):
        return "no-diacritics"
    if suspicious(words(text)):
        return "spelling"
    return None


def submit(args) -> int:
    plan = SynthPlan(model=args.model)
    requests = build_requests(plan)
    cost = estimate_usd(len(requests), plan.model)
    # The model cannot turn thinking off; effort low only shrinks it, and those
    # tokens are billed on top of the 3 000-token answer assumed here.
    print(f"{len(requests)} requests on {plan.model}, estimated at least ${cost:.2f} "
          "(Batch API, effort low; thinking tokens not included)")
    if not args.yes:
        print("Dry run. Re-run with --yes to submit.")
        return 0
    import anthropic

    batch = anthropic.Anthropic().messages.batches.create(requests=requests)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({"id": batch.id, "model": plan.model}), encoding="utf-8")
    print(f"submitted {batch.id} -> {STATE}")
    return 0


def collect(args) -> int:
    import anthropic

    client = anthropic.Anthropic()
    batch_id = json.loads(STATE.read_text(encoding="utf-8"))["id"]
    while (batch := client.messages.batches.retrieve(batch_id)).processing_status != "ended":
        print(f"{batch.processing_status}: {batch.request_counts.processing} processing")
        time.sleep(60)

    checker = Hunspell()
    suspicious = lambda ws: suspicious_words(ws, checker)
    stats: Counter[str] = Counter()
    seen: set[str] = set()
    out: dict[str, list[dict]] = {"train": [], "eval": []}
    for entry in client.messages.batches.results(batch_id):
        messages = parse_result(entry)
        if messages is None:
            stats["request-failed"] += 1
            continue
        split, category, _ = entry.custom_id.split("--")
        kind = "negative" if category in NEGATIVE else "hybrid"
        for m in messages:
            text = normalize(m["text"]).strip()
            reason = accept_message(kind, text, suspicious)
            if reason is None and fold_key(text) in seen:
                reason = "duplicate"
            stats[reason or "accepted"] += 1
            if reason is None:
                seen.add(fold_key(text))
                out[split].append({
                    "split": split, "category": category, "kind": kind, "custom_id": entry.custom_id,
                    "text": text, "english_terms": m["english_terms"],
                })
    for split, records in out.items():
        write_jsonl(Path(f"data/synth/{split}.jsonl"), records)
    print(dict(stats))
    return 0


def register(sub) -> None:
    p = sub.add_parser("synth", help="synthetic hybrid corpus via Claude Batch API")
    actions = p.add_subparsers(dest="action", required=True)
    s = actions.add_parser("submit", help="print the cost estimate; submit with --yes")
    s.add_argument("--model", default="claude-opus-5-5", choices=sorted(PRICES))
    s.add_argument("--yes", action="store_true")
    s.set_defaults(func=submit)
    c = actions.add_parser("collect", help="wait for the batch and write data/synth/{train,eval}.jsonl")
    c.set_defaults(func=collect)
