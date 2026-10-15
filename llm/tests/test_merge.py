import json

import mlx.core as mx
import pytest

from czllm.export.merge import hf_merge

GATE = "layers.0.mlp.gate_proj.weight"
NORM = "layers.0.input_layernorm.weight"
CONV = "layers.0.linear_attn.conv1d.weight"


def _write(path, tensors, extra=None):
    path.mkdir(parents=True, exist_ok=True)
    mx.save_safetensors(str(path / "model.safetensors"), tensors)
    for name, content in (extra or {}).items():
        (path / name).write_text(content)


def test_only_adapted_linear_weights_come_from_the_fused_model(tmp_path):
    # mlx_lm.fuse saves MLX layout: RMSNorm weights shifted by +1, conv1d
    # transposed. Only LoRA-adapted linear weights share the HF layout.
    base = tmp_path / "base"
    _write(base, {
        f"model.language_model.{GATE}": mx.ones((2, 3)),
        f"model.language_model.{NORM}": mx.zeros((3,)),
        f"model.language_model.{CONV}": mx.ones((4, 1, 2)),
    }, {"config.json": '{"architectures": ["X"]}', "tokenizer.json": "{}"})
    fused = tmp_path / "fused"
    _write(fused, {
        f"language_model.model.{GATE}": 2 * mx.ones((2, 3)),
        f"language_model.model.{NORM}": mx.ones((3,)),
        f"language_model.model.{CONV}": mx.ones((4, 2, 1)),
    })
    adapters = tmp_path / "adapters.safetensors"
    mx.save_safetensors(str(adapters), {
        f"language_model.model.{GATE[:-len('.weight')]}.lora_a": mx.zeros((3, 1)),
        f"language_model.model.{GATE[:-len('.weight')]}.lora_b": mx.zeros((1, 2)),
    })
    out = tmp_path / "hf"
    assert hf_merge(base, fused, adapters, out) == 1
    merged = mx.load(str(out / "model.safetensors"))
    assert mx.array_equal(merged[f"model.language_model.{GATE}"], 2 * mx.ones((2, 3)))
    assert mx.array_equal(merged[f"model.language_model.{NORM}"], mx.zeros((3,)))
    assert merged[f"model.language_model.{CONV}"].shape == (4, 1, 2)
    assert json.loads((out / "config.json").read_text()) == {"architectures": ["X"]}
    assert (out / "tokenizer.json").exists()


def test_refuses_an_adapter_it_cannot_place(tmp_path):
    base, fused = tmp_path / "base", tmp_path / "fused"
    _write(base, {f"model.{GATE}": mx.ones((2, 3))})
    _write(fused, {f"model.{GATE}": mx.ones((2, 3))})
    adapters = tmp_path / "adapters.safetensors"
    mx.save_safetensors(str(adapters), {"model.layers.9.mlp.up_proj.lora_a": mx.zeros((3, 1))})
    with pytest.raises(ValueError, match="up_proj"):
        hf_merge(base, fused, adapters, tmp_path / "hf")
