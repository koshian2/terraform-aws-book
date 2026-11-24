"""Independently check reported totals and artifacts; never execute downloaded model code locally."""
import argparse
import ast
from collections import defaultdict
import csv
from html.parser import HTMLParser
import json
from pathlib import Path

from client import session_dir, save_json, setup


def expected_metrics(path):
    months, categories = defaultdict(int), defaultdict(int)
    with path.open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    total = 0
    for row in rows:
        amount = int(row["amount_yen"])
        total += amount
        months[row["date"][:7]] += amount
        categories[row["category"]] += amount
    return {"row_count": len(rows), "total_yen": total, "by_month": dict(months), "by_category": dict(categories)}


class HTMLCheck(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = set()
        self.external = []

    def handle_starttag(self, tag, attrs):
        self.tags.add(tag)
        for key, value in attrs:
            if key in ("src", "href") and value and not value.startswith(("#", "data:")):
                self.external.append(value)


def verify(directory, run):
    artifacts = run / "artifacts"
    expected = expected_metrics(directory / "input.csv")
    actual = json.loads((artifacts / "metrics.json").read_text(encoding="utf-8"))
    for key, value in expected.items():
        assert actual.get(key) == value, (key, actual.get(key), value)
    ast.parse((artifacts / "analysis.py").read_text(encoding="utf-8-sig"))
    html = (artifacts / "report.html").read_text(encoding="utf-8")
    parser = HTMLCheck()
    parser.feed(html)
    assert {"html", "body"} <= parser.tags
    assert "script" not in parser.tags and not parser.external, "Expected self-contained HTML without scripts/external URLs"
    assert "http://" not in html.replace("http://www.w3.org/2000/svg", "") and "https://" not in html
    assert len(html) > 1000, "Report unexpectedly small"
    execution_path = run / "execution.json"
    execution = json.loads(execution_path.read_text(encoding="utf-8")) if execution_path.exists() else None
    if execution:
        assert execution["tools"], "No tool execution observed"
        assert execution["stop_reasons"][-1] == "end_turn"
    result = {"totals_match": True, "expected": expected, "python_syntax_valid": True,
              "self_contained_html": True, "tool_calls": len(execution["tools"]) if execution else None,
              "note": "Narrative quality and visual layout require human review; this checks numeric aggregates and artifact structure."}
    save_json(run / "verification.json", result)
    return result


if __name__ == "__main__":
    setup()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True, help="latest、またはstartが表示したUUID")
    parser.add_argument("--run", help="Timestamp directory; defaults to latest")
    args = parser.parse_args()
    try:
        directory = session_dir(args.session)
    except ValueError as exc:
        parser.error(str(exc))
    name = args.run or json.loads((directory / "latest.json").read_text())["directory"]
    run = (directory / name).resolve()
    if run.parent != directory.resolve():
        raise SystemExit("--run must name a direct child directory")
    print(json.dumps(verify(directory, run), ensure_ascii=False, indent=2))
