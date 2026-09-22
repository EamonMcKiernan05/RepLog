#!/usr/bin/env python3
"""Drill supervisor for the in-simulator offline drill (plan §7.5).

The XCUITest bundle runs on the Mac host but is compiled for iOS, so it
cannot spawn processes (Foundation.Process is macOS-only). This small
stdlib-only HTTP server is started by scripts/mac-tests.sh and gives the
test control over a disposable lift-sync service:

  POST /start  -> start uvicorn (fresh data dir, fixed test token), wait for health
  POST /stop   -> terminate uvicorn
  GET  /csv    -> the service's sessions.csv ("" when down)
  GET  /audit  -> the service's sessions.jsonl ("" when down)
  GET  /health -> supervisor alive

The service binds 0.0.0.0 so the iOS simulator can reach it via its
gateway to the Mac host (172.168.100.1). The token is a fixed local test
value for a throwaway service — not a production credential.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = "uitest-drill-token"


def gateway_ip() -> str:
    """The Mac's NAT gateway IP, which the iOS simulator routes through to
    reach host services (the simulator's own loopback is not the Mac's).
    macOS: `route -n get default` -> the `gateway:` line."""
    try:
        out = subprocess.check_output(
            ["route", "-n", "get", "default"], text=True, timeout=5
        )
        for line in out.splitlines():
            if line.strip().startswith("gateway:"):
                return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return "172.168.100.1"


class Supervisor:
    def __init__(self, repo: str, service_port: int) -> None:
        self.repo = repo
        self.service_port = service_port
        self.proc: subprocess.Popen | None = None
        self.data_dir: str | None = None

    @property
    def base(self) -> str:
        return f"http://127.0.0.1:{self.service_port}"

    def _health(self) -> bool:
        try:
            with urllib.request.urlopen(f"{self.base}/v1/health", timeout=2) as r:
                return r.status == 200
        except Exception:
            return False

    def start(self) -> dict:
        self.stop()
        self.data_dir = tempfile.mkdtemp(prefix="replog-drill-")
        uvicorn = os.path.join(self.repo, "service", ".venv", "bin", "uvicorn")
        if not os.path.exists(uvicorn):
            return {"ok": False, "error": f"uvicorn not found at {uvicorn}"}
        env = dict(os.environ)
        env["LIFT_SYNC_DATA_DIR"] = self.data_dir
        env["LIFT_SYNC_TOKEN"] = TOKEN
        log = open(os.path.join(self.data_dir, "uvicorn.log"), "ab")
        self.proc = subprocess.Popen(
            [uvicorn, "lift_sync.app:app", "--port", str(self.service_port),
             "--host", "0.0.0.0", "--log-level", "warning"],
            cwd=os.path.join(self.repo, "service"),
            env=env, stdout=log, stderr=log,
            preexec_fn=os.setsid,
        )
        for _ in range(60):
            if self._health():
                return {"ok": True, "data_dir": self.data_dir, "token": TOKEN,
                        "port": self.service_port, "gateway": gateway_ip()}
            time.sleep(0.5)
        return {"ok": False, "error": "service did not come up"}

    def stop(self) -> None:
        if self.proc is not None:
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
            self.proc = None

    def read(self, name: str) -> str:
        if not self.data_dir:
            return ""
        path = os.path.join(self.data_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as fh:
                return fh.read()
        except FileNotFoundError:
            return ""


class Handler(BaseHTTPRequestHandler):
    sup: Supervisor

    def log_message(self, format, *args) -> None:  # keep the log quiet
        pass

    def _send(self, code: int, payload: dict | str) -> None:
        body = payload if isinstance(payload, str) else json.dumps(payload)
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain" if isinstance(payload, str) else "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._send(200, {"ok": True})
        elif self.path == "/csv":
            self._send(200, self.sup.read("sessions.csv"))
        elif self.path == "/audit":
            self._send(200, self.sup.read("sessions.jsonl"))
        else:
            self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path == "/start":
            self._send(200, self.sup.start())
        elif self.path == "/stop":
            self.sup.stop()
            self._send(200, {"ok": True})
        else:
            self._send(404, {"ok": False, "error": "not found"})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--port", type=int, default=8392)
    ap.add_argument("--service-port", type=int, default=8391)
    args = ap.parse_args()

    sup = Supervisor(repo=args.repo, service_port=args.service_port)
    Handler.sup = sup
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"drill supervisor on 127.0.0.1:{args.port} (service port {args.service_port})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        sup.stop()


if __name__ == "__main__":
    main()
