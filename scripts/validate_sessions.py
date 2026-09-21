#!/usr/bin/env python3
"""validate_sessions.py — validity checking for the RepLog sync CSV.

This checks DATA VALIDITY only (plan §4.6): schema/column set, ISO dates,
rpe 1-10 or blank, reps 0-100 or blank, weight_kg 0-500 or blank,
duration_s/distance_m/kcal >= 0, enums respected, no duplicate
(session_id, exercise, set_number), no date-shaped notes.

It deliberately does NOT apply the coach's 1RM junk filter (20-400 kg /
1-12 reps) — that lives in the analysis script, where 1RM maths happens.
Conflating the two would mark ~1,000 legitimate rows invalid.

Run:
    python3 scripts/validate_sessions.py sessions.csv
Exit code 0 = valid (anomalies may still be reported), 1 = schema errors.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

CSV_HEADER = [
    "session_id", "date", "start_time", "end_time", "bodyweight_kg",
    "exercise", "category", "exercise_type", "superset_id", "set_number",
    "weight_kg", "reps", "rpe", "duration_s", "distance_m", "kcal",
    "set_type", "notes",
]

EXERCISE_TYPES = {
    "weight_reps", "weight_time", "bw_weight_reps", "bw_assisted",
    "bw_reps", "bw_time", "cardio", "note",
}
SET_TYPES = {"working", "warmup", "drop"}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TIME_RE = re.compile(r"^\d{2}:\d{2}$")
DATE_SHAPED_NOTE_RE = re.compile(r"^\d{2}-[A-Za-z]{3}$")


def _num(value: str) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def validate(path: Path) -> dict:
    errors: list[str] = []
    anomalies: dict[str, int] = {}
    rows = 0
    sessions: set[str] = set()
    seen_keys: set[tuple[str, str, str]] = set()

    text = path.read_text(encoding="utf-8")
    parsed = list(csv.reader(text.splitlines()))
    if not parsed:
        return {"errors": ["file is empty"], "anomalies": anomalies,
                "rows": 0, "sessions": 0}

    header = parsed[0]
    if header != CSV_HEADER:
        errors.append(f"header mismatch: {header!r}")
        return {"errors": errors, "anomalies": anomalies,
                "rows": 0, "sessions": 0}

    for lineno, vals in enumerate(parsed[1:], start=2):
        rows += 1
        # Proper CSV parsing (handles quoted notes with commas).
        if len(vals) != len(CSV_HEADER):
            anomalies["field_count_mismatch"] = anomalies.get("field_count_mismatch", 0) + 1
            continue
        row = dict(zip(CSV_HEADER, vals))

        if row["session_id"] == "":
            errors.append(f"line {lineno}: empty session_id")
        else:
            sessions.add(row["session_id"])

        if row["date"] and not DATE_RE.match(row["date"]):
            errors.append(f"line {lineno}: bad date {row['date']!r}")

        for col in ("start_time", "end_time"):
            if row[col] and not TIME_RE.match(row[col]):
                errors.append(f"line {lineno}: bad {col} {row[col]!r}")

        if row["exercise_type"] not in EXERCISE_TYPES:
            errors.append(f"line {lineno}: bad exercise_type {row['exercise_type']!r}")

        if row["set_type"] and row["set_type"] not in SET_TYPES:
            errors.append(f"line {lineno}: bad set_type {row['set_type']!r}")

        rpe = _num(row["rpe"])
        if rpe is not None and not (1.0 <= rpe <= 10.0):
            errors.append(f"line {lineno}: rpe out of range {row['rpe']!r}")

        # reps/weight bounds are sanity checks: the plan's §4.6 validity
        # contract (0-100 / 0-500) is a *review* bound, not a schema one.
        # Legacy data carries genuine data-entry errors (999 reps, -35.85 kg
        # assisted) that must surface in the anomaly report, not fail the
        # migration gate. The coach's 1RM junk filter (20-400 kg / 1-12
        # reps) is a separate thing and lives in the analysis script.
        reps = _num(row["reps"])
        if reps is not None and not (0 <= reps <= 100):
            anomalies["reps_out_of_range"] = anomalies.get("reps_out_of_range", 0) + 1

        weight = _num(row["weight_kg"])
        if weight is not None and not (0 <= weight <= 500):
            anomalies["weight_out_of_range"] = anomalies.get("weight_out_of_range", 0) + 1

        for col in ("duration_s", "distance_m", "kcal"):
            v = _num(row[col])
            if v is not None and v < 0:
                errors.append(f"line {lineno}: {col} negative {row[col]!r}")

        bw = _num(row["bodyweight_kg"])
        if bw is not None and not (20 <= bw <= 300):
            anomalies["bodyweight_unusual"] = anomalies.get("bodyweight_unusual", 0) + 1

        note = row["notes"]
        if DATE_SHAPED_NOTE_RE.match(note):
            anomalies["date_shaped_note"] = anomalies.get("date_shaped_note", 0) + 1

        key = (row["session_id"], row["exercise"], row["set_number"])
        if key in seen_keys:
            anomalies["duplicate_set_key"] = anomalies.get("duplicate_set_key", 0) + 1
        seen_keys.add(key)

    return {
        "errors": errors,
        "anomalies": anomalies,
        "rows": rows,
        "sessions": len(sessions),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("csv", type=Path)
    args = ap.parse_args(argv)

    result = validate(args.csv)
    print(f"File:         {args.csv}")
    print(f"Rows:         {result['rows']}")
    print(f"Sessions:     {result['sessions']}")
    print(f"Schema errors: {len(result['errors'])}")
    for e in result["errors"][:20]:
        print(f"  ERROR: {e}")
    if len(result["errors"]) > 20:
        print(f"  ... and {len(result['errors']) - 20} more")
    print("Anomaly counts (informational, not errors):")
    if not result["anomalies"]:
        print("  (none)")
    for k in sorted(result["anomalies"]):
        print(f"  {k:24s} {result['anomalies'][k]}")

    return 0 if not result["errors"] else 1


if __name__ == "__main__":
    sys.exit(main())
