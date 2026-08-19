# Quality fixtures

Czech samples with reference output, used to compare models and to tell whether
a prompt change actually helped. Not part of `make test` — these call a live
model, so they are slow and their result depends on which model is installed.

```bash
swift build -c release
Tools/quality.py qwen3:4b-instruct gemma3:4b
```

Two numbers come out and they measure different things:

- **exactly** — the output equals the reference, so the model got the accents right
- **verified** — the tool accepted the result at all, which is what the user feels

A model can score badly on the first and well on the second (it left some accents
out, which verification permits) or well on the first and badly on the second (it
got the accents right but also reworded something, so the whole run was refused).

## Baseline

Measured on 2026-08-19, 22 samples:

| model | exactly | verified |
|---|---|---|
| `qwen3:4b-instruct` | 15/22 | 21/22 |
| `gemma3:4b` | not recommended — swapped whole words (`v úterý` → `ve středu`) |

## Adding a sample

Two files with the same stem: `NN-name.in` and `NN-name.want`. Keep them small
and realistic — a sample that never occurs in a clipboard teaches nothing. The
set deliberately covers the shapes that broke the tool during development: a
non-breaking space, CRLF, JSON with `\uXXXX` escapes, an HTML entity, a URL, and
an English sentence that must come back untouched.
