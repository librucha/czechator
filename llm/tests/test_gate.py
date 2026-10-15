import random

import pytest

from czllm.eval.ollama import ChatResult
from czllm.format.contracts import systems
from czllm.format.validate import validate_file
from czllm.gate import fixture_lines, gate_dataset, smoke


def test_fixture_lines_come_from_the_quality_fixtures():
    lines = fixture_lines()
    assert "Příliš žluťoučký kůň úpěl ďábelské ódy." in lines
    assert all(l.strip() for l in lines)


def test_gate_dataset_is_valid(tmp_path):
    gate_dataset(tmp_path, random.Random(0), n=50, n_valid=5)
    known = set(systems().values())
    assert validate_file(tmp_path / "train.jsonl", known, set()) == 50
    assert validate_file(tmp_path / "valid.jsonl", known, set()) == 5


class Client:
    def __init__(self, content, thinking=""):
        self.content, self.thinking = content, thinking

    def chat(self, model, system, user):
        return ChatResult(self.content, self.thinking, 1, 1, 0.1, 0.1)


def test_smoke_accepts_a_parsable_answer_and_rejects_thinking():
    smoke(Client("1. kůň\n2. pes"), "m", "sys", ["kůň", "pes"])
    with pytest.raises(AssertionError, match="thinking"):
        smoke(Client("1. kůň\n2. pes", thinking="hmm"), "m", "sys", ["kůň", "pes"])
    with pytest.raises(AssertionError, match="parse"):
        smoke(Client("Here you go: kůň, pes"), "m", "sys", ["kůň", "pes"])
