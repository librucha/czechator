# Quality fixtures

Czech samples with reference output, used to compare models and to tell whether
a prompt change actually helped. Not part of `make test` — these call a live
model, so they are slow and their result depends on which model is installed.

```bash
make install-cli
czechator quality --profile local
czechator quality --profile local --model gemma3:4b
czechator quality --profile local --letter-case segmentStart
czechator quality --profile local --color always | less -R
```

A run scoped to just this directory, `--profile local` pointed at
`qwen3:4b-instruct`, `--corrections strict`:

```
== quality  (23 vzorků)
local · qwen3:4b-instruct · Přísný
  přesně           15/23   65.2% ████████░░░░
  přes verifikaci  22/23   95.7% ███████████░
  odmítnuto       1/23
    ~    03-termin
         chtěl:  "Termín dodání je příští týden."
         dostal: "Termin dodání je příští týden."
    ~    04-dotazy
         chtěl:  "Pokud budete mít dotazy, ozvěte se."
         dostal: "Pokud budete mít dotazy, ozvete se."
    STOP 06-podekovani
    ~    10-mala-pismena
         chtěl:  "nezapomeň prosím na ten úkol"
         dostal: "nezapomen prosím na ten úkol"
    ~    11-nbsp
         chtěl:  "Školení proběhne v úterý a potrvá do čtvrtka."
         dostal: "Skolení proběhne v úterý a potrvá do čtvrtka."
    ~    17-html-nbsp
         chtěl:  "<p>Školení proběhne v&nbsp;úterý.</p>"
         dostal: "<p>Skolení proběhne v&nbsp;úterý.</p>"
    ~    18-url
         chtěl:  "Podrobnosti najdeš na https://example.cz/skoleni v sekci termíny."
         dostal: "Podrobnosti najdeš na https://example.cz/skoleni v sekci terminy."
    ~    23-e_s_hackem
         chtěl:  "Někde se to musí přece dodělat!"
         dostal: "Nekde se to musí přece dodělat!"
```

Captured 2026-08-25 against a local `qwen3:4b-instruct`, `--fixtures-dir
Fixtures/quality` so the run only touches this directory's 23 samples. `~`
means the sample was accepted but did not match exactly (shown with the diff);
`STOP` means the whole run was refused outright, so nothing reached the
clipboard for that sample.

Colour is dropped when the output is not a terminal, and honours `NO_COLOR`.

The fixtures are written for `letterCase: preserve`. Under a looser policy the
model may legitimately change case, so `--letter-case` relaxes the comparison the
same way the tool relaxes verification — otherwise every capitalized sentence
start would read as a failure.

Three numbers come out and they measure different things:

- **exactly** — the output equals the reference, so the model got the accents right
- **verified** — the tool accepted the result at all (including a partial fix
  within its edit budget), which is what the user feels
- **refused** — the tool rejected the result outright (edit budget exceeded or
  hard verification failure), so nothing reached the clipboard for that sample

A model can score badly on the first and well on the second (it left some accents
out, which verification permits) or well on the first and badly on the second (it
got the accents right but also reworded something, so the whole run was refused).

## Baseline

Measured on 2026-08-19, 23 samples, `qwen3:4b-instruct`. These numbers were
produced by the old Python harness (`Tools/quality.py`, since replaced by
`czechator quality`) — they are still valid measurements of the *model*, not of
the tool that measured it:

| `letterCase` | exactly | verified |
|---|---|---|
| `preserve` | 15/23 | 22/23 |
| `segmentStart` | 15/23 | 22/23 |
| `model` | 15/23 | 22/23 |

The policy makes no difference on this set, which is the point: capitalization is
handled deterministically now, so it is no longer a source of refusals.

`gemma3:4b` is not recommended — it swapped whole words (`v úterý` → `ve středu`).

## Where the model is weak

The misses are all the same shape: accents the model simply does not add, most
often **`ě`** (`Nekde` stays `Nekde`, `ozvete` stays `ozvete`) and a lone missing
accent in an otherwise correct sentence. Those pass verification — a partial
correction is allowed — so they cost accuracy, not refusals. That is the obvious
target for a prompt or a bigger model.

## Adding a sample

Two files with the same stem: `NN-name.in` and `NN-name.want`. Keep them small
and realistic — a sample that never occurs in a clipboard teaches nothing. The
set deliberately covers the shapes that broke the tool during development: a
non-breaking space, CRLF, JSON with `\uXXXX` escapes, an HTML entity, a URL, and
an English sentence that must come back untouched.

This set has no deliberate errors in the input beyond missing diacritics — see
`Fixtures/typos/` for the sibling set that measures how well typos actually get
fixed.
