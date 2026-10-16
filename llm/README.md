# czllm — a small model fine-tuned for Czech diacritics

A pipeline that turns Czech text into training data, fine-tunes small
open-weight models with MLX LoRA on Apple Silicon, exports them to GGUF and
Ollama, and measures them against the model czechator uses today.

The result is an Ollama model that czechator can use as a drop-in
replacement: same system prompt, same numbered-list wire format, only
`profiles.<name>.model` changes. It restores diacritics only — the `strict`
correction mode. It does not fix typos, and it adds no safety of its own:
what protects your text is still czechator's verification.

Design: [`docs/superpowers/specs/2026-10-15-diacritics-finetune-design.md`](../docs/superpowers/specs/2026-10-15-diacritics-finetune-design.md).

## Results — iteration 1

Measured on 2026-10-16, M4 Max, against `qwen3:4b-instruct` with czechator's
default prompt. Sets: `web` — 500 held-out lines of FineWeb-2 and Czech
Wikipedia; `hybrid` — 297 generated workplace messages mixing Czech and
English (`mergnul jsem PR`), every one reviewed by hand. Items are lines, as
czechator segments plain text.

| model | set | exact | verified | DER | English kept |
|---|---|---|---|---|---|
| qwen3:4b-instruct (baseline) | web | 13.6 % | 42.2 % | 14.4 % | — |
| qwen3:4b-instruct (baseline) | hybrid | 22.7 % | 52.2 % | 9.0 % | 91.7 % |
| czechator-gemma3-270m:v1-q8_0 | web | 36.6 % | 73.0 % | 4.7 % | — |
| czechator-gemma3-270m:v1-q8_0 | hybrid | 76.6 % | 94.9 % | 2.1 % | 98.1 % |

- **exact** — the line comes back byte-identical to the reference.
- **verified** — it passes czechator's check, `fold(output) == fold(input)`;
  this is what czechator would accept.
- **DER** — share of words with a diacritic error, over verified lines only.
- **English kept** — English terms of the hybrid set left unchanged.

Latency for a ~300-character message, warm: baseline p50 1.88–2.71 s, the
270M model 0.52 s (cold start 0.99 s against ~6 s).

`czechator quality --corrections strict`, built-in `clean` set: the 270M model
gets **18/23 exact and 23/23 verified**; the baseline, measured the same day,
15/23 and 22/23. The iteration goal of 20/23 exact was not reached.

Q4_K_M costs the 270M model 3–7 points of accuracy and saves no time; use
Q8_0. The short contract (no long system prompt) measured the same as the
drop-in one, so czechator needs no change to use the model.

### Candidates dropped

- **Qwen3.5-0.8B / 2B** passed the export gate but cannot be trained here at
  a usable rate: mlx-lm 0.32 runs Qwen3.5's gated delta layers through a
  Python per-token loop while training (`models/qwen3_5.py`,
  `use_kernel=not self.training`), about 26 trained tokens/s on 0.8B.

## Use the model in czechator

```yaml
profiles:
  finetuned:
    provider: ollama
    model: czechator-gemma3-270m:v1-q8_0
    corrections: strict
```

The model exists only in the Ollama instance it was created in. To move it,
copy `runs/<run>/gguf/model-q8_0.gguf` and its `Modelfile.q8_0`, then
`ollama create czechator-gemma3-270m:v1-q8_0 -f Modelfile.q8_0`.

## Reproduce

Prerequisites: macOS on Apple Silicon, Ollama, and

```bash
brew install uv hunspell
cd llm
uv sync
make dict          # LibreOffice cs_CZ dictionary into data/dict
make llamacpp      # llama.cpp b11429 converter with its own venv
uv run hf auth login   # Gemma 3 is gated: accept its licence first
```

The pipeline, in order. Every step reads and writes files under `data/` and
`runs/`, so any step can be rerun alone.

```bash
uv run czllm corpus --source fineweb --docs 20000 --out data/clean/fineweb.jsonl
uv run czllm corpus --source wiki --docs 6000 --out data/clean/wiki.jsonl
uv run czllm spellfilter data/clean/fineweb.jsonl
uv run czllm spellfilter data/clean/wiki.jsonl
uv run czllm ambiguity
uv run czllm eval-sets web                       # frozen; --force to replace

uv run czllm synth submit                        # dry run: request count and cost
uv run --env-file .env czllm synth submit --yes  # spends money, see below
uv run --env-file .env czllm synth collect
uv run czllm eval-sets review-export             # hand review, then:
uv run czllm eval-sets review-import

uv run czllm build --id s01 --total 38875
uv run czllm gate --candidate gemma3-270m        # can it go through the whole pipeline?
uv run czllm train --candidate gemma3-270m       # prints the run directory
uv run czllm export --run runs/<run> --candidate gemma3-270m --version 1
uv run czllm eval --model czechator-gemma3-270m:v1-q8_0 --out runs/<run>/eval.json
uv run czllm report --inputs runs/baseline/*.json runs/*/eval-*.json --out runs/sweep.md
```

`make test` runs the unit tests. Run every command from `llm/`: paths are
relative to it.

`.env` holds `ANTHROPIC_API_KEY` and, for an organisation-wide key,
`ANTHROPIC_WORKSPACE_ID`. It is git-ignored. The synthetic corpus — 804
requests on `claude-opus-5-5` through the Batch API — is estimated at no less
than 25.57 USD; thinking tokens come on top and are not in the estimate.

## How it works, briefly

- **Targets** are Czech lines with correct diacritics; **inputs** are the same
  lines with all, some or none of the accents removed. Every pair satisfies
  `len(input) == len(target)` and `fold(input) == fold(target)`, checked over
  the whole set before training.
- **Shared with czechator by construction:** the fold table, the fragile
  whitespace set and the default system prompt are read from the Swift
  sources; the numbered-list format is a tested port.
- **Corpus cleaning:** documents typed without diacritics are dropped; a line
  is dropped when hunspell rejects one of its words and a spelling with the
  same fold occurs in the corpus.
- **Export:** `mlx_lm.fuse` writes MLX layout, which the GGUF converter
  misreads; the export takes the base checkpoint and replaces only the
  LoRA-adapted linear weights.
- **Training:** micro-batches of 4 with gradient accumulation 4. Gemma's
  262k-token vocabulary makes logits for a full batch of 16 too large for GPU
  memory.

## Known limitations

- **Ambiguous words are guesses.** `byt`/`být`, `pani`/`paní`, `rad`/`rád`/`řád`
  fold to the same letters; only context decides, and the small model gets
  them wrong often (the largest error class on `web`). czechator's
  verification cannot catch these — both spellings fold identically.
- **Web text is the weak spot.** On news and encyclopedia text the 270M model
  is exact on about a third of lines and verified on three quarters; a
  refused line costs a refusal, not a corruption.
- **The hybrid eval set is synthetic.** It was generated by Claude and reviewed
  by one person; it measures one style of developer Czech.
- **No private eval set.** Iteration 1 was not measured on the author's own
  texts.
- **The spell filter is only as wide as the corpus.** A wrongly accented word
  whose correct spelling never occurs in the corpus passes.
- **Training data is mostly web text** filtered by heuristics; some spam and
  some lines with wrong accents remain.
