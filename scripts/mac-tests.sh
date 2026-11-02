#!/usr/bin/env bash
# mac-tests.sh — the Mac gate, one run: regenerate the project, build the app,
# then the UI suite. Everything runs on the Mac over ssh; this script exits
# non-zero if any step fails.
#
# The gate is: ** BUILD SUCCEEDED ** + the UI suite, all green. Owner policy
# (2026-09-24, restated 2026-10-27): new behaviour is proven by END-TO-END (UI)
# tests only. The unit suite is NOT part of this gate — the old unit files are
# still in Tests/Unit but nothing runs them.
# The accessibility-audit class is excluded here on purpose (it REPORTS
# issues instead of gating on them); run it standalone with
#   -only-testing:RepLogUITests/RepLogAccessibilityTests
#
# The offline drill and its supervisor are gone with sync (2026-10-23): there
# is no service to be offline from, and the app's only way off the phone is a
# CSV export.
#
# Usage:
#   scripts/mac-tests.sh [mac-host]     # default host: mac
set -euo pipefail

HOST="${1:-mac}"
DEST="platform=iOS Simulator,name=iPhone 17 Pro"
REPO_DIR="~/Documents/RepLog"
# xcodegen lives in Homebrew, which is not on the non-interactive SSH PATH.
BREW_BIN="/opt/homebrew/bin"

run() {
  echo "==> $*"
  ssh "$HOST" "$*"
}

run "cd $REPO_DIR && git pull --ff-only"

# 1. Regenerate the Xcode project from project.yml.
run "cd $REPO_DIR && $BREW_BIN/xcodegen generate"

# 2. Build the app (plus the RepLogWidget extension).
run "cd $REPO_DIR && xcodebuild -scheme RepLog -destination '$DEST' build"

# 3. UI tests (XCUITest).
run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' \
  -only-testing:RepLogUITests \
  -skip-testing:RepLogUITests/RepLogAccessibilityTests \
  -skip-testing:RepLogUITests/RepLogVisualTourTests"

echo "All Mac tests passed."
