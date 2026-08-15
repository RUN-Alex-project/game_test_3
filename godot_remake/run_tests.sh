#!/usr/bin/env bash
# Thin Linux/macOS wrapper: all test logic lives in tools/run_tests.py.
# The test registry is tests/test_manifest.json (platform-neutral, single source of truth).
# -u keeps python output unbuffered so CI logs stream scene results live.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec python3 -u "${SCRIPT_DIR}/tools/run_tests.py" "$@"
