"""Refuses a dataset that would teach the model something czechator rejects,
or that would leak eval text into training. Runs over every record before
training; the first violation stops the pipeline."""

from pathlib import Path

from czllm.format.augment import check_pair
from czllm.format.contracts import MAX_BATCH_CHARS
from czllm.jsonl import read_jsonl
from czllm.numbered_list import NumberedListError, decode
from czllm.text import fold_key


class DatasetError(ValueError):
    pass


def validate_record(record: dict, systems: set[str], eval_keys: set[str]) -> None:
    messages = record.get("messages", [])
    if [m.get("role") for m in messages] != ["system", "user", "assistant"]:
        raise DatasetError("roles must be system, user, assistant")
    system, user, assistant = (m["content"] for m in messages)
    if system not in systems:
        raise DatasetError("unknown system prompt")
    count = user.count("\n") + 1   # encode never leaves a raw newline in an item
    try:
        inputs = decode(user, count)
        targets = decode(assistant, count)
    except NumberedListError as e:
        raise DatasetError(f"items do not parse: {e}") from e
    if sum(len(t) for t in targets) > MAX_BATCH_CHARS and len(targets) > 1:
        raise DatasetError(f"batch over {MAX_BATCH_CHARS} chars")
    if len(targets) == 1 and len(targets[0]) > MAX_BATCH_CHARS:
        raise DatasetError(f"single item over {MAX_BATCH_CHARS} chars")
    for n, (inp, tgt) in enumerate(zip(inputs, targets), start=1):
        if not check_pair(inp, tgt):
            raise DatasetError(f"item {n}: fold or length differs")
        for line in tgt.split("\n"):
            if line.strip() and fold_key(line) in eval_keys:
                raise DatasetError(f"item {n}: eval text in training data")


def validate_file(path: Path, systems: set[str], eval_keys: set[str]) -> int:
    n = 0
    for n, record in enumerate(read_jsonl(path), start=1):
        try:
            validate_record(record, systems, eval_keys)
        except DatasetError as e:
            raise DatasetError(f"{path}:{n}: {e}") from e
    return n
