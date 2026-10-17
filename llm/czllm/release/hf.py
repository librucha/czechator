"""Stages and publishes a fine-tuned model as a Hugging Face GGUF repository.

Ollama pulls such a repo directly (`ollama pull hf.co/<repo>:Q8_0`) and reads
three optional files from it: `template` (a Go template), `system` and
`params` (JSON). Shipping them carries the exact chat template, stop tokens
and settings of the local Modelfile; without them Ollama would guess a
template from the GGUF metadata.

`stage` only writes a local folder. `publish` uploads it, and without --yes
it only lists what would be sent: a public upload cannot be taken back.
"""

import json
import os
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path

import yaml

GEMMA_NOTICE = "Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms"
RELEASE_DIR = Path("release")


def parse_modelfile(text: str) -> dict:
    def block(name: str) -> str:
        m = re.search(rf'^{name} """(.*?)"""', text, flags=re.MULTILINE | re.DOTALL)
        if not m:
            raise ValueError(f"Modelfile has no {name}")
        return m.group(1)

    params: dict = {}
    for key, raw in re.findall(r"^PARAMETER (\S+) (.+)$", text, flags=re.MULTILINE):
        raw = raw.strip()
        value = raw[1:-1] if raw.startswith('"') and raw.endswith('"') else (
            int(raw) if re.fullmatch(r"-?\d+", raw) else float(raw))
        if key == "stop":
            params.setdefault("stop", []).append(value)
        else:
            params[key] = value
    renderer = re.search(r"^RENDERER (\S+)\s*$", text, flags=re.MULTILINE)
    return {"template": block("TEMPLATE"), "system": block("SYSTEM"), "params": params,
            "renderer": renderer.group(1) if renderer else None}


# Go templates reproducing what an Ollama RENDERER produces, for repos pulled
# from the Hub, which can carry a `template` file but no RENDERER. Each must
# match the chat template the model was trained with (transformers'
# apply_chat_template), turn for turn.
GO_TEMPLATES = {
    "gemma4": (
        """{{- range $i, $_ := .Messages }}
{{- $last := eq (len (slice $.Messages $i)) 1 }}
{{- if eq .Role "system" }}<|turn>system
{{ .Content }}<turn|>
{{ else if eq .Role "user" }}<|turn>user
{{ .Content }}<turn|>
{{ if $last }}<|turn>model
{{ end }}
{{- else if eq .Role "assistant" }}<|turn>model
{{ .Content }}{{ if not $last }}<turn|>
{{ end }}
{{- end }}
{{- end }}""",
        ["<turn|>"],
    ),
}


def hub_template(modelfile: dict) -> tuple[str, list[str]]:
    renderer = modelfile["renderer"]
    if renderer is None:
        return modelfile["template"], modelfile["params"].get("stop", [])
    if renderer not in GO_TEMPLATES:
        raise SystemExit(f"Ollama renders this model with RENDERER {renderer}, and no Go template for it is "
                         "known; add one to GO_TEMPLATES before publishing")
    return GO_TEMPLATES[renderer]


def base_license(readme: str) -> tuple[str, str | None]:
    front = readme.split("---")[1] if readme.startswith("---") else ""
    meta = yaml.safe_load(front) or {}
    return meta.get("license", "other"), meta.get("license_link")


def gguf_name(repo: str, quant: str) -> str:
    stem = repo.split("/")[-1].removesuffix("-GGUF")
    return f"{stem}-{quant.upper()}.gguf"


@dataclass
class CardInfo:
    repo: str
    base_model: str
    license: str
    license_link: str | None
    quants: list[str]
    system: str
    results: list[dict]
    quality: tuple[int, int, int] | None
    lora: dict = field(default_factory=dict)
    train_examples: int | None = None


def _pct(x: float) -> str:
    return f"{x * 100:.1f} %"


def render_card(info: CardInfo) -> str:
    front = {
        "license": info.license,
        **({"license_link": info.license_link} if info.license_link else {}),
        "base_model": info.base_model,
        "base_model_relation": "finetune",
        "language": ["cs", "en"],
        "library_name": "gguf",
        "pipeline_tag": "text-generation",
        "tags": ["czech", "diacritics", "gguf", "ollama", "czechator"],
        "datasets": ["HuggingFaceFW/fineweb-2", "wikimedia/wikipedia"],
    }
    name = info.repo.split("/")[-1]
    quant = info.quants[0]
    rows = []
    for r in info.results:
        for set_name, s in r["sets"].items():
            rows.append(f"| {r['label']} | {set_name} | {s['items']} | {_pct(s['exact'])} | "
                        f"{_pct(s['verified'])} | {_pct(s['der'])} |")
    latency = [f"- {r['label']}: p50 {r['latency']['p50_s']:.2f} s, cold start {r['latency']['cold_s']:.2f} s"
               for r in info.results if r.get("latency")]
    quality = (f"\nOn czechator's built-in `clean` set (`czechator quality --corrections strict`) it gets "
               f"**{info.quality[0]}/{info.quality[2]} exact and {info.quality[1]}/{info.quality[2]} verified**.\n"
               if info.quality else "")
    training = ", ".join(f"{k} {v}" for k, v in info.lora.items())
    examples = f"{info.train_examples:,}".replace(",", " ") if info.train_examples else "about 40 000"
    notice = f"\n{GEMMA_NOTICE}. See `NOTICE` and `LICENSE`.\n" if info.license == "gemma" else ""

    return f"""---
{yaml.safe_dump(front, sort_keys=False, allow_unicode=True).strip()}
---

# {name}

A fine-tune of [`{info.base_model}`](https://huggingface.co/{info.base_model}) that restores
Czech diacritics — `Prilis zlutoucky kun` becomes `Příliš žluťoučký kůň` — and nothing else.
It was trained for [czechator](https://github.com/librucha/czechator), a macOS tool that fixes
the clipboard, and it keeps English terms in mixed developer Czech (`mergnul jsem PR do mainu`)
untouched.

## Use it with Ollama

```sh
ollama pull hf.co/{info.repo}:{quant}
```

The repo ships Ollama's `template`, `system` and `params` (temperature 0, `num_ctx` 4096), so
nothing else needs configuring. In czechator:

```yaml
profiles:
  local:
    kind: ollama
    endpoint: http://localhost:11434
    model: hf.co/{info.repo}:{quant}
    temperature: 0
    timeoutSeconds: 30
    corrections: strict
```

## Input contract

The model expects a numbered list, one segment per item, and answers with the same list:

```
system: {info.system}
user:   1. Prilis zlutoucky kun upel dabelske ody.
        2. mergnul jsem PR, zitra to pushnu na staging
model:  1. Příliš žluťoučký kůň úpěl ďábelské ódy.
        2. mergnul jsem PR, zítra to pushnu na staging
```

It was also trained with czechator's longer default system prompt, so czechator needs no change.
A real newline inside an item is written as `\\n`, a backslash as `\\\\`.

## Results

Measured through Ollama on an M4 Max. `web`: 500 held-out lines of FineWeb-2 and Czech
Wikipedia. `hybrid`: 297 generated workplace messages mixing Czech and English, each reviewed by
hand. **exact** — the line comes back identical to the reference; **verified** — only diacritics
changed, which is what czechator accepts; **DER** — share of words with a diacritic error, over
verified lines.

| model | set | lines | exact | verified | DER |
|---|---|---|---|---|---|
{chr(10).join(rows)}

Latency for a ~300-character message:

{chr(10).join(latency)}
{quality}
## Known limitations

- **Words that differ only in diacritics are guessed from context** (`byt`/`být`, `pani`/`paní`,
  `rad`/`rád`/`řád`). This is the largest error class, and a verifier comparing letters without
  diacritics cannot catch it.
- **Proper names are often wrong** (`Ahmadínežád`), especially foreign ones.
- **Diacritics only.** It does not fix typos, case or punctuation, and a prompt asking for that
  is outside what it was trained on.
- **One domain of hybrid Czech.** The mixed-language data is synthetic developer and office
  writing; other registers are covered only by web text.
- **No safety of its own.** Use it behind a check such as czechator's verification.

## Training

LoRA on all linear layers with [mlx-lm](https://github.com/ml-explore/mlx-lm) ({training}),
one epoch over {examples} examples, prompt masked so only the answer is learned. Inputs are
correct Czech with all, some or none of the diacritics removed, with occasional all-lowercase and
all-caps items; every pair keeps length and letters identical apart from diacritics. Pipeline and
full write-up: [`llm/`](https://github.com/librucha/czechator/tree/master/llm).

**Data and attribution:**

- [FineWeb-2](https://huggingface.co/datasets/HuggingFaceFW/fineweb-2) `ces_Latn` — ODC-By 1.0.
- [Wikipedia](https://huggingface.co/datasets/wikimedia/wikipedia) `20231101.cs` — CC BY-SA 4.0,
  © Wikipedia contributors.
- About 13 500 synthetic workplace messages generated with Anthropic's Claude.

## Licence

Derived from `{info.base_model}` under its licence (`{info.license}`); see `LICENSE`.
This model was modified from the original by fine-tuning.{notice}
"""


def _results(run: Path, baseline: Path | None, quants: list[str]) -> list[dict]:
    out = []
    for path in sorted(run.glob("eval-*.json")):
        r = json.loads(path.read_text(encoding="utf-8"))
        quant = path.stem.split("-")[1].upper()
        if quant not in quants:
            continue
        contract = "short prompt" if r["contract"] == "short" else "czechator prompt"
        out.append({"label": f"this model, {quant}, {contract}", "sets": r["sets"], "latency": r.get("latency")})
    if baseline:
        r = json.loads(baseline.read_text(encoding="utf-8"))
        out.append({"label": f"{r['model']} (czechator's default)", "sets": r["sets"], "latency": r.get("latency")})
    return out


def _place(src: Path, dst: Path) -> None:
    """Hard link: the GGUF can be several GB and must not be copied twice."""
    dst.unlink(missing_ok=True)
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def stage(*, run: Path, base_model: str, base_snapshot: Path, repo: str, quants: list[str],
          license_file: Path | None, baseline: Path | None, quality: tuple[int, int, int] | None,
          out: Path) -> Path:
    if license_file is None or not Path(license_file).exists():
        raise SystemExit("a licence text is required (--license-file): the base model's licence must ship with it")
    gguf = run / "gguf"
    for q in quants:
        if not (gguf / f"model-{q.lower()}.gguf").exists():
            raise SystemExit(f"{q} was not exported in {gguf}")
    license_id, license_link = base_license((base_snapshot / "README.md").read_text(encoding="utf-8"))
    modelfile = parse_modelfile((gguf / f"Modelfile.{quants[0].lower()}").read_text(encoding="utf-8"))
    mlx = yaml.safe_load((run / "mlx.yaml").read_text(encoding="utf-8")) if (run / "mlx.yaml").exists() else {}

    target = out / repo.split("/")[-1]
    target.mkdir(parents=True, exist_ok=True)
    for q in quants:
        _place(gguf / f"model-{q.lower()}.gguf", target / gguf_name(repo, q))
    template, stops = hub_template(modelfile)
    params = {**modelfile["params"], **({"stop": stops} if stops else {})}
    (target / "template").write_text(template, encoding="utf-8")
    (target / "system").write_text(modelfile["system"], encoding="utf-8")
    (target / "params").write_text(json.dumps(params, indent=2), encoding="utf-8")
    shutil.copy2(license_file, target / "LICENSE")
    if license_id == "gemma":
        (target / "NOTICE").write_text(GEMMA_NOTICE + "\n", encoding="utf-8")
    lora = {"rank": mlx.get("lora_parameters", {}).get("rank"), "scale": mlx.get("lora_parameters", {}).get("scale"),
            "learning rate": mlx.get("learning_rate")} if mlx else {}
    n_train = None
    # mlx.yaml paths are relative to llm/, which is two levels above the run.
    data = run.parents[1] / mlx["data"] / "train.jsonl" if mlx.get("data") else None
    if data and data.exists():
        n_train = sum(1 for _ in data.open(encoding="utf-8"))
    info = CardInfo(repo=repo, base_model=base_model, license=license_id, license_link=license_link,
                    quants=[q.upper() for q in quants], system=modelfile["system"],
                    results=_results(run, baseline, [q.upper() for q in quants]), quality=quality,
                    lora={k: v for k, v in lora.items() if v is not None}, train_examples=n_train)
    (target / "README.md").write_text(render_card(info), encoding="utf-8")
    return target


def staged_modelfile(folder: Path, quant: str) -> str:
    """The Modelfile Ollama effectively builds from a pulled repo: the GGUF
    plus the `template`, `system` and `params` files next to it."""
    gguf = next(p.name for p in Path(folder).glob(f"*-{quant.upper()}.gguf"))
    params = json.loads((folder / "params").read_text(encoding="utf-8"))
    lines = [
        f"FROM ./{gguf}",
        f'TEMPLATE """{(folder / "template").read_text(encoding="utf-8")}"""',
        f'SYSTEM """{(folder / "system").read_text(encoding="utf-8")}"""',
    ]
    for key, value in params.items():
        for v in value if isinstance(value, list) else [value]:
            lines.append(f'PARAMETER {key} "{v}"' if isinstance(v, str) else f"PARAMETER {key} {v}")
    return "\n".join(lines) + "\n"


def verify(folder: Path, quant: str, tag: str = "czechator-release-check:latest") -> None:
    """Creates the staged model in the local Ollama and asks it one question,
    so a broken template or stop token shows up before anything is uploaded."""
    import subprocess

    from czllm.eval.ollama import OllamaClient
    from czllm.format.contracts import systems
    from czllm.gate import fixture_lines, smoke

    (folder / "Modelfile").write_text(staged_modelfile(folder, quant), encoding="utf-8")
    try:
        subprocess.run(["ollama", "create", tag, "-f", "Modelfile"], cwd=folder, check=True,
                       capture_output=True, text=True)
        wants = fixture_lines()[:3]
        smoke(OllamaClient(), tag, systems()["drop_in"], wants)
        smoke(OllamaClient(), tag, systems()["short"], wants)
    finally:
        (folder / "Modelfile").unlink(missing_ok=True)
        subprocess.run(["ollama", "rm", tag], capture_output=True)


def publish(folder: Path, repo: str, *, private: bool, yes: bool, api=None) -> int:
    files = sorted(p for p in Path(folder).iterdir() if p.is_file())
    total = sum(p.stat().st_size for p in files)
    for p in files:
        print(f"{p.stat().st_size / 1e6:10.1f} MB  {p.name}")
    visibility = "private" if private else "PUBLIC"
    print(f"{total / 1e9:.2f} GB to {repo} ({visibility})")
    if not yes:
        print("Dry run. Re-run with --yes to upload.")
        return 0
    if api is None:
        from huggingface_hub import HfApi

        api = HfApi()
    api.create_repo(repo_id=repo, repo_type="model", private=private, exist_ok=True)
    api.upload_folder(repo_id=repo, repo_type="model", folder_path=str(folder),
                      commit_message="Upload czechator model")
    print(f"uploaded -> https://huggingface.co/{repo}")
    return 0


def _quality(text: str | None) -> tuple[int, int, int] | None:
    if not text:
        return None
    exact, verified, total = (int(x) for x in text.split("/"))
    return exact, verified, total


def run_stage(args) -> int:
    from huggingface_hub import snapshot_download

    from czllm.train.run import candidate, load_sweep

    c = candidate(load_sweep(args.sweep), args.candidate)
    snapshot = Path(snapshot_download(c.hf, allow_patterns=["README.md"]))
    out = stage(run=args.run, base_model=c.hf, base_snapshot=snapshot, repo=args.repo,
                quants=args.quants.split(","), license_file=args.license_file, baseline=args.baseline,
                quality=_quality(args.quality), out=RELEASE_DIR)
    print(out)
    return 0


def run_verify(args) -> int:
    verify(args.dir, args.quant)
    print(f"{args.dir}: Ollama answers with a parsable list, no thinking")
    return 0


def run_publish(args) -> int:
    return publish(args.dir, args.repo, private=not args.public, yes=args.yes)


def register(sub) -> None:
    from czllm.train.run import DEFAULT_SWEEP

    p = sub.add_parser("release", help="stage or publish a model as a Hugging Face GGUF repo")
    actions = p.add_subparsers(dest="action", required=True)
    s = actions.add_parser("stage", help="write release/<repo-name> locally")
    s.add_argument("--run", type=Path, required=True)
    s.add_argument("--candidate", required=True)
    s.add_argument("--repo", required=True, help="e.g. librucha/czechator-gemma3-270m-GGUF")
    s.add_argument("--quants", default="Q8_0")
    s.add_argument("--license-file", type=Path, help="full text of the base model's licence")
    s.add_argument("--baseline", type=Path, help="eval JSON of czechator's default model, for comparison")
    s.add_argument("--quality", help="czechator quality on the clean set as EXACT/VERIFIED/TOTAL, e.g. 18/23/23")
    s.add_argument("--sweep", type=Path, default=DEFAULT_SWEEP)
    s.set_defaults(func=run_stage)
    v = actions.add_parser("verify", help="build the staged folder in local Ollama and smoke-test it")
    v.add_argument("--dir", type=Path, required=True)
    v.add_argument("--quant", default="Q8_0")
    v.set_defaults(func=run_verify)
    u = actions.add_parser("publish", help="upload a staged folder; dry run without --yes")
    u.add_argument("--dir", type=Path, required=True)
    u.add_argument("--repo", required=True)
    u.add_argument("--public", action="store_true", help="create the repo public (default: private)")
    u.add_argument("--yes", action="store_true")
    u.set_defaults(func=run_publish)
