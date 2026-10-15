"""Frozen eval sets (spec §5.5). Plain-text czechator input is segmented per
line, so an eval record is a text and its non-empty lines are the items."""

import hashlib
import random
from collections.abc import Iterable
from pathlib import Path

from czllm.jsonl import read_jsonl, write_jsonl
from czllm.numbered_list import escape, unescape
from czllm.text import WORD_RE, fold_key, normalize

HOLDOUT_MOD = 50
EVAL_PATHS = {
    "web": Path("data/eval/web.jsonl"),
    "hybrid": Path("data/eval/hybrid.jsonl"),
    "private": Path("data/private/private.jsonl"),
}
REVIEW_TSV = Path("data/eval/hybrid.review.tsv")


def is_heldout(doc_id: str) -> bool:
    return int(hashlib.sha1(doc_id.encode("utf-8")).hexdigest(), 16) % HOLDOUT_MOD == 0


def segments(text: str) -> list[str]:
    return [line for line in text.split("\n") if line.strip()]


def freeze_web(docs: Iterable[dict], per_source: dict[str, int], rng: random.Random, per_doc: int = 2) -> list[dict]:
    pools: dict[str, list[str]] = {s: [] for s in per_source}
    for doc in docs:
        if doc["source"] in pools and is_heldout(doc["doc_id"]):
            lines = list(doc["lines"])
            rng.shuffle(lines)
            pools[doc["source"]].extend(lines[:per_doc])
    out: list[dict] = []
    for source, n in per_source.items():
        pool = pools[source]
        if len(pool) < n:
            raise ValueError(f"{source}: only {len(pool)} held-out lines, need {n}")
        out += [{"source": source, "text": t} for t in rng.sample(pool, n)]
    rng.shuffle(out)
    return [{"id": f"web-{i:04d}", **r} for i, r in enumerate(out)]


def export_review(records: list[dict], path: Path, n: int, rng: random.Random) -> int:
    chosen = rng.sample(records, min(n, len(records)))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write("id\tverdict\ttext\n")
        for r in sorted(chosen, key=lambda r: r["id"]):
            f.write(f"{r['id']}\t\t{escape(r['text'])}\n")
    return len(chosen)


def import_review(path: Path, synth_by_id: dict[str, dict]) -> list[dict]:
    """verdict: "x" drops the row; "ok"/"fix" or an edited text marks it
    reviewed; empty keeps it unreviewed."""
    out = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for row in lines[1:]:
        if not row.strip():
            continue
        rid, verdict, text = row.split("\t", 2)
        verdict = verdict.strip().lower()
        if verdict == "x":
            continue
        source = synth_by_id[rid]
        text = normalize(unescape(text)).strip()
        reviewed = verdict in {"ok", "fix"} or text != source["text"]
        out.append({"id": rid, "text": text, "english_terms": source["english_terms"], "reviewed": reviewed})
    return out


def import_private(paths: Iterable[Path]) -> list[dict]:
    out = []
    for path in paths:
        for raw in Path(path).read_text(encoding="utf-8").splitlines():
            line = normalize(raw).strip()
            if line and WORD_RE.search(line):
                out.append({"id": f"private-{len(out):05d}", "text": line})
    return out


def eval_keys(paths: Iterable[Path]) -> set[str]:
    keys: set[str] = set()
    for path in paths:
        if Path(path).exists():
            for record in read_jsonl(path):
                keys.update(fold_key(s) for s in segments(record["text"]))
    return keys


def _refuse_overwrite(path: Path, force: bool) -> None:
    if path.exists() and not force:
        raise SystemExit(f"{path} exists and is frozen; pass --force to replace it")


def run(args) -> int:
    rng = random.Random(0)
    if args.action == "web":
        _refuse_overwrite(EVAL_PATHS["web"], args.force)
        docs = [d for p in args.clean for d in read_jsonl(p)]
        records = freeze_web(docs, {"fineweb": 400, "wiki": 100}, rng)
        print(f"{write_jsonl(EVAL_PATHS['web'], records)} -> {EVAL_PATHS['web']}")
    elif args.action == "review-export":
        _refuse_overwrite(REVIEW_TSV, args.force)
        synth = [{**r, "id": f"hybrid-{i:04d}"} for i, r in enumerate(read_jsonl(args.synth))]
        print(f"{export_review(synth, REVIEW_TSV, 300, rng)} rows -> {REVIEW_TSV}")
    elif args.action == "review-import":
        synth = {f"hybrid-{i:04d}": r for i, r in enumerate(read_jsonl(args.synth))}
        records = import_review(REVIEW_TSV, synth)
        reviewed = sum(r["reviewed"] for r in records)
        print(f"{write_jsonl(EVAL_PATHS['hybrid'], records)} ({reviewed} reviewed) -> {EVAL_PATHS['hybrid']}")
    elif args.action == "private":
        records = import_private(args.inputs)
        print(f"{write_jsonl(EVAL_PATHS['private'], records)} -> {EVAL_PATHS['private']}")
    return 0


def register(sub) -> None:
    p = sub.add_parser("eval-sets", help="freeze eval sets")
    p.add_argument("action", choices=["web", "review-export", "review-import", "private"])
    p.add_argument("--clean", type=Path, nargs="*", default=[Path("data/clean/fineweb.jsonl"), Path("data/clean/wiki.jsonl")])
    p.add_argument("--synth", type=Path, default=Path("data/synth/eval.jsonl"))
    p.add_argument("--inputs", type=Path, nargs="*", default=sorted(Path("data/private").glob("*.txt")))
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=run)
