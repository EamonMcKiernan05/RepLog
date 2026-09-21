# lift-sync

A tiny self-hosted sync service for [RepLog](../README.md), the native
SwiftUI workout tracker. The phone pushes each finished session here; the
service upserts it into a flat `sessions.csv` that AI agents and the coach
pipeline can read with plain `pandas.read_csv`.

- One writer, atomic rewrites (temp file + `os.replace`)
- Upsert by `session_id` (retries and edits are idempotent)
- Delete = tombstone: a deleted session cannot be re-imported
- JSONL audit trail (`sessions.jsonl`)
- Static bearer token auth
- No database; the CSV **is** the database

## Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/v1/sessions` | Upsert one session (bearer auth) |
| `DELETE` | `/v1/sessions/{session_id}` | Delete + tombstone (bearer auth) |
| `GET` | `/v1/health` | Uptime check |
| `GET` | `/v1/export.csv` | The current file |

## Run

```bash
cd service
uv sync                      # or: pip install -e .
export LIFT_SYNC_TOKEN=$(openssl rand -hex 16)
export LIFT_SYNC_DATA_DIR=./data
uvicorn lift_sync.app:app --port 8080
```

Or with Docker:

```bash
cd service
cp .env.example .env         # fill in LIFT_SYNC_TOKEN
docker compose up --build
```

## Tests

```bash
cd service
uv run pytest -v
```

## CSV contract

See `docs/PLAN.md` §4.4 — the header is frozen:

```
session_id,date,start_time,end_time,bodyweight_kg,exercise,category,exercise_type,superset_id,set_number,weight_kg,reps,rpe,duration_s,distance_m,kcal,set_type,notes
```
