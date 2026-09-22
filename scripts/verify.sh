#!/usr/bin/env bash
# verify.sh — the fast, deterministic gate. Seconds, not minutes.
#
# Runs the things that can fail silently without a compiler:
#   1. the lift-sync service's pytest suite (upsert, tombstones, auth,
#      concurrent writes, malformed payloads);
#   2. scripts/validate_sessions.py over the committed CSV fixtures — the
#      frozen §4.4 header and column order, ISO dates, rpe 1-10 or blank,
#      exercise_type/set_type enums, duplicate set keys.
#
# Exit code 0 = green; anything else = red. No network, no simulator, no Mac.
#
# Usage: bash scripts/verify.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> service pytest suite"
(cd service && ./.venv/bin/python -m pytest -q)

echo "==> validate committed CSV fixtures (frozen §4.4 header)"
for f in Tests/Fixtures/*.csv; do
  python3 scripts/validate_sessions.py "$f"
done

echo "verify.sh: PASS"
