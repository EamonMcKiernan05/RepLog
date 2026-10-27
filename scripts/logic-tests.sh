#!/usr/bin/env bash
# logic-tests.sh — run the app's Foundation-only logic tests on THIS machine,
# with no Xcode and no simulator.
#
# Why: the Mac build host carries SwiftUI and SwiftData, but it is a single
# box that can be asleep, busy or mid-archive, and half of what breaks in this
# repo is pure logic — CSV parsing, the importer, targets, metrics. Those files
# import Foundation only, so a plain Swift toolchain compiles and tests them
# anywhere. This is a FAST gate (seconds); it is not the Mac gate and must not
# be quoted as "the suite passed".
#
# What it covers: whatever is listed in SOURCES plus every test file listed in
# TESTS. Keep both lists current when a Foundation-only file is added.
#
#   scripts/logic-tests.sh
#
# Requires `swift` (Xcode toolchain on macOS, swiftlang on Linux).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/replog-logic.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

SOURCES=(
  "Engine/CSVFields.swift"
  "Engine/RoutineCSV.swift"
)
TESTS=(
  "Tests/Unit/RoutineCSVTests.swift"
)

mkdir -p "$WORK/Sources/RepLogLogic" "$WORK/Tests/RepLogLogicTests"
cat > "$WORK/Package.swift" <<'PKG'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RepLogLogic",
    targets: [
        .target(name: "RepLogLogic"),
        .testTarget(name: "RepLogLogicTests", dependencies: ["RepLogLogic"]),
    ]
)
PKG

for f in "${SOURCES[@]}"; do
  cp "$ROOT/$f" "$WORK/Sources/RepLogLogic/$(basename "$f")"
done
for f in "${TESTS[@]}"; do
  # The app target is called RepLog; here it is RepLogLogic.
  sed 's/@testable import RepLog$/@testable import RepLogLogic/' "$ROOT/$f" \
    > "$WORK/Tests/RepLogLogicTests/$(basename "$f")"
done

cd "$WORK"
# swift-testing reports through its own runner; XCTest's "Executed 0 tests" line
# is not the result and must not be read as one.
if ! OUT="$(swift test 2>&1)"; then
  echo "$OUT" | grep -E "error:|✘|failed" | head -40
  exit 1
fi
echo "$OUT" | grep -E "✔ Test run with|error:" || true
if ! echo "$OUT" | grep -q "Test run with .* tests passed"; then
  echo "no swift-testing results — the test target did not run" >&2
  exit 1
fi
