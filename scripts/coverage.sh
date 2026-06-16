#!/usr/bin/env bash
#
# Runs the SwiftPM test suite with coverage and fails if total line coverage
# for our own source targets falls below THRESHOLD.
#
# Excluded from the measurement: tests, external deps, and pure SwiftUI `*View`
# files. SwiftUI view bodies are declarative and exercised by the XCUITest on
# the simulator (the `app` CI job), not by `swift test`; measuring unit-coverage
# on them distorts the metric. View MODELS (e.g. EditorModel) are logic and ARE
# measured.
#
# Usage: scripts/coverage.sh [threshold]   (default 90)
set -euo pipefail

THRESHOLD="${1:-90}"
# Files excluded from unit-coverage (see note above).
IGNORE='(Tests|\.build|checkouts)/|View\.swift$'

echo "==> Running tests with coverage"
swift test --enable-code-coverage >/dev/null

BIN_DIR="$(swift build --show-bin-path)"
PROFDATA="$(find "${BIN_DIR}/codecov" -name '*.profdata' | head -1)"

# Locate the compiled test bundle binary (name ends in PackageTests).
XCTEST="$(find "${BIN_DIR}" -name '*PackageTests.xctest' -print -quit)"
if [[ "$(uname)" == "Darwin" ]]; then
  TEST_BIN="${XCTEST}/Contents/MacOS/$(basename "${XCTEST}" .xctest)"
else
  TEST_BIN="${XCTEST}"
fi

echo "==> Computing coverage (threshold ${THRESHOLD}%)"
# Only measure our Sources/, ignore Tests/ and checkouts.
PERCENT="$(xcrun llvm-cov report \
  "${TEST_BIN}" \
  -instr-profile "${PROFDATA}" \
  -ignore-filename-regex="${IGNORE}" \
  2>/dev/null | awk '/^TOTAL/ { gsub(/%/,"",$10); print $10 }')"

echo "Total line coverage: ${PERCENT}%"

# Per-file breakdown for visibility in CI logs.
xcrun llvm-cov report \
  "${TEST_BIN}" \
  -instr-profile "${PROFDATA}" \
  -ignore-filename-regex="${IGNORE}" \
  2>/dev/null || true

awk -v p="${PERCENT}" -v t="${THRESHOLD}" 'BEGIN {
  if (p+0 < t+0) { printf "FAIL: coverage %.2f%% < %.2f%%\n", p, t; exit 1 }
  printf "OK: coverage %.2f%% >= %.2f%%\n", p, t
}'
