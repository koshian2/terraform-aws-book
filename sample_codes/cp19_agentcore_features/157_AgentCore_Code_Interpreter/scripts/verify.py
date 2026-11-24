"""Check a downloaded shift.csv against the rules, independently of the generated solver code."""
import argparse
import csv
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DAYS, SHIFTS = "月火水木金土日", ("早番", "遅番")


def latest_shift():
    found = sorted(ROOT.glob("results/*/files/shift.csv"))
    if not found:
        raise SystemExit("No results/*/files/shift.csv. Ask the agent to code_download shift.csv first.")
    return found[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shift", nargs="?", type=Path, help="default: newest results/*/files/shift.csv")
    parser.add_argument("--off", action="append", default=[], metavar="NAME:DAYS",
                        help="extra days off from a follow-up request, e.g. --off 佐藤:水")
    args = parser.parse_args()
    path = args.shift or latest_shift()

    with open(ROOT / "data/staff.csv", encoding="utf-8") as f:
        off = {r["name"]: set(r["days_off"].split()) for r in csv.DictReader(f)}
    for item in args.off:
        name, days = item.split(":")
        off[name] |= set(days)

    with open(path, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    errors = defaultdict(list)
    slots, by_day = defaultdict(list), defaultdict(list)
    for r in rows:
        day, shift, name = (r.get(k, "").strip() for k in ("day", "shift", "name"))
        if day not in DAYS or len(day) != 1 or shift not in SHIFTS or name not in off:
            errors["format"].append(r)
            continue
        slots[day, shift].append(name)
        by_day[name, day].append(shift)

    for day in DAYS:
        for shift in SHIFTS:
            names = slots[day, shift]
            if len(names) != 2 or len(set(names)) != 2:
                errors["two_per_shift"].append(f"{day}{shift}: {names}")
    work = Counter()
    for (name, day), shifts in by_day.items():
        work[name] += 1
        if day in off[name]:
            errors["days_off"].append(f"{name} {day}")
        if len(shifts) > 1:
            errors["one_shift_per_day"].append(f"{name} {day}")
    for name in off:
        if work[name] > 5:
            errors["max_five_days"].append(f"{name}: {work[name]}")
        for today, tomorrow in zip(DAYS, DAYS[1:]):
            if "遅番" in by_day[name, today] and "早番" in by_day[name, tomorrow]:
                errors["no_early_after_late"].append(f"{name} {today}→{tomorrow}")

    rules = ["format", "two_per_shift", "days_off", "one_shift_per_day", "max_five_days", "no_early_after_late"]
    counts = {name: work[name] for name in off}
    report = {"file": str(path), "rows": len(rows),
              "rules": {rule: "FAIL" if errors[rule] else "PASS" for rule in rules},
              "errors": {rule: errors[rule] for rule in rules if errors[rule]},
              "work_days": counts, "spread": max(counts.values()) - min(counts.values()),
              "status": "FAIL" if any(errors[rule] for rule in rules) else "PASS"}
    path.with_name("verification.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    sys.exit(report["status"] != "PASS")


if __name__ == "__main__":
    main()
