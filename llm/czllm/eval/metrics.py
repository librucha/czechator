"""Metrics of spec §8.1.

Per-word scoring needs positional alignment, which exists exactly when the
output passes czechator's verification (same length, same fold). Unverified
items count only toward exact/verified; their words are not scored, so DER
describes what czechator would actually accept.
"""

from collections import Counter, defaultdict
from collections.abc import Iterable
from dataclasses import dataclass, fields
from pathlib import Path

from czllm.fold import DIACRITICS, fold
from czllm.jsonl import read_jsonl
from czllm.text import WORD_RE

AMBIGUOUS = Path("data/eval/ambiguous.txt")


@dataclass
class ItemScore:
    exact: bool
    verified: bool
    words: int = 0
    word_errors: int = 0
    missing: int = 0
    spurious: int = 0
    wrong: int = 0
    ambiguous_errors: int = 0


def score_item(source: str, want: str, got: str | None, ambiguous: frozenset[str]) -> ItemScore:
    if got is None:
        return ItemScore(False, False)
    verified = len(got) == len(source) and fold(got) == fold(source)
    score = ItemScore(exact=got == want, verified=verified)
    if not verified or len(want) != len(got):
        return score
    for m in WORD_RE.finditer(want):
        a, b = m.span()
        score.words += 1
        differs = False
        for w, g in zip(want[a:b], got[a:b]):
            if w == g:
                continue
            differs = True
            if w not in DIACRITICS:
                score.spurious += 1
            elif g not in DIACRITICS:
                score.missing += 1
            else:
                score.wrong += 1
        if differs:
            score.word_errors += 1
            if fold(want[a:b]).lower() in ambiguous:
                score.ambiguous_errors += 1
    return score


@dataclass
class SetScore:
    items: int = 0
    exact: int = 0
    verified: int = 0
    format_fail: int = 0
    words: int = 0
    word_errors: int = 0
    missing: int = 0
    spurious: int = 0
    wrong: int = 0
    ambiguous_errors: int = 0
    en_terms: int = 0
    en_untouched: int = 0

    def add(self, item: ItemScore) -> None:
        self.items += 1
        for f in fields(ItemScore):
            setattr(self, f.name, getattr(self, f.name) + int(getattr(item, f.name)))

    def rates(self) -> dict[str, float]:
        div = lambda a, b: a / b if b else 0.0
        return {
            "items": self.items,
            "exact": div(self.exact, self.items),
            "verified": div(self.verified, self.items),
            "format_fail": self.format_fail,
            "der": div(self.word_errors, self.words),
            "missing": self.missing,
            "spurious": self.spurious,
            "wrong": self.wrong,
            "ambiguous_errors": self.ambiguous_errors,
            "en_untouched": div(self.en_untouched, self.en_terms),
        }


def build_ambiguity(lines: Iterable[str], min_count: int = 3) -> frozenset[str]:
    counts = Counter(w.lower() for line in lines for w in WORD_RE.findall(line))
    forms: dict[str, set[str]] = defaultdict(set)
    for word, n in counts.items():
        if n >= min_count:
            forms[fold(word)].add(word)
    return frozenset(k for k, v in forms.items() if len(v) > 1)


def load_ambiguity(path: Path = AMBIGUOUS) -> frozenset[str]:
    return frozenset(path.read_text(encoding="utf-8").split()) if path.exists() else frozenset()


def run(args) -> int:
    lines = (l for p in args.clean for d in read_jsonl(p) for l in d["lines"])
    words = sorted(build_ambiguity(lines))
    AMBIGUOUS.parent.mkdir(parents=True, exist_ok=True)
    AMBIGUOUS.write_text("\n".join(words) + "\n", encoding="utf-8")
    print(f"{len(words)} ambiguous folds -> {AMBIGUOUS}")
    return 0


def register(sub) -> None:
    p = sub.add_parser("ambiguity", help="list folds with more than one Czech spelling")
    p.add_argument("--clean", type=Path, nargs="*", default=[Path("data/clean/fineweb.jsonl"), Path("data/clean/wiki.jsonl")])
    p.set_defaults(func=run)
