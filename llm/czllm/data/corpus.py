"""Czech source text with correct diacritics. The web is full of Czech typed
without them; such text would teach the model a target without accents, so it
is filtered per document and per line."""

from collections.abc import Iterable, Iterator
from pathlib import Path

from czllm.jsonl import read_jsonl, write_jsonl
from czllm.fold import fold
from czllm.synth.spell import Hunspell
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


def spell_filter(docs: list[dict], checker) -> list[dict]:
    """Drops lines containing a disputed word: one hunspell rejects while an
    accepted spelling with the same fold occurs in the corpus itself. Such a
    line was typed without (some) accents and would be a wrong target.

    Hunspell suggestions would also catch variants absent from the corpus,
    but cost ~50 ms per unknown word — hours for a corpus full of names."""
    vocabulary = sorted({w for d in docs for line in d["lines"] for w in WORD_RE.findall(line)})
    rejected = checker.misspelled(vocabulary)
    accepted_folds = {fold(w).lower() for w in vocabulary if w not in rejected}
    bad = {w for w in rejected if fold(w).lower() in accepted_folds}
    out = []
    for doc in docs:
        lines = [l for l in doc["lines"] if not bad.intersection(WORD_RE.findall(l))]
        if lines:
            out.append({**doc, "lines": lines})
    return out


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
    try:
        n = write_jsonl(args.out, collect(docs, args.source, args.docs))
    finally:
        # Stopping a streaming dataset early leaves its iterator suspended;
        # closing it lets the reader threads finish so the process can exit.
        docs.close()
    print(f"{n} documents -> {args.out}")
    return 0


def run_spellfilter(args) -> int:
    docs = list(read_jsonl(args.path))
    before = sum(len(d["lines"]) for d in docs)
    kept = spell_filter(docs, Hunspell())
    after = sum(len(d["lines"]) for d in kept)
    write_jsonl(args.path, kept)
    print(f"{args.path}: {after}/{before} lines, {len(kept)}/{len(docs)} documents kept")
    return 0


def register(sub) -> None:
    s = sub.add_parser("spellfilter", help="drop corpus lines whose diacritics hunspell disputes (in place)")
    s.add_argument("path", type=Path)
    s.set_defaults(func=run_spellfilter)
    p = sub.add_parser("corpus", help="download and filter a Czech corpus")
    p.add_argument("--source", choices=["fineweb", "wiki"], required=True)
    p.add_argument("--docs", type=int, default=20_000, help="documents to keep")
    p.add_argument("--out", type=Path, required=True)
    p.set_defaults(func=run)
