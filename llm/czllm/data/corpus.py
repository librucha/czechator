"""Czech source text with correct diacritics. The web is full of Czech typed
without them; such text would teach the model a target without accents, so it
is filtered per document and per line."""

from collections.abc import Iterable, Iterator
from pathlib import Path

from czllm.jsonl import write_jsonl
from czllm.text import WORD_RE, diacritic_word_ratio, fold_key, normalize, words

MIN_DOC_RATIO = 0.25
MIN_LINE_RATIO = 0.1
MIN_WORDS_FOR_LINE_CHECK = 4
MIN_LINE, MAX_LINE = 20, 600


def keep_document(text: str) -> bool:
    return diacritic_word_ratio(text) >= MIN_DOC_RATIO


def document_lines(text: str) -> list[str]:
    out = []
    for raw in text.splitlines():
        line = normalize(raw).strip()
        if not (MIN_LINE <= len(line) <= MAX_LINE) or not WORD_RE.search(line):
            continue
        if len(words(line)) >= MIN_WORDS_FOR_LINE_CHECK and diacritic_word_ratio(line) < MIN_LINE_RATIO:
            continue
        out.append(line)
    return out


def collect(docs: Iterable[tuple[str, str]], source: str, limit: int) -> Iterator[dict]:
    seen: set[str] = set()
    kept = 0
    for doc_id, text in docs:
        if kept >= limit:
            return
        if not keep_document(text):
            continue
        lines = []
        for line in document_lines(text):
            key = fold_key(line)
            if key not in seen:
                seen.add(key)
                lines.append(line)
        if lines:
            kept += 1
            yield {"source": source, "doc_id": str(doc_id), "lines": lines}


def fineweb_docs(min_language_score: float = 0.9) -> Iterator[tuple[str, str]]:
    from datasets import load_dataset

    ds = load_dataset("HuggingFaceFW/fineweb-2", name="ces_Latn", split="train", streaming=True)
    for row in ds.shuffle(seed=0, buffer_size=10_000):
        if row.get("language_score", 1.0) >= min_language_score:
            yield row["id"], row["text"]


def wiki_docs() -> Iterator[tuple[str, str]]:
    from datasets import load_dataset

    ds = load_dataset("wikimedia/wikipedia", "20231101.cs", split="train", streaming=True)
    for row in ds.shuffle(seed=0, buffer_size=10_000):
        yield row["id"], row["text"]


def run(args) -> int:
    docs = fineweb_docs() if args.source == "fineweb" else wiki_docs()
    n = write_jsonl(args.out, collect(docs, args.source, args.docs))
    print(f"{n} documents -> {args.out}")
    return 0


def register(sub) -> None:
    p = sub.add_parser("corpus", help="download and filter a Czech corpus")
    p.add_argument("--source", choices=["fineweb", "wiki"], required=True)
    p.add_argument("--docs", type=int, default=20_000, help="documents to keep")
    p.add_argument("--out", type=Path, required=True)
    p.set_defaults(func=run)
