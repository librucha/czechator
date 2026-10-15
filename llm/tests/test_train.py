import json
from datetime import datetime
from pathlib import Path

from czllm.train.run import candidate, load_sweep, mlx_config, new_run_dir, write_manifest

SWEEP = Path(__file__).resolve().parents[1] / "configs" / "sweep-01.yaml"


def test_load_sweep():
    sweep = load_sweep(SWEEP)
    assert [c.name for c in sweep.candidates] == ["qwen35-0.8b", "qwen35-2b", "gemma4-e2b", "gemma3-270m"]
    assert candidate(sweep, "gemma3-270m").lr == 2e-4
    assert sweep.train.max_seq_length == 2560


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


def test_max_seq_length_has_margin_over_a_full_technical_batch():
    # A 1515-char technical batch under the drop-in prompt measured 2049
    # Qwen3.5 tokens; 2048 would truncate the answer silently.
    assert load_sweep(SWEEP).train.max_seq_length >= 2560


def _one_record_set(tmp_path):
    from czllm.format.contracts import chat_record, systems
    from czllm.jsonl import write_jsonl

    record = chat_record(systems()["short"], ["kun"], ["kůň"])
    write_jsonl(tmp_path / "train.jsonl", [record])
    write_jsonl(tmp_path / "valid.jsonl", [record])


def test_preflight_rejects_records_over_max_seq_length(tmp_path):
    import pytest

    from czllm.format.validate import DatasetError
    from czllm.train.run import preflight

    _one_record_set(tmp_path)
    count = lambda messages: sum(len(m["content"]) for m in messages)
    preflight(tmp_path, count, limit=1000, eval_keys=set())
    with pytest.raises(DatasetError, match="tokens"):
        preflight(tmp_path, count, limit=10, eval_keys=set())


def test_token_count_handles_batch_encoding_and_plain_lists():
    from czllm.train.run import token_count

    # transformers >= 4.5x returns a BatchEncoding (a dict) from
    # apply_chat_template(tokenize=True); len() of it is the number of keys.
    assert token_count({"input_ids": [1, 2, 3], "attention_mask": [1, 1, 1]}) == 3
    assert token_count([1, 2, 3, 4]) == 4


def test_preflight_rejects_eval_leak(tmp_path):
    import pytest

    from czllm.format.validate import DatasetError
    from czllm.text import fold_key
    from czllm.train.run import preflight

    _one_record_set(tmp_path)
    with pytest.raises(DatasetError, match="eval"):
        preflight(tmp_path, lambda m: 1, limit=1000, eval_keys={fold_key("kůň")})
