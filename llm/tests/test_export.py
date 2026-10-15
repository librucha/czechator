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


def test_model_tag():
    assert model_tag("qwen35-0.8b", 1, "Q4_K_M") == "czechator-qwen35-0.8b:v1-q4_k_m"
