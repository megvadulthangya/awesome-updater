#!/usr/bin/env bash
#
# tests/run-tests.sh
#
# Test suite runner for awesome-updater.
#
# Discovers and executes tests/test-*.sh, aggregates their results, prints
# a summary, and exits non-zero when any test fails.
#
# Every test file is fully isolated: no real package manager, no real
# reboot, no real cron, no real sudo, no network access.

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TESTS_DIR

# Ensure mocks are executable. Contents are never modified; only the
# executable bit is set if it happens to be missing.
if [ -d "$TESTS_DIR/mocks" ]; then
    chmod +x "$TESTS_DIR"/mocks/* 2>/dev/null || true
fi

if [ -t 1 ]; then
    RED=$'\033[1;31m'
    GREEN=$'\033[1;32m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED=""; GREEN=""; BOLD=""; NC=""
fi

TOTAL=0
PASSED=0
FAILED=0
FAILED_FILES=()

# Optional filter: pass test file paths as arguments.
if [ "$#" -gt 0 ]; then
    FILES=("$@")
else
    FILES=()
    while IFS= read -r -d '' f; do
        FILES+=("$f")
    done < <(find "$TESTS_DIR" -maxdepth 1 -name 'test-*.sh' -print0 | sort -z)
fi

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No test files found under $TESTS_DIR"
    exit 1
fi

for f in "${FILES[@]}"; do
    rel="${f#$TESTS_DIR/}"
    echo
    echo "${BOLD}==> ${rel}${NC}"

    out="$(bash "$f" 2>&1)"
    rc=$?
    printf '%s\n' "$out"

    ft="$(printf '%s\n' "$out" | sed -n 's/^SUMMARY_TOTAL=//p' | tail -n1)"
    fp="$(printf '%s\n' "$out" | sed -n 's/^SUMMARY_PASSED=//p' | tail -n1)"
    ff="$(printf '%s\n' "$out" | sed -n 's/^SUMMARY_FAILED=//p' | tail -n1)"

    TOTAL=$((TOTAL + ${ft:-0}))
    PASSED=$((PASSED + ${fp:-0}))
    FAILED=$((FAILED + ${ff:-0}))

    if [ "$rc" -ne 0 ] || [ "${ff:-0}" -gt 0 ]; then
        FAILED_FILES+=("$rel")
    fi
done

echo
echo "${BOLD}============================================================${NC}"
echo "Tests:  $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "${BOLD}============================================================${NC}"

if [ "$FAILED" -gt 0 ]; then
    echo
    echo "${RED}Failed test files:${NC}"
    for f in "${FAILED_FILES[@]}"; do
        echo "  $f"
    done
    exit 1
fi

if [ "$TOTAL" -eq 0 ]; then
    echo "${RED}No tests were executed.${NC}"
    exit 1
fi

echo
echo "${GREEN}All tests passed.${NC}"
exit 0