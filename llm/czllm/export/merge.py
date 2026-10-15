"""Builds a Hugging Face-layout checkpoint for the GGUF converter.

`mlx_lm.fuse` saves weights in MLX layout, not HF layout: Qwen3.5 RMSNorm
weights come back shifted by +1 and conv1d kernels transposed, and the
converter then produces a model that emits garbage. LoRA only ever changes
the linear layers it adapted, and those share one layout in MLX and HF. So
the merged checkpoint is the base checkpoint byte for byte, with exactly the
adapted linear weights taken from the fused model.
"""

import shutil
from pathlib import Path

import mlx.core as mx

_PREFIX_PARTS = {"model", "language_model"}


def _canonical(name: str) -> str:
    """Name without the wrapper prefixes MLX and HF order differently
    (`language_model.model.` vs `model.language_model.`)."""
    parts = name.split(".")
    while parts and parts[0] in _PREFIX_PARTS:
        parts = parts[1:]
    return ".".join(parts)


def _load_dir(path: Path) -> dict[Path, dict[str, mx.array]]:
    return {f: mx.load(str(f)) for f in sorted(path.glob("*.safetensors"))}


def hf_merge(base_dir: Path, fused_dir: Path, adapters: Path, out_dir: Path) -> int:
    """Writes `out_dir`; returns the number of weights taken from the fused model."""
    adapted = {
        _canonical(key.rsplit(".", 1)[0]) + ".weight"
        for key in mx.load(str(adapters))
        if key.endswith(("lora_a", "lora_b"))
    }
    fused = {_canonical(k): v for shard in _load_dir(fused_dir).values() for k, v in shard.items()}
    base_shards = _load_dir(base_dir)
    base_names = {_canonical(k): k for shard in base_shards.values() for k in shard}

    missing = sorted(n for n in adapted if n not in base_names or n not in fused)
    if missing:
        raise ValueError(f"adapted weights not found in both checkpoints: {missing[:5]}")

    out_dir.mkdir(parents=True, exist_ok=True)
    for item in base_dir.iterdir():
        if item.suffix != ".safetensors" and item.is_file():
            shutil.copy2(item, out_dir / item.name)
    replaced = 0
    for shard_path, tensors in base_shards.items():
        merged = {}
        for key, value in tensors.items():
            name = _canonical(key)
            if name in adapted:
                if fused[name].shape != value.shape:
                    raise ValueError(f"{key}: fused shape {fused[name].shape} != base {value.shape}")
                merged[key] = fused[name].astype(value.dtype)
                replaced += 1
            else:
                merged[key] = value
        mx.save_safetensors(str(out_dir / shard_path.name), merged, metadata={"format": "pt"})
    return replaced
