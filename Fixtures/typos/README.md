# Typo fixtures

Czech samples with **real typos** in the input, not just missing diacritics.
Where `Fixtures/quality/` has correct Czech that only needs accents — so there
is nothing to fix beyond that, and it measures how often a tolerant mode
touches text that was already fine — this set measures how many of its actual
mistakes a correction mode fixes.

```bash
make install-cli
czechator quality --profile local --fixtures-dir Fixtures/typos
```

Each sample carries **one kind of mistake**, not several stacked together:
swapped letters, a missing letter, a doubled letter, a misplaced space, `i`/`y`
confusion, `s`/`z` confusion, a missing comma, a stray space before a period, a
missing capital, and the same set of mistakes inside JSON and HTML. Mixing
mistakes in one sample would hide which kind the model actually struggles
with — the table would show one failure where there are really two.

`12-bez-chyby` is deliberately the one sample with **no typo at all**, only
missing diacritics. Without it, a model that "corrects" everything it sees —
including text that needed no correction — would score a perfect 11/11 on the
other samples and look flawless. `12-bez-chyby` is what would catch it.

A high **refused** count for this set under `strict` correction is the
**correct** result, not a failure: `strict` requires an exact match after
verification, and the model cannot fix a genuine typo and still reproduce the
reference character-for-character. Use `proofread` or `all` to see how many of
these a looser mode actually catches.

## Adding a sample

Two files with the same stem: `NN-name.in` and `NN-name.want`, with **no
trailing newline** — same convention as `Fixtures/quality/`. Keep to one
mistake per sample so it stays clear what the numbers are measuring.
