import json
from pathlib import Path

QUALITY_COLUMNS = ["exact", "verified", "der", "missing", "spurious", "ambiguous_errors", "en_untouched", "format_fail"]


def _fmt(key: str, value) -> str:
    if key in {"exact", "verified", "der", "en_untouched"}:
        return f"{value * 100:.1f} %"
    return str(value)


def render(results: list[dict]) -> str:
    lines = [
        "## Kvalita", "",
        "| model | kontrakt | set | items | " + " | ".join(QUALITY_COLUMNS) + " |",
        "|---|---|---|---|" + "---|" * len(QUALITY_COLUMNS),
    ]
    for r in results:
        for name, rates in r["sets"].items():
            cells = " | ".join(_fmt(k, rates[k]) for k in QUALITY_COLUMNS)
            lines.append(f"| {r['model']} | {r['contract']} | {name} | {rates['items']} | {cells} |")
    lines += ["", "## Latence (300 znaků, M4 Max)", "",
              "| model | kontrakt | cold s | p50 s | p95 s | tok/s |", "|---|---|---|---|---|---|"]
    for r in results:
        lt = r.get("latency", {})
        if lt:
            lines.append(f"| {r['model']} | {r['contract']} | {lt['cold_s']:.2f} | {lt['p50_s']:.2f} | "
                         f"{lt['p95_s']:.2f} | {lt['tokens_per_s']:.0f} |")
    return "\n".join(lines) + "\n"


def run(args) -> int:
    results = [json.loads(Path(p).read_text(encoding="utf-8")) for p in args.inputs]
    args.out.write_text(render(results), encoding="utf-8")
    print(f"-> {args.out}")
    return 0


def register(sub) -> None:
    p = sub.add_parser("report", help="render eval results as Markdown")
    p.add_argument("--inputs", type=Path, nargs="+", required=True)
    p.add_argument("--out", type=Path, required=True)
    p.set_defaults(func=run)
