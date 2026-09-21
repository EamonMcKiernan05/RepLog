#!/usr/bin/env python3
"""repcount_import.py — one-time migration of a RepCount CSV export into the
RepLog sync schema (plan §4.5).

Reads the legacy 7-column export:
    Workout Start, Workout End, Exercise, Weight, Reps, Notes, Category

and writes:
    1. a new-schema CSV (frozen header, plan §4.4)
    2. an anomaly report (JSON + human text) for every row the importer
       refused to guess at. Nothing is "fixed" silently.

The RPE migration is the point of the build: RPE/RIR living in the Notes
prose moves into its own typed column. The rules (plan §4.5):
  - bare numbers and `Rpe 8`            -> rpe
  - `RIR n`                             -> 10 - n
  - ranges (`7.5-8`)                    -> midpoint, phrase kept in notes
  - standalone `F` (failure marker)     -> rpe 10, `F` kept in notes
  - anything outside 1-10 (`0`, `11`)   -> review list, never into rpe

Run:
    python3 scripts/repcount_import.py INPUT.csv -o OUT_DIR
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# Frozen CSV contract v1 (plan §4.4) — must match service/lift_sync/store.py.
CSV_HEADER = [
    "session_id", "date", "start_time", "end_time", "bodyweight_kg",
    "exercise", "category", "exercise_type", "superset_id", "set_number",
    "weight_kg", "reps", "rpe", "duration_s", "distance_m", "kcal",
    "set_type", "notes",
]

# Exercises that are cardio (one log: time/distance/calories).
CARDIO_EXERCISES = {
    "treadmill", "rowing", "rowing machine", "air bike", "bike", "cycling",
    "elliptical", "stairmaster", "incline walk", "walking", "running",
    "jump rope", "rope skipping", "swimming", "rowing erg",
}

# Exercises that are bodyweight (BW+ / BW- / reps-only / time).
BODYWEIGHT_EXERCISES = {
    "dips", "machine dips", "push up", "push ups", "push-up", "push-ups",
    "pull up", "pull ups", "pull-up", "pull-ups", "chin up", "chin ups",
    "assisted pull up", "assisted chin up", "assisted dips", "plank",
    "side plank", "wall sit", "bodyweight squat", "air squat", "pike push up",
    "pistol squat", "leg raise", "hanging leg raise", "hollow hold",
    "superman", "back extension",
}

# Prose markers for set_type.
DROPSET_RE = re.compile(r"\bdrop\s?set", re.IGNORECASE)
WARMUP_RE = re.compile(r"\bwarm\s?up", re.IGNORECASE)

# RPE note shapes.
BARE_NUM_RE = re.compile(r"^(\d{1,2}(?:\.\d)?)$")
RPE_PREFIX_RE = re.compile(r"^[Rr][Pp][Ee]\s+(\d{1,2}(?:\.\d)?)$")
RIR_PREFIX_RE = re.compile(r"^[Rr][Ii][Rr]\s+(\d{1,2}(?:\.\d)?)$")
RANGE_RE = re.compile(r"^(\d{1,2}(?:\.\d)?)\s*[-\u2013]\s*(\d{1,2}(?:\.\d)?)$")
STANDALONE_F_RE = re.compile(r"^[Ff]$")

DATE_CORRUPT_RE = re.compile(r"^\d{2}-[A-Za-z]{3}$")
EXCEL_ERROR_RE = re.compile(r"#(NAME|REF|VALUE|DIV/0|N/A)\??")

TS_RE = re.compile(r"^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2})$")


@dataclass
class RPEResult:
    rpe: float | None
    notes: str
    rule: str  # bare, rpe_prefix, rir, range, failure, none, review


@dataclass
class RowResult:
    row: dict[str, str] | None
    anomalies: list[str] = field(default_factory=list)


def extract_rpe(notes: str) -> RPEResult:
    """Pull an RPE out of a legacy note. Conservative: anything ambiguous
    stays in the notes and is flagged for review."""
    n = (notes or "").strip()
    if n == "":
        return RPEResult(None, "", "none")

    m = BARE_NUM_RE.match(n)
    if m:
        v = float(m.group(1))
        if 1.0 <= v <= 10.0:
            return RPEResult(v, "", "bare")
        return RPEResult(None, n, "review")  # 0, 11, ...

    m = RPE_PREFIX_RE.match(n)
    if m:
        v = float(m.group(1))
        if 1.0 <= v <= 10.0:
            return RPEResult(v, "", "rpe_prefix")
        return RPEResult(None, n, "review")

    m = RIR_PREFIX_RE.match(n)
    if m:
        rir = float(m.group(1))
        v = 10.0 - rir
        if 1.0 <= v <= 10.0:
            return RPEResult(v, "", "rir")
        return RPEResult(None, n, "review")

    m = RANGE_RE.match(n)
    if m:
        a, b = float(m.group(1)), float(m.group(2))
        mid = (a + b) / 2.0
        if 1.0 <= mid <= 10.0:
            return RPEResult(mid, n, "range")  # keep the phrase
        return RPEResult(None, n, "review")

    if STANDALONE_F_RE.match(n):
        return RPEResult(10.0, "F", "failure")

    return RPEResult(None, n, "none")


def parse_timestamp(value: str) -> tuple[str, str] | None:
    """`DD/MM/YYYY HH:MM` -> (date `YYYY-MM-DD`, time `HH:MM`), else None."""
    m = TS_RE.match((value or "").strip())
    if not m:
        return None
    d, mo, y, hh, mm = m.groups()
    return f"{y}-{int(mo):02d}-{int(d):02d}", f"{int(hh):02d}:{mm}"


def infer_exercise_type(exercise: str, category: str) -> str:
    ex = exercise.strip().lower()
    cat = (category or "").strip().lower()
    if ex in CARDIO_EXERCISES or cat == "cardio":
        return "cardio"
    if ex in BODYWEIGHT_EXERCISES:
        return "bw_weight_reps"
    return "weight_reps"


def set_type_from_notes(notes: str) -> str:
    if DROPSET_RE.search(notes or ""):
        return "drop"
    if WARMUP_RE.search(notes or ""):
        return "warmup"
    return "working"


def session_id_for(start: str, end: str) -> str:
    """Deterministic, stable across re-runs; distinct for two sessions a day."""
    key = f"{start.strip()}|{end.strip()}".encode("utf-8")
    return hashlib.sha256(key).hexdigest()[:12]


def _num(value: str) -> str:
    """Normalise a numeric cell: '' for blank/garbage, else the number."""
    v = (value or "").strip()
    if v == "":
        return ""
    try:
        f = float(v)
    except ValueError:
        return ""
    return str(int(f)) if f == int(f) else str(f)


def convert_row(
    start: str, end: str, exercise: str, weight: str, reps: str,
    notes: str, category: str, set_number: int,
) -> RowResult:
    """Convert one legacy row into a new-schema row + anomaly flags."""
    anomalies: list[str] = []

    ts = parse_timestamp(start)
    if ts is None:
        anomalies.append("unparsable_timestamp")
        date, start_time = "", ""
    else:
        date, start_time = ts
    ts_end = parse_timestamp(end)
    end_time = ts_end[1] if ts_end else ""

    # Weight / reps validity. Blank is normal for cardio; garbage is not.
    weight_raw = (weight or "").strip()
    reps_raw = (reps or "").strip()
    etype = infer_exercise_type(exercise, category)
    if weight_raw == "":
        if etype != "cardio":
            anomalies.append("blank_weight")
    elif _num(weight_raw) == "":
        anomalies.append("non_numeric_weight")
    if reps_raw == "":
        if etype != "cardio":
            anomalies.append("blank_reps")
    elif _num(reps_raw) == "":
        anomalies.append("non_numeric_reps")
    else:
        rv = float(reps_raw)
        if not (0 <= rv <= 100):
            anomalies.append("reps_out_of_range")
    if weight_raw and _num(weight_raw) != "":
        wv = float(weight_raw)
        if not (0 <= wv <= 500):
            anomalies.append("weight_out_of_range")

    # Notes corruption classes (reported, never silently fixed).
    n = (notes or "").strip()
    if DATE_CORRUPT_RE.match(n):
        anomalies.append("date_shaped_note")
    if EXCEL_ERROR_RE.search(n):
        anomalies.append("excel_error_note")

    rpe_res = extract_rpe(notes)
    if rpe_res.rule == "review":
        anomalies.append("rpe_review")

    set_type = set_type_from_notes(notes)

    row = {
        "session_id": session_id_for(start, end),
        "date": date,
        "start_time": start_time,
        "end_time": end_time,
        "bodyweight_kg": "",  # not in the legacy export
        "exercise": exercise.strip(),
        "category": (category or "").strip(),
        "exercise_type": etype,
        "superset_id": "",
        "set_number": str(set_number),
        "weight_kg": _num(weight_raw),
        "reps": _num(reps_raw),
        "rpe": _num(str(rpe_res.rpe)) if rpe_res.rpe is not None else "",
        "duration_s": "",
        "distance_m": "",
        "kcal": "",
        "set_type": set_type,
        "notes": rpe_res.notes,
    }
    return RowResult(row, anomalies)


def import_file(input_path: Path) -> tuple[list[dict[str, str]], dict]:
    """Read a legacy export, return (new-schema rows, anomaly report)."""
    with input_path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh)
        rows = [r for r in reader if r]
    if not rows:
        return [], {"error": "empty file"}
    header = [h.strip() for h in rows[0]]
    # Map columns by name so column order in the export doesn't matter.
    idx = {name: i for i, name in enumerate(header)}

    def cell(r, name):
        i = idx.get(name)
        return r[i].strip() if i is not None and i < len(r) else ""

    out_rows: list[dict[str, str]] = []
    anomaly_counts: dict[str, int] = {}
    anomaly_rows: list[dict] = []
    set_counters: dict[tuple[str, str, str], int] = {}

    for r in rows[1:]:
        start = cell(r, "Workout Start")
        end = cell(r, "Workout End")
        exercise = cell(r, "Exercise")
        weight = cell(r, "Weight")
        reps = cell(r, "Reps")
        notes = cell(r, "Notes")
        category = cell(r, "Category")

        key = (start, end, exercise)
        set_counters[key] = set_counters.get(key, 0) + 1
        set_number = set_counters[key]

        res = convert_row(start, end, exercise, weight, reps, notes,
                          category, set_number)
        if res.row is not None:
            out_rows.append(res.row)
        for a in res.anomalies:
            anomaly_counts[a] = anomaly_counts.get(a, 0) + 1
            anomaly_rows.append({
                "workout_start": start, "exercise": exercise,
                "weight": weight, "reps": reps, "notes": notes,
                "anomaly": a,
            })

    report = {
        "input": str(input_path),
        "total_rows": len(rows) - 1,
        "migrated_rows": len(out_rows),
        "distinct_sessions": len({r["session_id"] for r in out_rows}),
        "anomaly_counts": anomaly_counts,
        "anomaly_rows": anomaly_rows,
    }
    return out_rows, report


def write_csv(rows: list[dict[str, str]], path: Path) -> None:
    lines = [",".join(CSV_HEADER)]
    for row in rows:
        lines.append(",".join(_csv_field(row.get(c, "")) for c in CSV_HEADER))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _csv_field(value: str) -> str:
    if value is None:
        return ""
    text = str(value)
    if text == "":
        return ""
    if text[0] in ("=", "+", "-", "@"):
        text = " " + text
    if any(ch in text for ch in (",", '"', "\n", "\r")):
        return '"' + text.replace('"', '""') + '"'
    return text


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", type=Path)
    ap.add_argument("-o", "--out-dir", type=Path, default=Path("."))
    ap.add_argument("--report-json", type=Path, default=None)
    args = ap.parse_args(argv)

    rows, report = import_file(args.input)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    csv_out = args.out_dir / "sessions.csv"
    write_csv(rows, csv_out)

    report_json = args.report_json or (args.out_dir / "import-report.json")
    report_json.write_text(json.dumps(report, indent=2), encoding="utf-8")

    # Human summary.
    print(f"Input:            {args.input}")
    print(f"Total rows:       {report['total_rows']}")
    print(f"Migrated rows:    {report['migrated_rows']}")
    print(f"Distinct sessions: {report['distinct_sessions']}")
    print(f"CSV written:      {csv_out}")
    print(f"Report written:   {report_json}")
    print("\nAnomaly counts (rows the importer refused to guess at):")
    if not report["anomaly_counts"]:
        print("  (none)")
    for k in sorted(report["anomaly_counts"]):
        print(f"  {k:24s} {report['anomaly_counts'][k]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
