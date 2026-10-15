"""Calls Ollama the way czechator's OllamaProvider does: /api/chat, not
streamed, system + user, temperature only. No `think` field is sent, because
czechator does not send one."""

import json
import time
import urllib.request
from dataclasses import dataclass


@dataclass(frozen=True)
class ChatResult:
    content: str
    thinking: str
    prompt_tokens: int
    eval_tokens: int
    wall_s: float
    eval_s: float


class OllamaClient:
    def __init__(self, base_url: str = "http://localhost:11434", timeout: float = 120.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _post(self, path: str, payload: dict) -> dict:
        req = urllib.request.Request(
            f"{self.base_url}{path}", data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=self.timeout) as response:
            return json.load(response)

    def chat(self, model: str, system: str, user: str) -> ChatResult:
        start = time.perf_counter()
        d = self._post("/api/chat", {
            "model": model, "stream": False,
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "options": {"temperature": 0.0},
        })
        wall = time.perf_counter() - start
        message = d["message"]
        return ChatResult(
            content=message.get("content", ""), thinking=message.get("thinking", "") or "",
            prompt_tokens=d.get("prompt_eval_count", 0), eval_tokens=d.get("eval_count", 0),
            wall_s=wall, eval_s=d.get("eval_duration", 0) / 1e9,
        )

    def unload(self, model: str) -> None:
        self._post("/api/generate", {"model": model, "keep_alive": 0})
