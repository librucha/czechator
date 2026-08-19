#!/usr/bin/env python3
"""Measures how well a model does on the Czech fixtures.

Two numbers matter and they are not the same thing:

  exactly    the output equals the reference — the model got the diacritics right
  verified   the tool accepted the result at all — what the user experiences

A model can score badly on the first and well on the second (it left some
accents out) or well on the first and badly on the second (it got the accents
right but also reworded something, so the run was refused). Tuning a prompt
without watching both is guesswork.

Usage:
    Tools/quality.py qwen3:4b-instruct gemma3:4b
    Tools/quality.py --verbose qwen3:4b-instruct
"""

import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "Fixtures" / "quality"
BINARY = ROOT / ".build" / "release" / "czechator"


def config_for(model: str, directory: pathlib.Path) -> pathlib.Path:
    """A throwaway config pinned to one model, so the real one is untouched."""
    path = directory / "config.yaml"
    subprocess.run(
        [str(BINARY), "fix", "-", "--config", str(path)],
        input=b"x", capture_output=True, timeout=120,
    )
    text = path.read_text(encoding="utf-8")
    lines = []
    in_local = False
    for line in text.splitlines():
        if line.startswith("  local:"):
            in_local = True
        elif in_local and line.startswith("    model:"):
            line = f"    model: {model}"
            in_local = False
        lines.append(line)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def run(model: str, verbose: bool) -> tuple[int, int, int]:
    with tempfile.TemporaryDirectory() as tmp:
        config = config_for(model, pathlib.Path(tmp))
        exact = verified = total = 0

        for source in sorted(FIXTURES.glob("*.in")):
            # newline="" disables universal-newline translation: a CRLF fixture
            # must be compared as CRLF, not silently turned into LF.
            with open(source.with_suffix(".want"), encoding="utf-8", newline="") as handle:
                want = handle.read()
            result = subprocess.run(
                [str(BINARY), "fix", str(source), "--config", str(config)],
                capture_output=True, timeout=600,
            )
            got = result.stdout.decode("utf-8")
            total += 1
            if result.returncode == 0:
                verified += 1
            if got == want:
                exact += 1
                mark = "ok  "
            elif result.returncode == 0:
                mark = "~   "
            else:
                mark = "STOP"
            if verbose or mark != "ok  ":
                print(f"  {mark} {source.stem}")
                if verbose or mark == "~   ":
                    print(f"       chtěl: {want!r}")
                    print(f"       dostal: {got!r}")
        return exact, verified, total


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("models", nargs="+")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if not BINARY.exists():
        print("Nejdřív sestav release: swift build -c release", file=sys.stderr)
        return 2
    if shutil.which("ollama") is None:
        print("Varování: ollama není v PATH, měření poběží jen proti běžícímu serveru",
              file=sys.stderr)

    for model in args.models:
        print(f"\n== {model}")
        exact, verified, total = run(model, args.verbose)
        print(f"   přesně {exact}/{total}, prošlo verifikací {verified}/{total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
