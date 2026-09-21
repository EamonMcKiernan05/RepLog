"""Tests for scripts/repcount_import.py and scripts/validate_sessions.py."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import repcount_import as ri  # noqa: E402
import validate_sessions as vs  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"
LEGACY = FIXTURES / "legacy_export.csv"


# -- RPE extraction --------------------------------------------------------
@pytest.mark.parametrize(
    "note, rpe, rule",
    [
        ("8", 8.0, "bare"),
        ("8.5", 8.5, "bare"),
        ("Rpe 8", 8.0, "rpe_prefix"),
        ("rpe 7.5", 7.5, "rpe_prefix"),
        ("Rir 3", 7.0, "rir"),
        ("RIR 0", 10.0, "rir"),
        ("7.5-8", 7.75, "range"),
        ("F", 10.0, "failure"),
        ("f", 10.0, "failure"),
        ("0", None, "review"),
        ("11", None, "review"),
        ("Rpe 11", None, "review"),
        ("", None, "none"),
        ("beltless", None, "none"),
        ("6-7 socks only", None, "none"),  # not a pure range: stays prose
    ],
)
def test_extract_rpe(note, rpe, rule):
    res = ri.extract_rpe(note)
    assert res.rpe == rpe, note
    assert res.rule == rule, note


def test_range_keeps_phrase_in_notes():
    res = ri.extract_rpe("7.5-8")
    assert res.rpe == 7.75
    assert res.notes == "7.5-8"


def test_failure_keeps_F_in_notes():
    res = ri.extract_rpe("F")
    assert res.rpe == 10.0
    assert res.notes == "F"


# -- timestamp -------------------------------------------------------------
def test_parse_timestamp():
    assert ri.parse_timestamp("21/09/2026 06:04") == ("2026-09-21", "06:04")
    assert ri.parse_timestamp("1/9/2026 6:04") == ("2026-09-01", "06:04")
    assert ri.parse_timestamp("") is None
    assert ri.parse_timestamp("garbage") is None


# -- session id ------------------------------------------------------------
def test_session_id_stable_and_distinct():
    a = ri.session_id_for("21/09/2026 06:04", "21/09/2026 07:43")
    b = ri.session_id_for("21/09/2026 06:04", "21/09/2026 07:43")
    c = ri.session_id_for("21/09/2026 12:00", "21/09/2026 13:30")
    assert a == b
    assert a != c
    assert len(a) == 12


# -- exercise type inference -----------------------------------------------
def test_infer_exercise_type():
    assert ri.infer_exercise_type("Treadmill", "Cardio") == "cardio"
    assert ri.infer_exercise_type("Dips", "Chest") == "bw_weight_reps"
    assert ri.infer_exercise_type("Low Bar Squat", "Squats") == "weight_reps"


# -- set type --------------------------------------------------------------
def test_set_type_from_notes():
    assert ri.set_type_from_notes("Dropset") == "drop"
    assert ri.set_type_from_notes("drop set") == "drop"
    assert ri.set_type_from_notes("warmup") == "warmup"
    assert ri.set_type_from_notes("Warm Up") == "warmup"
    assert ri.set_type_from_notes("8") == "working"


# -- full fixture conversion -----------------------------------------------
def test_convert_fixture(tmp_path):
    rows, report = ri.import_file(LEGACY)
    assert report["total_rows"] == 20
    assert report["migrated_rows"] == 20
    assert report["distinct_sessions"] == 1

    by_ex = {}
    for r in rows:
        by_ex.setdefault(r["exercise"], []).append(r)

    # RPE extraction across the shapes
    squat = by_ex["Low Bar Squat"]
    assert squat[0]["rpe"] == "8"
    assert squat[-1]["rpe"] == ""  # formula note, no rpe

    bench = by_ex["Competition Bench"]
    assert bench[0]["rpe"] == "8.5"
    assert bench[1]["rpe"] == "7"     # Rpe 7
    assert bench[2]["rpe"] == "8.25"  # 8-8.5 midpoint
    assert bench[3]["rpe"] == "7"     # Rir 3 -> 10-3

    dead = by_ex["Sumo Deadlifts"]
    assert dead[0]["rpe"] == "7.5"
    assert dead[1]["rpe"] == "10"     # F -> 10
    assert dead[1]["notes"] == "F"    # F kept

    dips = by_ex["Dips"][0]
    assert dips["exercise_type"] == "bw_weight_reps"
    assert dips["weight_kg"] == "0"

    tm = by_ex["Treadmill"][0]
    assert tm["exercise_type"] == "cardio"

    leg = by_ex["Leg Extensions"]
    assert leg[0]["set_type"] == "drop"
    assert leg[1]["set_type"] == "warmup"

    # set_number restarts per exercise
    assert [r["set_number"] for r in squat] == [str(i) for i in range(1, 11)]

    # anomalies counted
    ac = report["anomaly_counts"]
    assert ac.get("rpe_review", 0) == 2          # 0 and Rpe 11
    assert ac.get("date_shaped_note", 0) == 1    # 07-Aug
    assert ac.get("excel_error_note", 0) == 1    # #NAME?
    assert ac.get("blank_weight", 0) == 1        # blank weight on a squat
    assert ac.get("blank_reps", 0) == 1          # blank reps on a squat
    # cardio's blank weight/reps are NOT anomalies
    assert "blank_weight" not in [a["anomaly"] for a in report["anomaly_rows"]
                                  if a["exercise"] == "Treadmill"]

    # write + re-parse round trip
    out = tmp_path / "sessions.csv"
    ri.write_csv(rows, out)
    text = out.read_text()
    assert text.splitlines()[0] == ",".join(ri.CSV_HEADER)
    # the formula-shaped note is escaped
    assert " =HYPERLINK" in text
    # the comma note is quoted
    assert '"felt heavy, good speed"' in text


def test_importer_output_validates(tmp_path):
    rows, _ = ri.import_file(LEGACY)
    out = tmp_path / "sessions.csv"
    ri.write_csv(rows, out)
    result = vs.validate(out)
    # The migrated file must have zero schema errors.
    assert result["errors"] == [], result["errors"]
    assert result["rows"] == 20


# -- validator -------------------------------------------------------------
def test_validator_flags_bad_rpe(tmp_path):
    bad = tmp_path / "bad.csv"
    bad.write_text(
        ",".join(vs.CSV_HEADER) + "\n"
        "x,2026-09-21,06:00,07:00,,Squats,Squats,weight_reps,,1,100,5,11,,,,working,\n"
    )
    result = vs.validate(bad)
    assert any("rpe out of range" in e for e in result["errors"])


def test_validator_flags_bad_header(tmp_path):
    bad = tmp_path / "bad.csv"
    bad.write_text("wrong,header\n")
    result = vs.validate(bad)
    assert any("header mismatch" in e for e in result["errors"])


def test_validator_flags_duplicate_key(tmp_path):
    bad = tmp_path / "bad.csv"
    row = "s1,2026-09-21,06:00,07:00,,Squats,Squats,weight_reps,,1,100,5,8,,,,working,"
    bad.write_text(",".join(vs.CSV_HEADER) + "\n" + row + "\n" + row + "\n")
    result = vs.validate(bad)
    assert result["anomalies"].get("duplicate_set_key", 0) == 1


def test_validator_accepts_light_and_bodyweight_rows(tmp_path):
    """The validator must NOT reject legitimate light / bodyweight rows —
    that is the coach's 1RM filter's job, not the validator's."""
    good = tmp_path / "good.csv"
    rows = [
        # 5 kg accessory work — legitimate
        "s1,2026-09-21,06:00,07:00,,Curls,Biceps,weight_reps,,1,5,15,8,,,,working,",
        # bodyweight, zero weight
        "s1,2026-09-21,06:00,07:00,,Dips,Chest,bw_weight_reps,,1,0,12,9,,,,working,",
        # 300s plank, no weight/reps
        "s1,2026-09-21,06:00,07:00,,Plank,Abs,bw_time,,1,,,,300,,,,working,",
    ]
    good.write_text(",".join(vs.CSV_HEADER) + "\n" + "\n".join(rows) + "\n")
    result = vs.validate(good)
    assert result["errors"] == [], result["errors"]


def test_validator_flags_extreme_reps_as_anomaly(tmp_path):
    """Out-of-range reps/weight are data-entry errors: they surface in the
    anomaly report, they do not fail the migration gate."""
    f = tmp_path / "extreme.csv"
    f.write_text(
        ",".join(vs.CSV_HEADER) + "\n"
        "s1,2026-09-21,06:00,07:00,,Bench,Bench Press,weight_reps,,1,85,547,8,,,,working,\n"
        "s1,2026-09-21,06:00,07:00,,Pull Up,Back,bw_assisted,,1,-35.85,10,8,,,,working,\n"
    )
    result = vs.validate(f)
    assert result["errors"] == [], result["errors"]
    assert result["anomalies"].get("reps_out_of_range") == 1
    assert result["anomalies"].get("weight_out_of_range") == 1
