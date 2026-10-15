"""Runs an eval set through a model exactly as czechator would: each record is
one clipboard, its lines are segments, segments are packed greedily up to
1500 characters and sent as one numbered list."""

import json
import statistics
from pathlib import Path

from czllm.eval.metrics import SetScore, load_ambiguity, score_item
from czllm.eval.ollama import OllamaClient
from czllm.eval.sets import EVAL_PATHS, segments
from czllm.fold import fold
from czllm.format.contracts import MAX_BATCH_CHARS, systems
from czllm.jsonl import read_jsonl
from czllm.numbered_list import NumberedListError, decode, encode

MAX_FAILURES = 30


def batches(texts: list[str], max_chars: int = MAX_BATCH_CHARS) -> list[list[int]]:
    result: list[list[int]] = []
    current: list[int] = []
    size = 0
    for i, text in enumerate(texts):
        if current and size + len(text) > max_chars:
            result.append(current)
            current, size = [], 0
        current.append(i)
        size += len(text)
    if current:
        result.append(current)
    return result


def run_set(client, model: str, system: str, records: list[dict], ambiguous: frozenset[str],
            max_chars: int = MAX_BATCH_CHARS) -> tuple[SetScore, list[dict]]:
    score = SetScore()
    failures: list[dict] = []
    for record in records:
        wants = segments(record["text"])
        inputs = [fold(w) for w in wants]
        gots: list[str | None] = [None] * len(wants)
        for batch in batches(inputs, max_chars):
            result = client.chat(model, system, encode([inputs[i] for i in batch]))
            if "<think>" in result.content or result.thinking:
                score.format_fail += len(batch)
                continue
            try:
                decoded = decode(result.content, len(batch))
            except NumberedListError:
                score.format_fail += len(batch)
                continue
            for i, got in zip(batch, decoded):
                gots[i] = got
        for source, want, got in zip(inputs, wants, gots):
            score.add(score_item(source, want, got, ambiguous))
            if got != want and len(failures) < MAX_FAILURES:
                failures.append({"id": record["id"], "want": want, "got": got})
        terms = record.get("english_terms", [])
        joined = "\n".join(g or "" for g in gots)
        score.en_terms += len(terms)
        score.en_untouched += sum(term in joined for term in terms)
    return score, failures


def latency_texts(records: list[dict], n: int = 20, target: int = 300) -> list[str]:
    texts = [s for r in records for s in segments(r["text"])]
    return sorted(texts, key=lambda t: abs(len(t) - target))[:n]


def latency(client, model: str, system: str, texts: list[str]) -> dict:
    client.unload(model)
    cold = client.chat(model, system, encode([fold(texts[0])])).wall_s
    runs = [client.chat(model, system, encode([fold(t)])) for t in texts]
    walls = sorted(r.wall_s for r in runs)
    eval_s = sum(r.eval_s for r in runs)
    return {
        "cold_s": cold,
        "p50_s": statistics.median(walls),
        "p95_s": statistics.quantiles(walls, n=20)[18] if len(walls) >= 2 else walls[0],
        "tokens_per_s": sum(r.eval_tokens for r in runs) / eval_s if eval_s else 0.0,
    }


def run(args) -> int:
    client = OllamaClient()
    system = systems()[args.contract]
    ambiguous = load_ambiguity()
    result = {"model": args.model, "contract": args.contract, "sets": {}, "failures": {}}
    for name in args.sets.split(","):
        path = EVAL_PATHS[name]
        if not path.exists():
            print(f"skip {name}: {path} missing")
            continue
        score, failures = run_set(client, args.model, system, list(read_jsonl(path)), ambiguous)
        result["sets"][name] = score.rates()
        result["failures"][name] = failures
        print(name, json.dumps(score.rates()))
    result["latency"] = latency(client, args.model, system, latency_texts(list(read_jsonl(EVAL_PATHS["web"]))))
    print("latency", json.dumps(result["latency"]))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0


def register(sub) -> None:
    p = sub.add_parser("eval", help="evaluate an Ollama model on the frozen sets")
    p.add_argument("--model", required=True)
    p.add_argument("--contract", choices=["drop_in", "short"], default="drop_in")
    p.add_argument("--sets", default="web,hybrid,private")
    p.add_argument("--out", type=Path, required=True)
    p.set_defaults(func=run)
