"""Fused HF weights -> GGUF -> quantized -> `ollama create`.

The chat template and stop tokens are taken from the base model as Ollama
ships it, so the fine-tuned model speaks the protocol Ollama expects. The
short contract becomes the Modelfile SYSTEM: used only when a client sends
no system prompt (czechator always sends one).
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

from czllm.format.contracts import SHORT_SYSTEM
from czllm.train.run import DEFAULT_SWEEP, Candidate, candidate, load_sweep

LLAMA_TAG = "b11429"
LLAMA_DIR = Path(".cache/llama.cpp")
CONVERT_PY = Path(".cache/convert-venv/bin/python")


def parse_stops(parameters: str) -> list[str]:
    return re.findall(r'^stop\s+"(.*)"\s*$', parameters, flags=re.MULTILINE)


def parse_directives(modelfile: str) -> dict[str, str]:
    """RENDERER and PARSER of a base model's Modelfile. Ollama renders some
    models (Gemma 4) with built-in code and their TEMPLATE is a placeholder.
    Ollama 0.40 infers both from the GGUF architecture even when they are
    missing; writing them out keeps the Modelfile correct without relying on
    that inference."""
    found = re.findall(r"^(RENDERER|PARSER) (\S+)\s*$", modelfile, flags=re.MULTILINE)
    return {key.lower(): value for key, value in found}


def render_modelfile(from_path: str, template: str, stops: list[str], system: str, num_ctx: int = 4096,
                     directives: dict[str, str] | None = None) -> str:
    for name, value in (("template", template), ("system", system)):
        if '"""' in value:
            raise ValueError(f"{name} contains triple quotes")
    lines = [
        f"FROM {from_path}",
        f'TEMPLATE """{template}"""',
        *[f"{key.upper()} {value}" for key, value in (directives or {}).items()],
        f'SYSTEM """{system}"""',
        "PARAMETER temperature 0",
        f"PARAMETER num_ctx {num_ctx}",
        *[f'PARAMETER stop "{s}"' for s in stops],
    ]
    return "\n".join(lines) + "\n"


def _mtp_weights_missing(fused: Path) -> bool:
    """mlx-lm does not load Qwen3.5's multi-token-prediction head, so the fused
    weights lack `mtp.*` while config.json still declares the layer; the
    converter would then declare a block llama.cpp cannot find."""
    config = json.loads((fused / "config.json").read_text(encoding="utf-8"))
    declared = any(s.get("mtp_num_hidden_layers") for s in (config, config.get("text_config", {})))
    index = fused / "model.safetensors.index.json"
    names = json.loads(index.read_text(encoding="utf-8"))["weight_map"] if index.exists() else {}
    return declared and not any("mtp." in name for name in names)


def convert_cmd(fused: Path, out: Path) -> list[str]:
    cmd = [str(CONVERT_PY), str(LLAMA_DIR / "convert_hf_to_gguf.py"), str(fused),
           "--outfile", str(out), "--outtype", "f16"]
    # Dropping the MTP head costs only speculative decoding, which Ollama does not use.
    return cmd + ["--no-mtp"] if _mtp_weights_missing(fused) else cmd


def hf_checkpoint(run: Path, c: Candidate) -> Path:
    """Base weights in HF layout plus the adapted linear weights; see merge.py
    for why the fused MLX checkpoint cannot be converted directly."""
    hf = run / "hf"
    if not hf.exists():
        from huggingface_hub import snapshot_download

        from czllm.export.merge import hf_merge

        base = Path(snapshot_download(c.hf))
        hf_merge(base, run / "fused", run / "adapters" / "adapters.safetensors", hf)
    return hf


def model_tag(name: str, version: int | str, quant: str) -> str:
    return f"czechator-{name}:v{version}-{quant.lower()}"


def _run(cmd: list[str], cwd: Path | None = None) -> str:
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = "\n".join((proc.stderr or proc.stdout).strip().splitlines()[-5:])
        raise RuntimeError(f"{Path(cmd[0]).name} {' '.join(cmd[1:2])} exited {proc.returncode}: {tail}")
    return proc.stdout


def export(run: Path, c: Candidate, version: int | str, quants=("Q8_0", "Q4_K_M"), via: str = "llama.cpp") -> list[str]:
    _run(["ollama", "pull", c.ollama_base])
    template = _run(["ollama", "show", "--template", c.ollama_base]).rstrip("\n")
    stops = parse_stops(_run(["ollama", "show", "--parameters", c.ollama_base]))
    directives = parse_directives(_run(["ollama", "show", "--modelfile", c.ollama_base]))
    hf = hf_checkpoint(run, c)
    tags = []
    if via == "ollama":
        for quant in quants:
            tag = model_tag(c.name, version, quant)
            (run / "Modelfile").write_text(render_modelfile("./hf", template, stops, SHORT_SYSTEM, directives=directives), encoding="utf-8")
            _run(["ollama", "create", tag, "--quantize", quant.lower(), "-f", "Modelfile"], cwd=run)
            tags.append(tag)
        return tags

    gguf = run / "gguf"
    gguf.mkdir(exist_ok=True)
    f16 = gguf / "model-f16.gguf"
    if not f16.exists():
        _run(convert_cmd(hf, f16))
    for quant in quants:
        out = gguf / f"model-{quant.lower()}.gguf"
        if not out.exists():
            _run([shutil.which("llama-quantize") or "llama-quantize", str(f16), str(out), quant])
        tag = model_tag(c.name, version, quant)
        modelfile = gguf / f"Modelfile.{quant.lower()}"
        modelfile.write_text(render_modelfile(f"./{out.name}", template, stops, SHORT_SYSTEM, directives=directives), encoding="utf-8")
        _run(["ollama", "create", tag, "-f", modelfile.name], cwd=gguf)
        tags.append(tag)
    return tags


def run_cli(args) -> int:
    c = candidate(load_sweep(args.sweep), args.candidate)
    for tag in export(args.run, c, args.version, tuple(args.quants.split(",")), args.via):
        print(tag)
    return 0


def register(sub) -> None:
    p = sub.add_parser("export", help="GGUF + quantize + ollama create")
    p.add_argument("--run", type=Path, required=True)
    p.add_argument("--candidate", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--quants", default="Q8_0,Q4_K_M")
    p.add_argument("--via", choices=["llama.cpp", "ollama"], default="llama.cpp")
    p.add_argument("--sweep", type=Path, default=DEFAULT_SWEEP)
    p.set_defaults(func=run_cli)
