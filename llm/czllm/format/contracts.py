"""The two input contracts the model is trained on (spec §4). Both share the
numbered-list wire format; only the system prompt differs."""

from czllm import swift_source
from czllm.numbered_list import encode

SHORT_SYSTEM = "Restore Czech diacritics in each numbered item. Change nothing else."
MAX_BATCH_CHARS = 1500   # czechator's default limits.maxBatchChars


def systems() -> dict[str, str]:
    return {"drop_in": swift_source.default_system(), "short": SHORT_SYSTEM}


def chat_record(system: str, inputs: list[str], targets: list[str]) -> dict:
    return {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": encode(inputs)},
            {"role": "assistant", "content": encode(targets)},
        ]
    }
