"""Thin wrapper over mlx_lm: renders its config from the sweep file, records
what was trained on, and keeps the log next to the adapters."""

import json
import math
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from collections.abc import Callable

import yaml

from czllm.eval.sets import EVAL_PATHS, eval_keys, require_eval_sets
from czllm.format.contracts import systems
from czllm.format.validate import DatasetError, validate_file
from czllm.jsonl import read_jsonl
from czllm.swift_source import REPO_ROOT

RUNS = Path("runs")
DEFAULT_SWEEP = Path("configs/sweep-01.yaml")


@dataclass(frozen=True)
class Candidate:
    name: str
    hf: str
    ollama_base: str
    lr: float


@dataclass(frozen=True)
class TrainSettings:
    rank: int = 16
    alpha: int = 32
    batch_size: int = 16
    epochs: int = 1
    max_seq_length: int = 2560
    steps_per_eval: int = 200
    save_every: int = 200
    seed: int = 0


@dataclass(frozen=True)
class Sweep:
    dataset: Path
    candidates: list[Candidate]
    train: TrainSettings


def load_sweep(path: Path) -> Sweep:
    raw = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    return Sweep(
        dataset=Path(raw["dataset"]),
        candidates=[Candidate(**c) for c in raw["candidates"]],
        train=TrainSettings(**raw["train"]),
    )


def candidate(sweep: Sweep, name: str) -> Candidate:
    for c in sweep.candidates:
        if c.name == name:
            return c
    raise SystemExit(f"unknown candidate {name}; known: {[c.name for c in sweep.candidates]}")


def mlx_config(c: Candidate, s: TrainSettings, data_dir: Path, adapter_dir: Path, n_train: int,
               iters: int | None = None, batch_size: int | None = None) -> dict:
    batch = batch_size or s.batch_size
    return {
        "model": c.hf,
        "train": True,
        "data": str(data_dir),
        "fine_tune_type": "lora",
        "mask_prompt": True,
        "num_layers": -1,
        "batch_size": batch,
        "iters": iters or math.ceil(n_train * s.epochs / batch),
        "learning_rate": c.lr,
        "steps_per_eval": s.steps_per_eval,
        "save_every": s.save_every,
        "adapter_path": str(adapter_dir),
        "max_seq_length": s.max_seq_length,
        "grad_checkpoint": True,
        "seed": s.seed,
        # mlx-lm multiplies the LoRA update by `scale`; alpha/rank is the usual convention.
        "lora_parameters": {"rank": s.rank, "scale": s.alpha / s.rank, "dropout": 0.0},
    }


def new_run_dir(root: Path, name: str, now: datetime) -> Path:
    run = Path(root) / f"{now:%Y%m%d-%H%M}-{name}"
    run.mkdir(parents=True, exist_ok=False)
    return run


def write_manifest(run: Path, mlx: dict, dataset_manifest: Path) -> None:
    sha = subprocess.run(["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"],
                         capture_output=True, text=True, check=True).stdout.strip()
    manifest = {
        "git_sha": sha,
        "mlx": mlx,
        "dataset_manifest": json.loads(dataset_manifest.read_text()) if dataset_manifest.exists() else None,
    }
    (run / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")


def _tee(cmd: list[str], log: Path) -> None:
    with log.open("a", encoding="utf-8") as f:
        f.write("$ " + " ".join(cmd) + "\n")
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in proc.stdout:
            sys.stdout.write(line)
            f.write(line)
        if proc.wait() != 0:
            raise subprocess.CalledProcessError(proc.returncode, cmd)


def preflight(data_dir: Path, count_tokens: Callable[[list[dict]], int], limit: int, eval_keys: set[str]) -> None:
    """Spec §5.3 on the training path: every record valid, none leaking eval
    text, none longer than max_seq_length — MLX would silently cut the end of
    the answer and the model would learn a truncated output."""
    known = set(systems().values())
    for name in ("train.jsonl", "valid.jsonl"):
        path = data_dir / name
        validate_file(path, known, eval_keys)
        for n, record in enumerate(read_jsonl(path), start=1):
            tokens = count_tokens(record["messages"])
            if tokens > limit:
                raise DatasetError(f"{path}:{n}: {tokens} tokens > max_seq_length {limit}")


def token_count(encoded) -> int:
    # Newer transformers return a BatchEncoding (a dict) instead of a list.
    if isinstance(encoded, dict) or hasattr(encoded, "keys"):
        encoded = encoded["input_ids"]
    return len(encoded)


def chat_token_counter(hf: str) -> Callable[[list[dict]], int]:
    from transformers import AutoTokenizer

    tok = AutoTokenizer.from_pretrained(hf)
    return lambda messages: token_count(tok.apply_chat_template(messages, tokenize=True))


def train(run: Path, c: Candidate, s: TrainSettings, data_dir: Path,
          iters: int | None = None, batch_size: int | None = None) -> Path:
    preflight(data_dir, chat_token_counter(c.hf), s.max_seq_length, eval_keys(EVAL_PATHS.values()))
    n_train = sum(1 for _ in (data_dir / "train.jsonl").open(encoding="utf-8"))
    adapters = run / "adapters"
    cfg = mlx_config(c, s, data_dir, adapters, n_train, iters, batch_size)
    (run / "mlx.yaml").write_text(yaml.safe_dump(cfg, sort_keys=False), encoding="utf-8")
    write_manifest(run, cfg, data_dir / "manifest.json")
    _tee([sys.executable, "-m", "mlx_lm", "lora", "--config", str(run / "mlx.yaml")], run / "train.log")
    return adapters


def fuse(run: Path, c: Candidate) -> Path:
    fused = run / "fused"
    _tee([sys.executable, "-m", "mlx_lm", "fuse", "--model", c.hf, "--adapter-path", str(run / "adapters"),
          "--save-path", str(fused), "--dequantize"], run / "train.log")
    return fused


def run_cli(args) -> int:
    sweep = load_sweep(args.sweep)
    c = candidate(sweep, args.candidate)
    require_eval_sets()
    run = new_run_dir(RUNS, c.name, datetime.now())
    train(run, c, sweep.train, args.data or sweep.dataset, args.iters, args.batch_size)
    fuse(run, c)
    print(run)
    return 0


def register(sub) -> None:
    p = sub.add_parser("train", help="LoRA fine-tune one candidate and fuse it")
    p.add_argument("--candidate", required=True)
    p.add_argument("--sweep", type=Path, default=DEFAULT_SWEEP)
    p.add_argument("--data", type=Path)
    p.add_argument("--iters", type=int)
    p.add_argument("--batch-size", type=int)
    p.set_defaults(func=run_cli)
