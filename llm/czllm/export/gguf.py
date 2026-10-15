"""Fused HF weights -> GGUF -> quantized -> `ollama create`.

The chat template and stop tokens are taken from the base model as Ollama
ships it, so the fine-tuned model speaks the protocol Ollama expects. The
short contract becomes the Modelfile SYSTEM: used only when a client sends
no system prompt (czechator always sends one).
"""

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


def render_modelfile(from_path: str, template: str, stops: list[str], system: str, num_ctx: int = 4096) -> str:
    for name, value in (("template", template), ("system", system)):
        if '"""' in value:
            raise ValueError(f"{name} contains triple quotes")
    lines = [
        f"FROM {from_path}",
        f'TEMPLATE """{template}"""',
        f'SYSTEM """{system}"""',
        "PARAMETER temperature 0",
        f"PARAMETER num_ctx {num_ctx}",
        *[f'PARAMETER stop "{s}"' for s in stops],
    ]
    return "\n".join(lines) + "\n"


def model_tag(name: str, version: int | str, quant: str) -> str:
    return f"czechator-{name}:v{version}-{quant.lower()}"


def _run(cmd: list[str], cwd: Path | None = None) -> str:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True).stdout


def export(run: Path, c: Candidate, version: int | str, quants=("Q8_0", "Q4_K_M"), via: str = "llama.cpp") -> list[str]:
    _run(["ollama", "pull", c.ollama_base])
    template = _run(["ollama", "show", "--template", c.ollama_base]).rstrip("\n")
    stops = parse_stops(_run(["ollama", "show", "--parameters", c.ollama_base]))
    fused = run / "fused"
    tags = []
    if via == "ollama":
        for quant in quants:
            tag = model_tag(c.name, version, quant)
            (run / "Modelfile").write_text(render_modelfile("./fused", template, stops, SHORT_SYSTEM), encoding="utf-8")
            _run(["ollama", "create", tag, "--quantize", quant.lower(), "-f", "Modelfile"], cwd=run)
            tags.append(tag)
        return tags

    gguf = run / "gguf"
    gguf.mkdir(exist_ok=True)
    f16 = gguf / "model-f16.gguf"
    if not f16.exists():
        _run([str(CONVERT_PY), str(LLAMA_DIR / "convert_hf_to_gguf.py"), str(fused),
              "--outfile", str(f16), "--outtype", "f16"])
    for quant in quants:
        out = gguf / f"model-{quant.lower()}.gguf"
        if not out.exists():
            _run([shutil.which("llama-quantize") or "llama-quantize", str(f16), str(out), quant])
        tag = model_tag(c.name, version, quant)
        modelfile = gguf / f"Modelfile.{quant.lower()}"
        modelfile.write_text(render_modelfile(f"./{out.name}", template, stops, SHORT_SYSTEM), encoding="utf-8")
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
