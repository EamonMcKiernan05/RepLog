#!/usr/bin/env bash
# mac-tests.sh — the full Mac gate, one run: regenerate the project, build the
# app, run the unit suite, then the UI suite (including the in-simulator
# offline drill, plan §7.5/T7.3). Everything runs on the Mac over ssh; this
# script exits non-zero if any step fails.
#
# The gate is: ** BUILD SUCCEEDED ** + 36/36 unit + 7/7 UI.
# The accessibility-audit class is excluded here on purpose (it REPORTS
# issues instead of gating on them); run it standalone with
#   -only-testing:RepLogUITests/RepLogAccessibilityTests
#
# Usage:
#   scripts/mac-tests.sh [mac-host]     # default host: mac
set -euo pipefail

HOST="${1:-mac}"
DEST="platform=iOS Simulator,name=iPhone 17 Pro"
REPO_DIR="~/Documents/RepLog"
# xcodegen + agent-device live in Homebrew, which is not on the
# non-interactive SSH PATH.
BREW_BIN="/opt/homebrew/bin"
# The offline-drill supervisor (scripts/drill_supervisor.py) runs on the Mac
# and gives the iOS-compiled UI test control over a disposable lift-sync
# service. Supervisor: 127.0.0.1:8392 (Mac loopback). Service: 0.0.0.0:8391
# (the simulator reaches it via the Mac's NAT gateway).
SUPERVISOR_PORT=8392
SERVICE_PORT=8391
SUPERVISOR_LOG="/tmp/replog-drill-supervisor.log"

run() {
  echo "==> $*"
  ssh "$HOST" "$*"
}

# Always stop the drill supervisor, however this script exits — an orphan
# holds 8392 and serves stale state to the next run (which then reads as a
# flaky test).
stop_supervisor() {
  ssh -o ConnectTimeout=10 "$HOST" "pkill -f drill_supervisor.py || true" >/dev/null 2>&1 || true
}
trap stop_supervisor EXIT

# 0. Kill any supervisor left over from a previous run, before anything else.
echo "==> stopping any stale drill supervisor"
stop_supervisor

run "cd $REPO_DIR && git pull --ff-only"

# 1. Regenerate the Xcode project from project.yml.
run "cd $REPO_DIR && $BREW_BIN/xcodegen generate"

# 2. Build the app (plus the RepLogWidget extension).
run "cd $REPO_DIR && xcodebuild -scheme RepLog -destination '$DEST' build"

# 3. Unit tests (swift-testing).
run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' -only-testing:RepLogTests"

# 4. UI tests (XCUITest — every text-entry flow + the offline drill).
#    Start the drill supervisor on the Mac first (detached so it survives
#    this ssh session), wait for it, then run the UI suite. The audit class
#    is excluded; this run must be exactly the 7 gating tests.
ssh "$HOST" "cd $REPO_DIR && nohup python3 scripts/drill_supervisor.py \
  --repo \$HOME/Documents/RepLog --port $SUPERVISOR_PORT --service-port $SERVICE_PORT \
  > $SUPERVISOR_LOG 2>&1 < /dev/null & disown"

# Wait for the supervisor to answer on the Mac loopback; a missing
# supervisor must fail the gate (the drill otherwise reports itself as a
# skip, which is not a pass).
supervisor_up=""
for i in $(seq 1 30); do
  if ssh -o ConnectTimeout=10 "$HOST" "curl -s http://127.0.0.1:$SUPERVISOR_PORT/health" 2>/dev/null | grep -q '"ok"'; then
    supervisor_up=1
    break
  fi
  sleep 1
done
if [ -z "$supervisor_up" ]; then
  echo "ERROR: drill supervisor did not come up on 127.0.0.1:$SUPERVISOR_PORT" >&2
  exit 1
fi
echo "==> drill supervisor up"

run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' \
  -only-testing:RepLogUITests \
  -skip-testing:RepLogUITests/RepLogAccessibilityTests \
  -skip-testing:RepLogUITests/RepLogVisualTourTests"

echo "All Mac tests passed."
