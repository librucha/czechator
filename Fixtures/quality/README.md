# Quality fixtures

Czech samples with reference output, used to compare models and to tell whether
a prompt change actually helped. Not part of `make test` — these call a live
model, so they are slow and their result depends on which model is installed.

```bash
swift build -c release
Tools/quality.py qwen3:4b-instruct gemma3:4b
Tools/quality.py --letter-case segmentStart qwen3:4b-instruct
Tools/quality.py --color always qwen3:4b-instruct | less -R
```

It ends with one row per model, coloured worst-to-best so a bad run is obvious
without reading the numbers:

```
                    přesně                        přes verifikaci
──────────────────────────────────────────────────────────────────
qwen3:4b-instruct    15/23   65.2%  ████████░░░░   22/23   95.7%  ███████████░
gemma3:4b            12/23   52.2%  ██████░░░░░░   15/23   65.2%  ████████░░░░
```

Colour is dropped when the output is not a terminal, and honours `NO_COLOR`.

The fixtures are written for `letterCase: preserve`. Under a looser policy the
model may legitimately change case, so `--letter-case` relaxes the comparison the
same way the tool relaxes verification — otherwise every capitalized sentence
start would read as a failure.

Two numbers come out and they measure different things:

- **exactly** — the output equals the reference, so the model got the accents right
- **verified** — the tool accepted the result at all, which is what the user feels

A model can score badly on the first and well on the second (it left some accents
out, which verification permits) or well on the first and badly on the second (it
got the accents right but also reworded something, so the whole run was refused).

## Baseline

Measured on 2026-08-19, 23 samples, `qwen3:4b-instruct`:

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
