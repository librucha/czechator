import json
from datetime import datetime
from pathlib import Path

from czllm.train.run import candidate, load_sweep, mlx_config, new_run_dir, write_manifest

SWEEP = Path(__file__).resolve().parents[1] / "configs" / "sweep-01.yaml"


def test_load_sweep():
    sweep = load_sweep(SWEEP)
    assert [c.name for c in sweep.candidates] == ["qwen35-0.8b", "qwen35-2b", "gemma4-e2b", "gemma3-270m"]
    assert candidate(sweep, "gemma3-270m").lr == 2e-4
    assert sweep.train.max_seq_length == 2048


def test_mlx_config_one_epoch_and_lora_scale():
    sweep = load_sweep(SWEEP)
    c = candidate(sweep, "qwen35-0.8b")
    cfg = mlx_config(c, sweep.train, Path("d"), Path("a"), n_train=40_000)
    assert cfg["iters"] == 2500
    assert cfg["lora_parameters"] == {"rank": 16, "scale": 2.0, "dropout": 0.0}
    assert cfg["mask_prompt"] is True and cfg["fine_tune_type"] == "lora" and cfg["num_layers"] == -1
    assert cfg["model"] == "Qwen/Qwen3.5-0.8B" and cfg["learning_rate"] == 1e-4


def test_mlx_config_overrides_for_gate():
    sweep = load_sweep(SWEEP)
    cfg = mlx_config(candidate(sweep, "qwen35-0.8b"), sweep.train, Path("d"), Path("a"), 400, iters=50, batch_size=4)
    assert cfg["iters"] == 50 and cfg["batch_size"] == 4


def test_run_dir_and_manifest(tmp_path):
    run = new_run_dir(tmp_path, "qwen35-0.8b", datetime(2026, 10, 15, 9, 5))
    assert run.name == "20261015-0905-qwen35-0.8b" and run.is_dir()
    write_manifest(run, {"iters": 1}, tmp_path / "missing-manifest.json")
    m = json.loads((run / "manifest.json").read_text())
    assert m["mlx"] == {"iters": 1} and len(m["git_sha"]) == 40 and m["dataset_manifest"] is None
