#!/usr/bin/env bash
# mac-tests.sh — pull the repo on the Mac and run the iOS build plus both
# test suites over ssh. Exit non-zero on any failure (plan §7.2, T7.3).
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

run "cd $REPO_DIR && git pull --ff-only"

# 0. Regenerate the Xcode project from project.yml.
run "cd $REPO_DIR && $BREW_BIN/xcodegen generate"

# 1. Build the app.
run "cd $REPO_DIR && xcodebuild -scheme RepLog -destination '$DEST' build"

# 2. Unit tests (swift-testing).
run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' -only-testing:RepLogTests"

# 3. UI tests (XCUITest — every text-entry flow + the offline drill).
#    Start the drill supervisor on the Mac first (detached so it survives
#    this ssh session), wait for it, then run the UI tests.
ssh "$HOST" "cd $REPO_DIR && setsid nohup python3 scripts/drill_supervisor.py \
  --repo \$HOME/Documents/RepLog --port $SUPERVISOR_PORT --service-port $SERVICE_PORT \
  > $SUPERVISOR_LOG 2>&1 < /dev/null &"
# Wait for the supervisor to answer on the Mac loopback.
for i in $(seq 1 30); do
  if ssh "$HOST" "curl -s http://127.0.0.1:$SUPERVISOR_PORT/health" 2>/dev/null | grep -q '"ok"'; then
    echo "==> drill supervisor up"
    break
  fi
  sleep 1
done
run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' -only-testing:RepLogUITests"

# Stop the supervisor (and its service) now that the UI tests are done.
ssh "$HOST" "pkill -f drill_supervisor.py || true"

echo "All Mac tests passed."
