"""Phase 0 (spec §7.1): proves a candidate survives the whole pipeline —
train, fuse, GGUF, Ollama, a parsable answer without thinking — before any
real training time is spent on it. Quality is irrelevant here."""

import json
import random
from datetime import datetime
from pathlib import Path

from czllm.eval.ollama import OllamaClient
from czllm.export.gguf import export
from czllm.fold import fold
from czllm.format.augment import AugmentConfig, augment
from czllm.format.contracts import chat_record, systems
from czllm.jsonl import write_jsonl
from czllm.numbered_list import NumberedListError, decode, encode
from czllm.swift_source import REPO_ROOT
from czllm.text import normalize
from czllm.train.run import DEFAULT_SWEEP, RUNS, candidate, fuse, load_sweep, new_run_dir, train

FIXTURES = REPO_ROOT / "Fixtures" / "quality"


def fixture_lines() -> list[str]:
    return [
        normalize(l) for p in sorted(FIXTURES.glob("*.want"))
        for l in p.read_text(encoding="utf-8").splitlines() if l.strip()
    ]


def gate_dataset(out_dir: Path, rng: random.Random, n: int = 400, n_valid: int = 40) -> None:
    lines = fixture_lines()
    contracts = list(systems().values())
    records = []
    for i in range(n + n_valid):
        items = rng.sample(lines, rng.randint(1, 3))
        inputs, targets, _ = augment(items, rng, AugmentConfig())
        records.append(chat_record(contracts[i % 2], inputs, targets))
    write_jsonl(out_dir / "train.jsonl", records[:n])
    write_jsonl(out_dir / "valid.jsonl", records[n:])


def smoke(client, tag: str, system: str, wants: list[str]) -> None:
    result = client.chat(tag, system, encode([fold(w) for w in wants]))
    assert not result.thinking and "<think>" not in result.content, f"thinking in answer: {result.content[:200]!r}"
    try:
        decode(result.content, len(wants))
    except NumberedListError as e:
        raise AssertionError(f"answer does not parse: {e}: {result.content[:200]!r}") from e


def tokens_per_char(hf: str, texts: list[str]) -> float:
    from transformers import AutoTokenizer

    tok = AutoTokenizer.from_pretrained(hf)
    return sum(len(tok.encode(t, add_special_tokens=False)) for t in texts) / sum(len(t) for t in texts)


def run(args) -> int:
    sweep = load_sweep(args.sweep)
    c = candidate(sweep, args.candidate)
    run_dir = new_run_dir(RUNS, f"{c.name}-gate", datetime.now())
    report = {"candidate": c.name, "stages": {}, "tokens_per_char": None}
    wants = fixture_lines()[:3]
    client = OllamaClient()

    def stage(name, fn):
        if any(v != "ok" for v in report["stages"].values()):
            report["stages"][name] = "skipped"
            return
        try:
            fn()
            report["stages"][name] = "ok"
        except Exception as e:  # noqa: BLE001 — the gate records every failure kind
            report["stages"][name] = f"FAIL: {type(e).__name__}: {e}"

    tags: list[str] = []
    stage("dataset", lambda: gate_dataset(run_dir / "data", random.Random(0)))
    stage("train", lambda: train(run_dir, c, sweep.train, run_dir / "data", iters=50, batch_size=4))
    stage("fuse", lambda: fuse(run_dir, c))
    stage("export", lambda: tags.extend(export(run_dir, c, "gate", quants=("Q8_0",), via=args.via)))
    stage("smoke-drop-in", lambda: smoke(client, tags[0], systems()["drop_in"], wants))
    stage("smoke-short", lambda: smoke(client, tags[0], systems()["short"], wants))
    try:
        report["tokens_per_char"] = tokens_per_char(c.hf, fixture_lines())
    except Exception as e:  # noqa: BLE001
        report["stages"]["tokens"] = f"FAIL: {e}"
    (run_dir / "gate.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if all(v == "ok" for v in report["stages"].values()) else 1


def register(sub) -> None:
    p = sub.add_parser("gate", help="phase 0: can this candidate go through the whole pipeline?")
    p.add_argument("--candidate", required=True)
    p.add_argument("--sweep", type=Path, default=DEFAULT_SWEEP)
    p.add_argument("--via", choices=["llama.cpp", "ollama"], default="llama.cpp")
    p.set_defaults(func=run)
