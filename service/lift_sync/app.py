"""lift-sync FastAPI app: bearer auth, upsert, delete/tombstone, health, export."""

from __future__ import annotations

import os
import re
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field, field_validator

from .store import EXERCISE_TYPES, SET_TYPES, Store

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TIME_RE = re.compile(r"^\d{2}:\d{2}$")


class SetPayload(BaseModel):
    exercise: str
    category: str | None = None
    exercise_type: str = "weight_reps"
    superset_id: str | None = None
    set_number: int
    weight_kg: float | None = None
    reps: int | None = None
    rpe: float | None = None
    duration_s: float | None = None
    distance_m: float | None = None
    kcal: float | None = None
    set_type: str | None = "working"
    notes: str | None = None

    @field_validator("exercise_type")
    @classmethod
    def _check_type(cls, v: str) -> str:
        if v not in EXERCISE_TYPES:
            raise ValueError(f"exercise_type must be one of {sorted(EXERCISE_TYPES)}")
        return v

    @field_validator("set_type")
    @classmethod
    def _check_set_type(cls, v: str | None) -> str | None:
        if v is not None and v not in SET_TYPES:
            raise ValueError(f"set_type must be one of {sorted(SET_TYPES)}")
        return v

    @field_validator("rpe")
    @classmethod
    def _check_rpe(cls, v: float | None) -> float | None:
        if v is not None and not (1.0 <= v <= 10.0):
            raise ValueError("rpe must be within 1-10 or omitted")
        return v

    @field_validator("reps")
    @classmethod
    def _check_reps(cls, v: int | None) -> int | None:
        # The service is a mirror, not a gate: the phone is the source of
        # truth and legacy history carries data-entry errors (999 reps).
        # The validator reports them; the service stores them.
        return v

    @field_validator("weight_kg")
    @classmethod
    def _check_weight(cls, v: float | None) -> float | None:
        # Negative weight is a legitimate RepCount convention for assisted
        # bodyweight (the assistance is subtracted). No bounds here.
        return v

    @field_validator("duration_s", "distance_m", "kcal")
    @classmethod
    def _check_nonneg(cls, v: float | None) -> float | None:
        if v is not None and v < 0:
            raise ValueError("must be >= 0 or omitted")
        return v


class SessionPayload(BaseModel):
    session_id: str = Field(min_length=1)
    date: str
    start_time: str | None = None
    end_time: str | None = None
    bodyweight_kg: float | None = None
    sets: list[SetPayload] = Field(default_factory=list)

    @field_validator("date")
    @classmethod
    def _check_date(cls, v: str) -> str:
        if not DATE_RE.match(v):
            raise ValueError("date must be YYYY-MM-DD")
        return v

    @field_validator("start_time", "end_time")
    @classmethod
    def _check_time(cls, v: str | None) -> str | None:
        if v is not None and not TIME_RE.match(v):
            raise ValueError("time must be HH:MM (24h)")
        return v


def make_app(data_dir: str | os.PathLike[str] | None = None) -> FastAPI:
    """Build the app. `data_dir` defaults to $LIFT_SYNC_DATA_DIR or ./data."""
    if data_dir is None:
        data_dir = os.environ.get("LIFT_SYNC_DATA_DIR", "data")
    store = Store(Path(data_dir))
    token = os.environ.get("LIFT_SYNC_TOKEN", "")

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield

    app = FastAPI(title="lift-sync", version="1.0.0", lifespan=lifespan)
    app.state.store = store

    def require_auth(request: Request) -> None:
        if not token:
            # No token configured: refuse all mutations (fail closed).
            raise HTTPException(status_code=503, detail="LIFT_SYNC_TOKEN not configured")
        header = request.headers.get("authorization", "")
        scheme, _, value = header.partition(" ")
        if scheme.lower() != "bearer" or value != token:
            raise HTTPException(status_code=401, detail="invalid bearer token")

    @app.get("/v1/health")
    def health() -> dict[str, Any]:
        return {"ok": True, "uptime_s": round(store.uptime(), 3)}

    @app.post("/v1/sessions", dependencies=[Depends(require_auth)])
    def upsert_session(payload: SessionPayload) -> dict[str, Any]:
        n = store.upsert_session(payload.model_dump())
        if n < 0:
            raise HTTPException(
                status_code=409,
                detail="session is tombstoned; re-import is not allowed",
            )
        return {"ok": True, "session_id": payload.session_id, "sets": n}

    @app.delete("/v1/sessions/{session_id}", dependencies=[Depends(require_auth)])
    def delete_session(session_id: str) -> dict[str, Any]:
        existed = store.delete_session(session_id)
        return {"ok": True, "session_id": session_id, "existed": existed}

    @app.get("/v1/export.csv")
    def export_csv() -> PlainTextResponse:
        text = store.csv_path.read_text(encoding="utf-8")
        return PlainTextResponse(text, media_type="text/csv")

    return app


app = make_app()
