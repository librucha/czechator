import pytest

from czllm.export.gguf import model_tag, parse_stops, render_modelfile
from czllm.format.contracts import SHORT_SYSTEM

PARAMETERS = '''stop                           "<|im_start|>"
stop                           "<|im_end|>"
temperature                    0.7
'''


def test_parse_stops():
    assert parse_stops(PARAMETERS) == ["<|im_start|>", "<|im_end|>"]


def test_render_modelfile():
    mf = render_modelfile("./model-q8_0.gguf", "{{ .Prompt }}", ["<|im_end|>"], SHORT_SYSTEM)
    assert mf.splitlines()[0] == "FROM ./model-q8_0.gguf"
    assert 'TEMPLATE """{{ .Prompt }}"""' in mf
    assert f'SYSTEM """{SHORT_SYSTEM}"""' in mf
    assert "PARAMETER temperature 0" in mf
    assert "PARAMETER num_ctx 4096" in mf
    assert 'PARAMETER stop "<|im_end|>"' in mf


def test_render_modelfile_refuses_triple_quotes():
    with pytest.raises(ValueError):
        render_modelfile("./m.gguf", 'x """ y', [], SHORT_SYSTEM)


def test_failed_tool_reports_its_stderr():
    import sys

    from czllm.export.gguf import _run

    # The gate records the exception text; "exit status 1" alone says nothing.
    with pytest.raises(RuntimeError, match="Tokenizer class Foo does not exist"):
        _run([sys.executable, "-c", "import sys; sys.stderr.write('ValueError: Tokenizer class Foo does not exist'); sys.exit(1)"])


def _fused(path, config, weights):
    import json

    path.mkdir(parents=True, exist_ok=True)
    (path / "config.json").write_text(json.dumps(config))
    (path / "model.safetensors.index.json").write_text(
        json.dumps({"weight_map": {w: "model.safetensors" for w in weights}}))
    return path


def test_convert_skips_mtp_when_fuse_dropped_its_weights(tmp_path):
    from czllm.export.gguf import convert_cmd

    # mlx-lm does not keep Qwen3.5's mtp.* weights; without --no-mtp the
    # converter declares a block llama.cpp then cannot find.
    fused = _fused(tmp_path, {"text_config": {"num_hidden_layers": 24, "mtp_num_hidden_layers": 1}},
                   ["language_model.model.layers.0.mlp.gate_proj.weight"])
    assert "--no-mtp" in convert_cmd(fused, tmp_path / "out.gguf")


def test_convert_keeps_mtp_when_weights_exist_or_none_declared(tmp_path):
    from czllm.export.gguf import convert_cmd

    with_weights = _fused(tmp_path / "a", {"mtp_num_hidden_layers": 1}, ["mtp.layers.0.mlp.gate_proj.weight"])
    assert "--no-mtp" not in convert_cmd(with_weights, tmp_path / "out.gguf")
    gemma = _fused(tmp_path / "b", {"num_hidden_layers": 18}, ["model.layers.0.mlp.gate_proj.weight"])
    assert "--no-mtp" not in convert_cmd(gemma, tmp_path / "out.gguf")


def test_renderer_and_parser_are_carried_over():
    # Ollama renders Gemma 4 with a built-in renderer; its TEMPLATE is only a
    # placeholder. Ollama 0.40 infers the renderer from the architecture, but
    # the Modelfile should not depend on that.
    from czllm.export.gguf import parse_directives

    base = "FROM /x\nTEMPLATE {{ .Prompt }}\nRENDERER gemma4\nPARSER gemma4\nPARAMETER temperature 1\n"
    assert parse_directives(base) == {"renderer": "gemma4", "parser": "gemma4"}
    assert parse_directives("FROM /x\nPARAMETER stop <end_of_turn>\n") == {}
    mf = render_modelfile("./m.gguf", "{{ .Prompt }}", [], SHORT_SYSTEM, directives={"renderer": "gemma4", "parser": "gemma4"})
    assert "RENDERER gemma4" in mf.splitlines() and "PARSER gemma4" in mf.splitlines()


def test_model_tag():
    assert model_tag("qwen35-0.8b", 1, "Q4_K_M") == "czechator-qwen35-0.8b:v1-q4_k_m"
