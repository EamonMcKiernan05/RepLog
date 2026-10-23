#!/usr/bin/env bash
# mac-tests.sh — the full Mac gate, one run: regenerate the project, build the
# app, run the unit suite, then the UI suite. Everything runs on the Mac over
# ssh; this script exits non-zero if any step fails.
#
# The gate is: ** BUILD SUCCEEDED ** + the unit suite + the UI suite, all
# green. Owner policy (2026-09-24): new behaviour is proven by END-TO-END (UI)
# tests, not unit tests — do not add unit tests for new work.
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

# 3. Unit tests (swift-testing).
run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' -only-testing:RepLogTests"

# 4. UI tests (XCUITest).
run "cd $REPO_DIR && xcodebuild test -scheme RepLog -destination '$DEST' \
  -only-testing:RepLogUITests \
  -skip-testing:RepLogUITests/RepLogAccessibilityTests \
  -skip-testing:RepLogUITests/RepLogVisualTourTests"

echo "All Mac tests passed."
