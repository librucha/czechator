"""Reads the facts the training data must share with czechator straight from
its Swift source, so a change there cannot silently diverge from here."""

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
_CORE = REPO_ROOT / "Sources" / "CzechatorCore"
FOLDING = _CORE / "Verification" / "DiacriticFolding.swift"
FRAGILE = _CORE / "Providers" / "FragileWhitespace.swift"
PROMPTS = _CORE / "Providers" / "PromptBuilder.swift"

_SWIFT_ESCAPES = {"\\": "\\", '"': '"', "'": "'", "n": "\n", "t": "\t", "r": "\r", "0": "\0"}


def _literal_block(src: str, anchor: str) -> str:
    start = src.index("= [", src.index(anchor)) + len("= [")
    return src[start : src.index("]", start)]


def folding_table() -> dict[str, str]:
    block = _literal_block(FOLDING.read_text(encoding="utf-8"), "let table")
    return dict(re.findall(r'"([^"\\])":\s*"([^"\\])"', block))


def fragile_characters() -> frozenset[str]:
    block = _literal_block(FRAGILE.read_text(encoding="utf-8"), "let characters")
    return frozenset(chr(int(h, 16)) for h in re.findall(r"\\u\{([0-9A-Fa-f]+)\}", block))


def swift_multiline_constant(path: Path, name: str) -> str:
    """Value of `static let <name> = \"\"\" ... \"\"\"`, with Swift's rules:
    the closing delimiter's indentation is stripped and escapes are resolved."""
    lines = path.read_text(encoding="utf-8").splitlines()
    start = next(i for i, line in enumerate(lines) if re.search(rf'\blet {name} = """\s*$', line))
    end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == '"""')
    indent = lines[end][: len(lines[end]) - len(lines[end].lstrip())]
    body = []
    for line in lines[start + 1 : end]:
        if line.strip() and not line.startswith(indent):
            raise ValueError(f"{path.name}: line under-indented in {name}: {line!r}")
        body.append(line[len(indent) :] if line.strip() else "")
    return re.sub(r"\\(.)", lambda m: _SWIFT_ESCAPES[m.group(1)], "\n".join(body))


def default_system() -> str:
    return swift_multiline_constant(PROMPTS, "defaultSystem")
