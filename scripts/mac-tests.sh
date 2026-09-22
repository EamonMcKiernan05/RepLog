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

run() {
  echo "==> $*"
  ssh "$HOST" "$*"
}

run "cd $REPO_DIR && git pull --ff-only"

# 1. Build the app.
run "cd $REPO_DIR && xcodebuild -scheme RepLog -destination '$DEST' build"

# 2. Unit tests (swift-testing).
run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' -only-testing:RepLogTests"

# 3. UI tests (XCUITest — every text-entry flow).
run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' -only-testing:RepLogUITests"

echo "All Mac tests passed."
