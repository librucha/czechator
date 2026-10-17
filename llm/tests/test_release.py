import json
from types import SimpleNamespace as NS

import pytest

from czllm.release.hf import (
    CardInfo, base_license, gguf_name, parse_modelfile, publish, render_card, stage,
)

MODELFILE = '''FROM ./model-q8_0.gguf
TEMPLATE """{{- range .Messages }}<start_of_turn>{{ .Role }}
{{ .Content }}<end_of_turn>
{{ end }}<start_of_turn>model
"""
SYSTEM """Restore Czech diacritics in each numbered item. Change nothing else."""
PARAMETER temperature 0
PARAMETER num_ctx 4096
PARAMETER stop "<end_of_turn>"
PARAMETER stop "<eos>"
'''


def test_parse_modelfile():
    m = parse_modelfile(MODELFILE)
    assert m["template"].startswith("{{- range .Messages }}") and m["template"].endswith("<start_of_turn>model\n")
    assert m["system"] == "Restore Czech diacritics in each numbered item. Change nothing else."
    assert m["params"] == {"temperature": 0, "num_ctx": 4096, "stop": ["<end_of_turn>", "<eos>"]}


GEMMA4_MODELFILE = '''FROM ./model-q8_0.gguf
TEMPLATE """{{ .Prompt }}"""
RENDERER gemma4
PARSER gemma4
SYSTEM """Restore Czech diacritics in each numbered item. Change nothing else."""
PARAMETER temperature 0
PARAMETER num_ctx 4096
'''


def test_parse_modelfile_reports_the_renderer():
    assert parse_modelfile(GEMMA4_MODELFILE)["renderer"] == "gemma4"
    assert parse_modelfile(MODELFILE)["renderer"] is None


def test_a_hub_repo_gets_a_real_go_template_where_ollama_uses_a_renderer():
    # A pulled hf.co repo can carry only a Go `template`, not RENDERER; the
    # placeholder would send the model a bare prompt.
    from czllm.release.hf import hub_template

    template, stops = hub_template(parse_modelfile(GEMMA4_MODELFILE))
    assert "<|turn>system" in template and "<|turn>user" in template and "<|turn>model" in template
    assert stops == ["<turn|>"]
    plain = parse_modelfile(MODELFILE)
    assert hub_template(plain) == (plain["template"], ["<end_of_turn>", "<eos>"])


def _hf_snapshot(repo):
    from pathlib import Path

    root = Path.home() / ".cache" / "huggingface" / "hub" / f"models--{repo.replace('/', '--')}" / "snapshots"
    return next(root.glob("*/tokenizer_config.json"), None)


@pytest.mark.integration
@pytest.mark.skipif(not __import__("shutil").which("go") or _hf_snapshot("google/gemma-4-E2B-it") is None,
                    reason="needs Go and the cached google/gemma-4-E2B-it tokenizer")
def test_gemma4_go_template_renders_exactly_the_training_chat_format(tmp_path):
    import subprocess
    from pathlib import Path

    from transformers import AutoTokenizer

    from czllm.release.hf import GO_TEMPLATES

    template = tmp_path / "template"
    template.write_text(GO_TEMPLATES["gemma4"][0])
    tok = AutoTokenizer.from_pretrained("google/gemma-4-E2B-it")
    renderer = Path(__file__).with_name("render_template.go")
    for messages in (
        [{"role": "system", "content": "SYS"}, {"role": "user", "content": "1. kun\n2. pes"}],
        [{"role": "user", "content": "1. kun"}],
    ):
        want = tok.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        got = subprocess.run(["go", "run", str(renderer), str(template)], input=json.dumps(messages),
                             capture_output=True, text=True, check=True).stdout
        assert "<bos>" + got == want   # Ollama adds BOS as a token, not as template text


def test_an_unknown_renderer_is_refused():
    from czllm.release.hf import hub_template

    with pytest.raises(SystemExit, match="qwen9"):
        hub_template(parse_modelfile(GEMMA4_MODELFILE.replace("gemma4", "qwen9")))


def test_base_license_reads_the_model_card_front_matter():
    assert base_license("---\nlicense: gemma\nlibrary_name: transformers\n---\n# Gemma") == ("gemma", None)
    assert base_license("---\nlicense: apache-2.0\nlicense_link: https://x/y\n---\n") == ("apache-2.0", "https://x/y")


def test_gguf_name_carries_the_quant_ollama_selects_by():
    assert gguf_name("librucha/czechator-gemma3-270m-GGUF", "q8_0") == "czechator-gemma3-270m-Q8_0.gguf"


def _info(**kw):
    base = dict(
        repo="librucha/czechator-gemma3-270m-GGUF", base_model="google/gemma-3-270m-it",
        license="gemma", license_link=None, quants=["Q8_0"],
        system="Restore Czech diacritics in each numbered item. Change nothing else.",
        results=[{"label": "this model, Q8_0", "sets": {
            "web": {"items": 500, "exact": 0.366, "verified": 0.73, "der": 0.047},
            "hybrid": {"items": 410, "exact": 0.766, "verified": 0.949, "der": 0.021},
        }, "latency": {"p50_s": 0.52, "cold_s": 0.99}}],
        quality=(18, 23, 23), lora={"rank": 16, "scale": 2.0}, train_examples=38875,
    )
    base.update(kw)
    return CardInfo(**base)


def test_model_card_front_matter_usage_results_and_notice():
    card = render_card(_info())
    head = card.split("---")[1]
    assert "license: gemma" in head and "base_model: google/gemma-3-270m-it" in head
    assert "- cs" in head and "gguf" in head
    assert "ollama pull hf.co/librucha/czechator-gemma3-270m-GGUF:Q8_0" in card
    assert "| web | 500 | 36.6 % | 73.0 % | 4.7 % |" in card
    assert "18/23" in card
    assert "Gemma is provided under and subject to the Gemma Terms of Use" in card
    assert "Known limitations" in card and "byt" in card


def test_model_card_for_apache_base_links_the_licence_and_omits_the_gemma_notice():
    card = render_card(_info(license="apache-2.0", license_link="https://ai.google.dev/gemma/docs/gemma_4_license",
                             base_model="google/gemma-4-E2B-it", quality=None))
    assert "license: apache-2.0" in card and "license_link: https://ai.google.dev/gemma/docs/gemma_4_license" in card
    assert "Gemma Terms of Use" not in card


def _run(tmp_path):
    run = tmp_path / "runs" / "r1"
    (run / "gguf").mkdir(parents=True)
    (run / "gguf" / "model-q8_0.gguf").write_bytes(b"GGUF-q8")
    (run / "gguf" / "Modelfile.q8_0").write_text(MODELFILE)
    (run / "mlx.yaml").write_text("data: data/sets/s01\nlora_parameters:\n  rank: 16\n  scale: 2.0\n  dropout: 0.0\n"
                                  "learning_rate: 0.0002\n")
    (tmp_path / "data" / "sets" / "s01").mkdir(parents=True)
    (tmp_path / "data" / "sets" / "s01" / "train.jsonl").write_text("{}\n{}\n{}\n")
    (run / "eval-q8_0-drop_in.json").write_text(json.dumps({
        "model": "czechator-gemma3-270m:v1-q8_0", "contract": "drop_in",
        "sets": {"web": {"items": 500, "exact": 0.366, "verified": 0.73, "der": 0.047}},
        "latency": {"p50_s": 0.52, "cold_s": 0.99},
    }))
    (run / "eval-q4_k_m-drop_in.json").write_text(json.dumps({
        "model": "czechator-gemma3-270m:v1-q4_k_m", "contract": "drop_in",
        "sets": {"web": {"items": 500, "exact": 0.318, "verified": 0.666, "der": 0.053}},
    }))
    snapshot = tmp_path / "snapshot"
    snapshot.mkdir()
    (snapshot / "README.md").write_text("---\nlicense: gemma\n---\n")
    return run, snapshot


def test_stage_writes_everything_ollama_and_the_hub_need(tmp_path):
    run, snapshot = _run(tmp_path)
    licence = tmp_path / "terms.txt"
    licence.write_text("GEMMA TERMS")
    out = stage(run=run, base_model="google/gemma-3-270m-it", base_snapshot=snapshot,
                repo="librucha/czechator-gemma3-270m-GGUF", quants=["Q8_0"], license_file=licence,
                baseline=None, quality=(18, 23, 23), out=tmp_path / "release")
    names = sorted(p.name for p in out.iterdir())
    assert names == ["LICENSE", "NOTICE", "README.md", "czechator-gemma3-270m-Q8_0.gguf", "params", "system", "template"]
    assert (out / "czechator-gemma3-270m-Q8_0.gguf").read_bytes() == b"GGUF-q8"
    assert json.loads((out / "params").read_text())["num_ctx"] == 4096
    assert (out / "system").read_text() == "Restore Czech diacritics in each numbered item. Change nothing else."
    assert (out / "LICENSE").read_text() == "GEMMA TERMS"
    # mlx.yaml paths are relative to llm/, not to wherever stage runs from
    card = (out / "README.md").read_text()
    assert "one epoch over 3 examples" in card
    # only results of the quantizations the repo actually ships
    assert "Q8_0" in card and "Q4_K_M" not in card


def test_stage_refuses_without_a_licence_text(tmp_path):
    run, snapshot = _run(tmp_path)
    with pytest.raises(SystemExit, match="licen"):
        stage(run=run, base_model="google/gemma-3-270m-it", base_snapshot=snapshot,
              repo="librucha/x-GGUF", quants=["Q8_0"], license_file=None,
              baseline=None, quality=None, out=tmp_path / "release")


def test_stage_refuses_a_quant_that_was_not_exported(tmp_path):
    run, snapshot = _run(tmp_path)
    licence = tmp_path / "terms.txt"
    licence.write_text("T")
    with pytest.raises(SystemExit, match="Q4_K_M"):
        stage(run=run, base_model="google/gemma-3-270m-it", base_snapshot=snapshot,
              repo="librucha/x-GGUF", quants=["Q4_K_M"], license_file=licence,
              baseline=None, quality=None, out=tmp_path / "release")


def test_staged_folder_rebuilds_the_modelfile_ollama_would_use(tmp_path):
    from czllm.release.hf import staged_modelfile

    run, snapshot = _run(tmp_path)
    licence = tmp_path / "terms.txt"
    licence.write_text("T")
    out = stage(run=run, base_model="google/gemma-3-270m-it", base_snapshot=snapshot,
                repo="librucha/czechator-gemma3-270m-GGUF", quants=["Q8_0"], license_file=licence,
                baseline=None, quality=None, out=tmp_path / "release")
    rebuilt = parse_modelfile(staged_modelfile(out, "Q8_0"))
    assert rebuilt == parse_modelfile(MODELFILE)
    assert staged_modelfile(out, "Q8_0").startswith("FROM ./czechator-gemma3-270m-Q8_0.gguf\n")


class FakeApi:
    def __init__(self):
        self.calls = []

    def create_repo(self, **kw):
        self.calls.append(("create_repo", kw))

    def upload_folder(self, **kw):
        self.calls.append(("upload_folder", kw))


def test_publish_is_a_dry_run_unless_confirmed(tmp_path, capsys):
    (tmp_path / "a.gguf").write_bytes(b"x" * 10)
    api = FakeApi()
    assert publish(tmp_path, "librucha/x-GGUF", private=True, yes=False, api=api) == 0
    assert api.calls == []
    assert "Dry run" in capsys.readouterr().out


def test_publish_creates_a_private_repo_by_default(tmp_path):
    (tmp_path / "a.gguf").write_bytes(b"x")
    api = FakeApi()
    publish(tmp_path, "librucha/x-GGUF", private=True, yes=True, api=api)
    assert api.calls[0] == ("create_repo", {"repo_id": "librucha/x-GGUF", "repo_type": "model",
                                            "private": True, "exist_ok": True})
    assert api.calls[1][1]["repo_id"] == "librucha/x-GGUF" and api.calls[1][1]["folder_path"] == str(tmp_path)
