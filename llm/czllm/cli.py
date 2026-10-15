"""czllm command line. Each pipeline step is a module exposing
`register(subparsers)`; heavy imports stay inside the command functions."""

import argparse
import importlib

COMMAND_MODULES = [
    "czllm.data.corpus",
    "czllm.synth.batch",
]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="czllm")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in COMMAND_MODULES:
        importlib.import_module(name).register(sub)
    args = parser.parse_args(argv)
    return args.func(args)
