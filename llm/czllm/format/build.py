"""Assembles train/valid JSONL from corpus documents and synthetic messages.

A unit is what czechator would send in one clipboard: consecutive lines of one
document, or one generated message split into lines. Each unit becomes one
chat record in one of the two contracts.
"""

import hashlib
import json
import random
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path

from czllm.eval.sets import EVAL_PATHS, eval_keys, is_heldout, require_eval_sets, segments
from czllm.format.augment import AugmentConfig, augment
from czllm.format.contracts import MAX_BATCH_CHARS, chat_record, systems
from czllm.format.validate import DatasetError, validate_file
from czllm.jsonl import read_jsonl, write_jsonl
from czllm.text import fold_key


@dataclass(frozen=True)
class BuildConfig:
    total: int = 40_000
    valid: int = 1_000
    mix: dict = field(default_factory=lambda: {"fineweb": 0.55, "wiki": 0.15, "hybrid": 0.20, "negative": 0.10})
    drop_in_share: float = 0.6
    budgets: tuple = (80, 200, 400, 800, MAX_BATCH_CHARS)
    budget_weights: tuple = (0.25, 0.30, 0.25, 0.12, 0.08)
    join_newline: float = 0.05
    augment: AugmentConfig = AugmentConfig()


class InsufficientData(ValueError):
    pass


def chunk_lines(lines: list[str], rng: random.Random, cfg: BuildConfig) -> list[list[str]]:
    chunks: list[list[str]] = []
    current: list[str] = []
    size = 0
    budget = rng.choices(cfg.budgets, weights=cfg.budget_weights)[0]
    for line in lines:
        if current and size + len(line) > budget:
            chunks.append(current)
            current, size = [], 0
            budget = rng.choices(cfg.budgets, weights=cfg.budget_weights)[0]
        current.append(line)
        size += len(line)
    if current:
        chunks.append(current)
    return [c for c in chunks if sum(map(len, c)) <= MAX_BATCH_CHARS]


def doc_units(docs, excluded: set[str], rng: random.Random, cfg: BuildConfig) -> list[list[str]]:
    units = []
    for doc in docs:
        if is_heldout(doc["doc_id"]):
            continue
        lines = [l for l in doc["lines"] if fold_key(l) not in excluded]
        units += chunk_lines(lines, rng, cfg)
    return units


def synth_units(records, excluded: set[str]) -> list[list[str]]:
    units = []
    for record in records:
        lines = segments(record["text"])
        if lines and not any(fold_key(l) in excluded for l in lines) and sum(map(len, lines)) <= MAX_BATCH_CHARS:
            units.append(lines)
    return units


def join_newlines(items: list[str], rng: random.Random, p: float) -> list[str]:
    """Some segments (JSON or HTML text nodes) carry a real newline inside."""
    out: list[str] = []
    i = 0
    while i < len(items):
        if i + 1 < len(items) and rng.random() < p:
            out.append(items[i] + "\n" + items[i + 1])
            i += 2
        else:
            out.append(items[i])
            i += 1
    return out


def build(units_by_source: dict[str, list[list[str]]], cfg: BuildConfig, rng: random.Random):
    wanted = cfg.total + cfg.valid
    contracts = systems()
    chosen: list[tuple[str, list[str]]] = []
    for source, share in cfg.mix.items():
        need = round(share * wanted)
        have = units_by_source.get(source, [])
        if len(have) < need:
            raise InsufficientData(f"{source}: {len(have)} units, need {need}")
        chosen += [(source, u) for u in rng.sample(have, need)]
    rng.shuffle(chosen)

    stats = {"source": Counter(), "mode": Counter(), "contract": Counter()}
    records = []
    for source, unit in chosen:
        items = join_newlines(unit, rng, cfg.join_newline)
        if sum(map(len, items)) > MAX_BATCH_CHARS:   # each join adds a "\n"
            items = unit
        inputs, targets, mode = augment(items, rng, cfg.augment)
        contract = "drop_in" if rng.random() < cfg.drop_in_share else "short"
        records.append(chat_record(contracts[contract], inputs, targets))
        stats["source"][source] += 1
        stats["mode"][mode] += 1
        stats["contract"][contract] += 1
    stats = {k: dict(v) for k, v in stats.items()}
    return records[cfg.valid :][: cfg.total], records[: cfg.valid], stats


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def config_from_args(args) -> BuildConfig:
    """Only the size is adjustable: the mix is the spec's, and a short source
    is answered by fewer examples overall, not by a different mix."""
    return BuildConfig(total=args.total) if args.total else BuildConfig()


def run_build(args) -> int:
    cfg = config_from_args(args)
    rng = random.Random(0)
    require_eval_sets()
    excluded = eval_keys(EVAL_PATHS.values())
    synth = list(read_jsonl(Path("data/synth/train.jsonl")))
    units = {
        "fineweb": doc_units(read_jsonl(Path("data/clean/fineweb.jsonl")), excluded, rng, cfg),
        "wiki": doc_units(read_jsonl(Path("data/clean/wiki.jsonl")), excluded, rng, cfg),
        "hybrid": synth_units([r for r in synth if r["kind"] == "hybrid"], excluded),
        "negative": synth_units([r for r in synth if r["kind"] == "negative"], excluded),
    }
    print({k: len(v) for k, v in units.items()})
    train, valid, stats = build(units, cfg, rng)
    out = Path("data/sets") / args.id
    write_jsonl(out / "train.jsonl", train)
    write_jsonl(out / "valid.jsonl", valid)
    manifest = {
        "config": json.loads(json.dumps(asdict(cfg), default=str)),
        "stats": stats,
        "eval_keys": len(excluded),
        "files": {n: _sha256(out / n) for n in ("train.jsonl", "valid.jsonl")},
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False))
    return run_validate(args)


def run_validate(args) -> int:
    out = Path("data/sets") / args.id
    known = set(systems().values())
    require_eval_sets()
    excluded = eval_keys(EVAL_PATHS.values())
    try:
        for name in ("train.jsonl", "valid.jsonl"):
            print(f"{name}: {validate_file(out / name, known, excluded)} records OK")
    except DatasetError as e:
        print(f"INVALID: {e}")
        return 1
    return 0


def register(sub) -> None:
    b = sub.add_parser("build", help="assemble data/sets/<id> and validate it")
    b.add_argument("--id", required=True)
    b.add_argument("--total", type=int, help="training examples (default 40000); the mix stays fixed")
    b.set_defaults(func=run_build)
    v = sub.add_parser("validate", help="validate data/sets/<id>")
    v.add_argument("--id", required=True)
    v.set_defaults(func=run_validate)
