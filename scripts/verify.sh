#!/usr/bin/env bash
# verify.sh — the fast, deterministic gate. Seconds, not minutes.
#
# Runs the checks that can fail silently without a compiler: the frozen CSV
# schema (§4.4 header and column order), ISO dates, rpe 1-10 or blank,
# exercise_type/set_type enums, duplicate set keys — over the committed
# golden fixtures in Tests/Fixtures.
#
# Exit code 0 = green; anything else = red. No network, no simulator, no Mac.
#
# Usage: bash scripts/verify.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> validate the committed CSV fixtures (frozen §4.4 header)"
for f in Tests/Fixtures/*.csv; do
  python3 scripts/validate_sessions.py "$f"
done

echo "verify.sh: PASS"
