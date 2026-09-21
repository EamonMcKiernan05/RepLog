"""The CSV store: single-writer, atomic rewrites, tombstones.

Design (plan §4.2):
- One lock serialises every mutation.
- The file is rewritten to a temp file and `os.rename`d into place, so a
  crash mid-write never leaves a torn CSV.
- Deletes are tombstones: the session id is recorded in sessions.jsonl and
  the rows are removed, so a later re-import of the same session cannot
  resurrect it.
- Readers (agents, the coach pipeline) open the CSV read-only; this module
  is the only writer.
"""

from __future__ import annotations

import json
import os
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# Frozen CSV contract v1 (plan §4.4). Order and spelling are the contract.
CSV_HEADER = [
    "session_id",
    "date",
    "start_time",
    "end_time",
    "bodyweight_kg",
    "exercise",
    "category",
    "exercise_type",
    "superset_id",
    "set_number",
    "weight_kg",
    "reps",
    "rpe",
    "duration_s",
    "distance_m",
    "kcal",
    "set_type",
    "notes",
]

EXERCISE_TYPES = {
    "weight_reps",
    "weight_time",
    "bw_weight_reps",
    "bw_assisted",
    "bw_reps",
    "bw_time",
    "cardio",
    "note",
}

SET_TYPES = {"working", "warmup", "drop"}

# A set row as the service stores it. All values are strings or None so the
# CSV round-trips exactly; numeric parsing is the reader's job.
SetRow = dict[str, Any]


@dataclass
class Store:
    """Holds the on-disk state and serialises mutations behind one lock."""

    data_dir: Path
    _lock: threading.Lock = field(default_factory=threading.Lock, init=False)
    _started_at: float = field(default_factory=time.time, init=False)

    def __post_init__(self) -> None:
        self.data_dir = Path(self.data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        if not self.csv_path.exists():
            self._write_csv({})
            self._append_audit({"type": "init", "ts": _now()})

    # -- paths -------------------------------------------------------------
    @property
    def csv_path(self) -> Path:
        return self.data_dir / "sessions.csv"

    @property
    def jsonl_path(self) -> Path:
        return self.data_dir / "sessions.jsonl"

    # -- reading -----------------------------------------------------------
    def load_sessions(self) -> dict[str, list[SetRow]]:
        """Return {session_id: [set rows]} in file order."""
        sessions: dict[str, list[SetRow]] = {}
        if not self.csv_path.exists():
            return sessions
        text = self.csv_path.read_text(encoding="utf-8")
        for line in text.splitlines():
            if not line:
                continue
            row = _parse_line(line)
            if row is None or row.get("session_id") == "":
                continue
            sessions.setdefault(row["session_id"], []).append(row)
        return sessions

    def load_tombstones(self) -> set[str]:
        """Session ids that have been deleted on the server."""
        tombstones: set[str] = set()
        if not self.jsonl_path.exists():
            return tombstones
        with self.jsonl_path.open("r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get("type") == "delete":
                    sid = event.get("session_id")
                    if sid:
                        tombstones.add(sid)
        return tombstones

    # -- mutations (all behind the lock) ------------------------------------
    def upsert_session(self, session: dict[str, Any]) -> int:
        """Insert or replace one session. Returns the number of set rows.

        `session` must carry `session_id` and a `sets` list of set dicts.
        A re-upsert of a tombstoned session is rejected (returns -1) so a
        re-import cannot resurrect a deleted session.
        """
        sid = session.get("session_id")
        if not sid:
            raise ValueError("session_id is required")
        sets = session.get("sets", [])
        with self._lock:
            if sid in self.load_tombstones():
                self._append_audit(
                    {"type": "rejected_tombstone", "session_id": sid, "ts": _now()}
                )
                return -1
            sessions = self.load_sessions()
            sessions[sid] = [_normalise_set(s, sid, session) for s in sets]
            self._write_csv(sessions)
            self._append_audit(
                {
                    "type": "upsert",
                    "session_id": sid,
                    "sets": len(sets),
                    "ts": _now(),
                }
            )
            return len(sets)

    def delete_session(self, session_id: str) -> bool:
        """Remove a session's rows and record a tombstone.

        Returns True if rows were removed, False if the session was absent
        (the tombstone is still recorded so a late re-import is blocked).
        """
        with self._lock:
            sessions = self.load_sessions()
            existed = session_id in sessions
            sessions.pop(session_id, None)
            self._write_csv(sessions)
            self._append_audit(
                {"type": "delete", "session_id": session_id, "ts": _now()}
            )
            return existed

    # -- internals -----------------------------------------------------------
    def _write_csv(self, sessions: dict[str, list[SetRow]]) -> None:
        lines = [",".join(CSV_HEADER)]
        for sid, rows in sessions.items():
            for row in rows:
                lines.append(
                    ",".join(_csv_field(row.get(col)) for col in CSV_HEADER)
                )
        data = ("\n".join(lines) + "\n").encode("utf-8")
        tmp = self.data_dir / f".sessions.{uuid.uuid4().hex}.tmp"
        tmp.write_bytes(data)
        os.replace(tmp, self.csv_path)

    def _append_audit(self, event: dict[str, Any]) -> None:
        with self.jsonl_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(event, separators=(",", ":")) + "\n")

    def uptime(self) -> float:
        return time.time() - self._started_at


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _normalise_set(raw: dict[str, Any], sid: str, session: dict[str, Any]) -> SetRow:
    """Coerce a set dict into the frozen column set, strings or None."""
    row: SetRow = {"session_id": sid}
    for col in CSV_HEADER[1:]:
        if col in ("exercise", "category"):
            row[col] = raw.get(col) or None
        elif col in ("date", "start_time", "end_time"):
            row[col] = session.get(col) or raw.get(col) or None
        elif col == "bodyweight_kg":
            row[col] = _num_or_none(session.get("bodyweight_kg", raw.get("bodyweight_kg")))
        elif col == "exercise_type":
            et = raw.get("exercise_type") or "weight_reps"
            row[col] = et if et in EXERCISE_TYPES else "weight_reps"
        elif col == "superset_id":
            row[col] = raw.get("superset_id") or None
        elif col == "set_number":
            row[col] = _num_or_none(raw.get("set_number"))
        elif col in ("weight_kg", "reps", "rpe", "duration_s", "distance_m", "kcal"):
            row[col] = _num_or_none(raw.get(col))
        elif col == "set_type":
            st = raw.get("set_type") or None
            row[col] = st if st in SET_TYPES else None
        else:  # notes
            row[col] = raw.get("notes") or None
    return row


def _num_or_none(value: Any) -> str | None:
    """Render a number the way the CSV wants it: no trailing .0, else None."""
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if value == int(value):
            return str(int(value))
        return repr(value)
    text = str(value).strip()
    if text == "":
        return None
    try:
        num = float(text)
    except ValueError:
        return None
    if num == int(num):
        return str(int(num))
    return str(num)


def _csv_field(value: Any) -> str:
    """One CSV cell: quote when needed; escape formula-shaped text."""
    if value is None:
        return ""
    text = str(value)
    if text == "":
        return ""
    # Escape leading formula characters so Excel cannot treat the cell as a
    # formula. A leading space keeps the text identical when read back.
    if text[0] in ("=", "+", "-", "@"):
        text = " " + text
    if any(ch in text for ch in (",", '"', "\n", "\r")):
        return '"' + text.replace('"', '""') + '"'
    return text


def _parse_line(line: str) -> dict[str, Any] | None:
    """Parse one CSV line back into a dict keyed by the frozen header."""
    if line.startswith(",".join(CSV_HEADER)):
        return None
    values = _split_csv_line(line)
    if len(values) != len(CSV_HEADER):
        return None
    row = dict(zip(CSV_HEADER, values))
    # Undo the formula escape: a leading space we added.
    for col in CSV_HEADER:
        v = row.get(col)
        if isinstance(v, str) and v.startswith(" ") and v[1:2] in ("=", "+", "-", "@"):
            row[col] = v[1:]
    return row


def _split_csv_line(line: str) -> list[str]:
    out: list[str] = []
    cur: list[str] = []
    in_quotes = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_quotes:
            if ch == '"':
                if i + 1 < len(line) and line[i + 1] == '"':
                    cur.append('"')
                    i += 2
                    continue
                in_quotes = False
                i += 1
                continue
            cur.append(ch)
            i += 1
            continue
        if ch == '"':
            in_quotes = True
            i += 1
            continue
        if ch == ",":
            out.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    out.append("".join(cur))
    return out
