#!/usr/bin/env python3
"""Measures how well a model does on the Czech fixtures.

Two numbers matter and they are not the same thing:

  exactly    the output equals the reference — the model got the diacritics right
  verified   the tool accepted the result at all — what the user experiences

A model can score badly on the first and well on the second (it left some
accents out) or well on the first and badly on the second (it got the accents
right but also reworded something, so the run was refused). Tuning a prompt
without watching both is guesswork.

The fixtures are written for `letterCase: preserve`. Under the looser policies
the model may legitimately change case, so the comparison is relaxed the same way
the tool relaxes it — otherwise every sample with a capitalized sentence start
would read as a failure.

Usage:
    Tools/quality.py qwen3:4b-instruct gemma3:4b
    Tools/quality.py --letter-case segmentStart qwen3:4b-instruct
    Tools/quality.py --verbose qwen3:4b-instruct
"""

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "Fixtures" / "quality"
BINARY = ROOT / ".build" / "release" / "czechator"


POLICIES = ("preserve", "segmentStart", "model")

# Worst to best. A run that refuses half the documents should look alarming at a
# glance; one that only misses a few accents should not.
HEAT = (
    (0.50, "\033[31m"),  # red
    (0.70, "\033[38;5;208m"),  # orange
    (0.85, "\033[33m"),  # yellow
    (0.95, "\033[32m"),  # green
    (1.01, "\033[92m"),  # bright green
)
RESET = "\033[0m"


def colors_wanted(mode: str) -> bool:
    # NO_COLOR is the de facto standard; "always" is for piping into `less -R`.
    if mode == "never":
        return False
    if mode == "always":
        return True
    return sys.stdout.isatty() and not os.environ.get("NO_COLOR")


def heat(ratio: float, text: str, enabled: bool) -> str:
    if not enabled:
        return text
    for threshold, code in HEAT:
        if ratio < threshold:
            return f"{code}{text}{RESET}"
    return text


def bar(ratio: float, width: int = 12) -> str:
    filled = round(ratio * width)
    return "█" * filled + "░" * (width - filled)


# label ("999/999 100.0%") plus a space plus the bar
CELL_WIDTH = 15 + 1 + 12


def summary(rows: list[tuple[str, int, int, int]], policy: str, color: str) -> None:
    """One row per model, so the table stays readable however many there are."""
    if not rows:
        return
    enabled = colors_wanted(color)
    name_width = max(len(name) for name, _, _, _ in rows)

    print()
    print(f"{'':<{name_width}}   {'přesně':<{CELL_WIDTH}}  {'přes verifikaci'}")
    print("─" * (name_width + 3 + CELL_WIDTH * 2 + 2))
    for name, exact, verified, total in rows:
        cells = []
        for value in (exact, verified):
            ratio = value / total if total else 0.0
            label = f"{value:>3}/{total:<3} {ratio * 100:5.1f}%"
            cells.append(heat(ratio, f"{label:<15} {bar(ratio)}", enabled))
        print(f"{name:<{name_width}}   {cells[0]}  {cells[1]}")
    print(f"\nletterCase: {policy}, vzorků: {rows[0][3]}")


def compare(got: str, want: str, policy: str) -> bool:
    """Mirrors LetterCasePolicy.normalize, minus the diacritic folding: the
    fixtures already carry the correct accents, so only case is relaxed."""
    if policy == "model":
        return got.lower() == want.lower()
    if policy == "segmentStart":
        # Only the opening letter of each line may differ in case.
        got_lines, want_lines = got.splitlines(True), want.splitlines(True)
        if len(got_lines) != len(want_lines):
            return False
        return all(
            g[:1].lower() + g[1:] == w[:1].lower() + w[1:]
            for g, w in zip(got_lines, want_lines)
        )
    return got == want


def config_for(model: str, directory: pathlib.Path, policy: str) -> pathlib.Path:
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
    text = "\n".join(lines) + "\n"
    text = text.replace("letterCase: preserve", f"letterCase: {policy}")
    path.write_text(text, encoding="utf-8")
    return path


def run(model: str, policy: str, verbose: bool) -> tuple[int, int, int]:
    with tempfile.TemporaryDirectory() as tmp:
        config = config_for(model, pathlib.Path(tmp), policy)
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
            if compare(got, want, policy):
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
    parser.add_argument("--letter-case", choices=POLICIES, default="preserve")
    parser.add_argument("--color", choices=("auto", "always", "never"), default="auto")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if not BINARY.exists():
        print("Nejdřív sestav release: swift build -c release", file=sys.stderr)
        return 2
    if shutil.which("ollama") is None:
        print("Varování: ollama není v PATH, měření poběží jen proti běžícímu serveru",
              file=sys.stderr)

    rows: list[tuple[str, int, int, int]] = []
    for model in args.models:
        print(f"\n== {model}  (letterCase: {args.letter_case})")
        exact, verified, total = run(model, args.letter_case, args.verbose)
        rows.append((model, exact, verified, total))

    summary(rows, args.letter_case, args.color)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
