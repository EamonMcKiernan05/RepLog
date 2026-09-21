"""lift-sync test suite.

Covers (plan §7.3): upsert idempotency, serialised concurrent writes (two
simultaneous POSTs, both survive), atomic rewrite, delete/tombstone,
malformed payload rejection, auth.
"""

from __future__ import annotations

import threading

import pytest
from fastapi.testclient import TestClient

from lift_sync.app import make_app
from lift_sync.store import CSV_HEADER, Store


@pytest.fixture()
def client(tmp_path):
    import os

    os.environ["LIFT_SYNC_TOKEN"] = "test-token"
    app = make_app(tmp_path / "data")
    with TestClient(app) as c:
        yield c
    os.environ.pop("LIFT_SYNC_TOKEN", None)


def _session(sid="s1", n_sets=2, weight=100.0):
    return {
        "session_id": sid,
        "date": "2026-09-21",
        "start_time": "06:04",
        "end_time": "07:43",
        "bodyweight_kg": 100,
        "sets": [
            {
                "exercise": "Low Bar Squat",
                "category": "Squats",
                "exercise_type": "weight_reps",
                "set_number": i + 1,
                "weight_kg": weight,
                "reps": 4,
                "rpe": 7,
                "set_type": "working",
                "notes": None,
            }
            for i in range(n_sets)
        ],
    }


AUTH = {"Authorization": "Bearer test-token"}


# -- health ----------------------------------------------------------------
def test_health(client):
    r = client.get("/v1/health")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert body["uptime_s"] >= 0


# -- auth ------------------------------------------------------------------
def test_missing_token_rejected(client):
    r = client.post("/v1/sessions", json=_session())
    assert r.status_code == 401


def test_wrong_token_rejected(client):
    r = client.post(
        "/v1/sessions", json=_session(), headers={"Authorization": "Bearer nope"}
    )
    assert r.status_code == 401


def test_no_bearer_scheme_rejected(client):
    r = client.post(
        "/v1/sessions", json=_session(), headers={"Authorization": "test-token"}
    )
    assert r.status_code == 401


def test_fail_closed_when_no_token_configured(tmp_path):
    import os

    os.environ.pop("LIFT_SYNC_TOKEN", None)
    app = make_app(tmp_path / "noauth")
    with TestClient(app) as c:
        r = c.post("/v1/sessions", json=_session(), headers=AUTH)
        assert r.status_code == 503
    os.environ["LIFT_SYNC_TOKEN"] = "test-token"


# -- upsert ----------------------------------------------------------------
def test_upsert_returns_set_count(client):
    r = client.post("/v1/sessions", json=_session(), headers=AUTH)
    assert r.status_code == 200
    assert r.json() == {"ok": True, "session_id": "s1", "sets": 2}


def test_upsert_writes_frozen_header(client, tmp_path):
    client.post("/v1/sessions", json=_session(), headers=AUTH)
    first = (tmp_path / "data" / "sessions.csv").read_text().splitlines()[0]
    assert first == ",".join(CSV_HEADER)


def test_upsert_is_idempotent(client):
    client.post("/v1/sessions", json=_session(), headers=AUTH)
    client.post("/v1/sessions", json=_session(), headers=AUTH)
    r = client.get("/v1/export.csv")
    lines = [l for l in r.text.splitlines() if l]
    # header + 2 sets, no duplicates
    assert len(lines) == 3
    assert all(l.startswith("s1,") for l in lines[1:])


def test_upsert_replaces_in_place(client):
    client.post("/v1/sessions", json=_session(n_sets=2), headers=AUTH)
    client.post("/v1/sessions", json=_session(n_sets=3, weight=120.0), headers=AUTH)
    lines = [l for l in client.get("/v1/export.csv").text.splitlines() if l]
    assert len(lines) == 4  # header + 3
    assert all("120" in l for l in lines[1:])


def test_csv_row_values(client, tmp_path):
    client.post("/v1/sessions", json=_session(), headers=AUTH)
    lines = [l for l in (tmp_path / "data" / "sessions.csv").read_text().splitlines() if l]
    row = dict(zip(CSV_HEADER, lines[1].split(",")))
    assert row["session_id"] == "s1"
    assert row["date"] == "2026-09-21"
    assert row["weight_kg"] == "100"
    assert row["reps"] == "4"
    assert row["rpe"] == "7"
    assert row["exercise_type"] == "weight_reps"
    assert row["set_type"] == "working"
    assert row["notes"] == ""


def test_formula_shaped_note_is_escaped(client, tmp_path):
    payload = _session(n_sets=1)
    payload["sets"][0]["notes"] = "=HYPERLINK(\"x\")"
    client.post("/v1/sessions", json=payload, headers=AUTH)
    lines = [l for l in (tmp_path / "data" / "sessions.csv").read_text().splitlines() if l]
    assert " =HYPERLINK" in lines[1]


def test_comma_in_note_is_quoted(client, tmp_path):
    payload = _session(n_sets=1)
    payload["sets"][0]["notes"] = "felt heavy, good speed"
    client.post("/v1/sessions", json=payload, headers=AUTH)
    text = (tmp_path / "data" / "sessions.csv").read_text()
    assert '"felt heavy, good speed"' in text


# -- delete / tombstone ----------------------------------------------------
def test_delete_removes_rows(client, tmp_path):
    client.post("/v1/sessions", json=_session(), headers=AUTH)
    r = client.delete("/v1/sessions/s1", headers=AUTH)
    assert r.status_code == 200
    assert r.json()["existed"] is True
    lines = [l for l in (tmp_path / "data" / "sessions.csv").read_text().splitlines() if l]
    assert len(lines) == 1  # header only


def test_delete_records_tombstone(client, tmp_path):
    client.post("/v1/sessions", json=_session(), headers=AUTH)
    client.delete("/v1/sessions/s1", headers=AUTH)
    jsonl = (tmp_path / "data" / "sessions.jsonl").read_text().splitlines()
    assert any('"type":"delete"' in l and '"session_id":"s1"' in l for l in jsonl)


def test_tombstone_blocks_reimport(client):
    client.post("/v1/sessions", json=_session(), headers=AUTH)
    client.delete("/v1/sessions/s1", headers=AUTH)
    r = client.post("/v1/sessions", json=_session(), headers=AUTH)
    assert r.status_code == 409
    lines = [l for l in client.get("/v1/export.csv").text.splitlines() if l]
    assert len(lines) == 1  # still header only


def test_delete_absent_session_still_tombstones(client):
    r = client.delete("/v1/sessions/never-existed", headers=AUTH)
    assert r.status_code == 200
    assert r.json()["existed"] is False
    # a late upload of that id is now blocked
    r2 = client.post(
        "/v1/sessions", json=_session(sid="never-existed"), headers=AUTH
    )
    assert r2.status_code == 409


# -- concurrency -----------------------------------------------------------
def test_two_concurrent_posts_both_survive(client, tmp_path):
    """Two simultaneous POSTs must both land — the single-writer lock
    serialises them; neither loses the other's rows."""
    errors = []

    def post(sid, weight):
        try:
            r = client.post("/v1/sessions", json=_session(sid=sid, weight=weight), headers=AUTH)
            assert r.status_code == 200, r.text
        except Exception as e:  # noqa: BLE001
            errors.append(e)

    t1 = threading.Thread(target=post, args=("concurrent-a", 100.0))
    t2 = threading.Thread(target=post, args=("concurrent-b", 110.0))
    t1.start(); t2.start(); t1.join(); t2.join()
    assert not errors
    lines = [l for l in (tmp_path / "data" / "sessions.csv").read_text().splitlines() if l]
    assert len(lines) == 5  # header + 2 + 2
    assert any(l.startswith("concurrent-a,") for l in lines[1:])
    assert any(l.startswith("concurrent-b,") for l in lines[1:])


def test_concurrent_upsert_same_session_no_lost_update(client, tmp_path):
    """Hammer one session id from many threads; the file must be valid and
    hold exactly that session's final rows (no torn writes)."""
    def hit():
        client.post("/v1/sessions", json=_session(sid="hammer", n_sets=3), headers=AUTH)

    threads = [threading.Thread(target=hit) for _ in range(8)]
    for t in threads: t.start()
    for t in threads: t.join()
    text = (tmp_path / "data" / "sessions.csv").read_text()
    lines = [l for l in text.splitlines() if l]
    assert lines[0] == ",".join(CSV_HEADER)
    assert len(lines) == 4  # header + 3 sets
    assert all(l.startswith("hammer,") for l in lines[1:])


def test_no_temp_files_left_behind(client, tmp_path):
    client.post("/v1/sessions", json=_session(), headers=AUTH)
    leftovers = list((tmp_path / "data").glob(".sessions.*.tmp"))
    assert leftovers == []


# -- malformed payloads ----------------------------------------------------
def test_bad_date_rejected(client):
    payload = _session()
    payload["date"] = "21/09/2026"
    r = client.post("/v1/sessions", json=payload, headers=AUTH)
    assert r.status_code == 422


def test_bad_rpe_rejected(client):
    payload = _session(n_sets=1)
    payload["sets"][0]["rpe"] = 11
    r = client.post("/v1/sessions", json=payload, headers=AUTH)
    assert r.status_code == 422


def test_bad_exercise_type_rejected(client):
    payload = _session(n_sets=1)
    payload["sets"][0]["exercise_type"] = "teleport"
    r = client.post("/v1/sessions", json=payload, headers=AUTH)
    assert r.status_code == 422


def test_negative_weight_accepted(client):
    """Assisted bodyweight is logged as a negative weight (RepCount
    convention) — the mirror must accept it."""
    payload = _session(n_sets=1)
    payload["sets"][0]["weight_kg"] = -35.85
    r = client.post("/v1/sessions", json=payload, headers=AUTH)
    assert r.status_code == 200, r.text


def test_extreme_reps_accepted(client):
    """Data-entry errors are the validator's concern, not the mirror's."""
    payload = _session(n_sets=1)
    payload["sets"][0]["reps"] = 547
    r = client.post("/v1/sessions", json=payload, headers=AUTH)
    assert r.status_code == 200, r.text


def test_missing_session_id_rejected(client):
    payload = _session()
    del payload["session_id"]
    r = client.post("/v1/sessions", json=payload, headers=AUTH)
    assert r.status_code == 422


def test_bad_time_rejected(client):
    payload = _session()
    payload["start_time"] = "6:04"
    r = client.post("/v1/sessions", json=payload, headers=AUTH)
    assert r.status_code == 422


# -- store unit tests ------------------------------------------------------
def test_store_roundtrip(tmp_path):
    store = Store(tmp_path / "s")
    store.upsert_session(_session())
    sessions = store.load_sessions()
    assert "s1" in sessions
    assert len(sessions["s1"]) == 2
    assert store.load_tombstones() == set()
    store.delete_session("s1")
    assert store.load_sessions() == {}
    assert store.load_tombstones() == {"s1"}
