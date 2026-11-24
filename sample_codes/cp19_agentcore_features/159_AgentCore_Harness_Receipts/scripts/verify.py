"""Verify extracted fields and state transitions using local-only ground truth."""
import argparse
import csv
import json
from pathlib import Path
from client import ROOT, session_dir, save_json, setup


def check(artifacts, phase):
    expected = json.loads((ROOT / "data/expected.json").read_text(encoding="utf-8"))
    with (artifacts / "expenses.csv").open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 5, "Each image must have one row"
    by_file = {r["source_file"]: r for r in rows}
    assert set(by_file) == {e["source_file"] for e in expected}
    for e in expected:
        r = by_file[e["source_file"]]
        for key in ["receipt_id", "date", "merchant"]:
            assert r[key] == e[key], (e["source_file"], key, r[key], e[key])
        assert int(r["amount_yen"]) == e["amount_yen"], (e["source_file"], "amount_yen", r["amount_yen"], e["amount_yen"])
        assert r["reason"].strip(), "Missing classification evidence"
    for filename in ["02.png", "03.png"]:
        r = by_file[filename]
        e = next(e for e in expected if e["source_file"] == filename)
        assert r["status"] == "confirmed" and r["category"] == e["category"]
    if phase == "initial":
        pair = [by_file[k] for k in ["01.png", "05.png"]]
        assert sorted(r["status"] for r in pair) == ["confirmed", "duplicate_pending"]
        original = next(r for r in pair if r["status"] == "confirmed")
        duplicate = next(r for r in pair if r["status"] == "duplicate_pending")
        assert original["category"] == next(e["category"] for e in expected if e["source_file"] == "01.png")
        assert duplicate["duplicate_of"] == original["source_file"]
        assert by_file["04.png"]["status"] == "needs_confirmation"
        assert by_file["04.png"]["category"] == ""
        expected_pending = {"04.png", duplicate["source_file"]}
        target_total = 27820
    else:
        assert by_file["01.png"]["status"] == "confirmed"
        assert by_file["01.png"]["category"] == next(e["category"] for e in expected if e["source_file"] == "01.png")
        assert by_file["05.png"]["status"] == "duplicate" and by_file["05.png"]["duplicate_of"] == "01.png"
        assert by_file["04.png"]["status"] == "confirmed"
        assert by_file["04.png"]["category"] == next(e["category"] for e in expected if e["source_file"] == "04.png")
        expected_pending = set()
        target_total = 31420
    questions = json.loads((artifacts / "questions.json").read_text(encoding="utf-8"))
    assert {q["source_file"] for q in questions} == expected_pending
    assert all(q["question"].strip() for q in questions)
    confirmed = [r for r in rows if r["status"] == "confirmed"]
    assert sum(int(r["amount_yen"]) for r in confirmed) == target_total
    summary = json.loads((artifacts / "summary.json").read_text(encoding="utf-8"))
    wanted = dict(image_count=5, confirmed_count=len(confirmed), confirmed_total_yen=target_total,
                  pending_count=len(expected_pending), duplicate_count=int(phase == "final"))
    for k,v in wanted.items():
        assert summary[k] == v, (k, summary[k], v)
    assert (artifacts / "notes.md").read_text(encoding="utf-8").strip()
    return wanted


if __name__ == "__main__":
    setup()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--session", required=True)
    p.add_argument("--phase", choices=["initial", "final"], required=True)
    p.add_argument("--run")
    a = p.parse_args()
    try:
        directory = session_dir(a.session)
    except ValueError as exc:
        p.error(str(exc))
    run = (directory / (a.run or json.loads((directory / "latest.json").read_text())["directory"])).resolve()
    assert run.parent == directory.resolve()
    summary = check(run / "artifacts", a.phase)
    save_json(run / "verification.json", {"phase": a.phase, "passed": True, "summary": summary})
    print(json.dumps(summary, ensure_ascii=False, indent=2))
