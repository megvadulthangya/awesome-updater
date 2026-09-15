#!/usr/bin/env bash
#
# tests/lib/harness.sh
#
# Shared test harness for the awesome-updater test suite.
#
# Responsibilities:
#   * build a sandboxed environment mirroring the runtime layout
#   * rewrite the production scripts so that every hard-coded absolute
#     path points inside the sandbox
#   * expose run_updater / run_notify / run_profile_hook helpers
#   * provide assertions and PASS/FAIL reporting
#
# The production files are never modified. Only copies placed inside the
# sandbox are transformed.

# shellcheck shell=bash

TESTS_DIR="${TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
export TESTS_DIR PROJECT_DIR

REAL_PATH="${REAL_PATH:-$PATH}"
REAL_HOME="${REAL_HOME:-$HOME}"
export REAL_PATH REAL_HOME

HARNESS_TOTAL=0
HARNESS_PASSED=0
HARNESS_FAILED=0

SANDBOX=""
SANDBOX_HOME=""
SANDBOX_PATH=""
SANDBOX_MOCK_LOG=""
MOCK_LOG=""
UPDATER_OUTPUT=""
UPDATER_EXIT=0
NOTIFY_OUTPUT=""
NOTIFY_EXIT=0
PROFILE_OUTPUT=""
PROFILE_EXIT=0

# ---------------------------------------------------------------------------
# Test reporting
# ---------------------------------------------------------------------------

t() {
    local name="$1"
    HARNESS_TOTAL=$((HARNESS_TOTAL + 1))

    if "$name"; then
        printf '  PASS: %s\n' "$name"
        HARNESS_PASSED=$((HARNESS_PASSED + 1))
    else
        printf '  FAIL: %s\n' "$name"
        HARNESS_FAILED=$((HARNESS_FAILED + 1))
    fi
}

summary() {
    echo "SUMMARY_TOTAL=$HARNESS_TOTAL"
    echo "SUMMARY_PASSED=$HARNESS_PASSED"
    echo "SUMMARY_FAILED=$HARNESS_FAILED"
    if [ "$HARNESS_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Sandbox setup
# ---------------------------------------------------------------------------

sandbox_cleanup() {
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        if [ "${KEEP_SANDBOX:-0}" = "1" ]; then
            echo "  (kept sandbox: $SANDBOX)"
        else
            rm -rf "$SANDBOX"
        fi
    fi
    SANDBOX=""
    SANDBOX_HOME=""
    SANDBOX_PATH=""
    SANDBOX_MOCK_LOG=""
    MOCK_LOG=""
}

sandbox_prepare() {
    sandbox_cleanup

    SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/sut.XXXXXX")"
    SANDBOX_HOME="$SANDBOX/home"
    SANDBOX_MOCK_LOG="$SANDBOX/mock.log"
    MOCK_LOG="$SANDBOX_MOCK_LOG"

    mkdir -p \
        "$SANDBOX_HOME/.config/system-update" \
        "$SANDBOX_HOME/.config/autostart" \
        "$SANDBOX_HOME/logs" \
        "$SANDBOX/var/lib/system-update" \
        "$SANDBOX/etc/system-update" \
        "$SANDBOX/etc/profile.d" \
        "$SANDBOX/usr/bin" \
        "$SANDBOX/usr/local/bin" \
        "$SANDBOX/tmp" \
        "$SANDBOX/mock-state"

    : > "$SANDBOX_MOCK_LOG"

    SANDBOX_PATH="$TESTS_DIR/mocks:$SANDBOX/usr/bin:$SANDBOX/usr/local/bin:$REAL_PATH"

    _prepare_script "$PROJECT_DIR/system-update" \
        "$SANDBOX/usr/bin/system-update" 0755
    _prepare_script "$PROJECT_DIR/system-update-notify" \
        "$SANDBOX/usr/bin/system-update-notify" 0755
    _prepare_script "$PROJECT_DIR/profile.d/99-system-update.sh" \
        "$SANDBOX/etc/profile.d/99-system-update.sh" 0644

    # Default mock environment. Tests override as needed.
    export MOCK_LOG="$SANDBOX_MOCK_LOG"
    export MOCK_STATE_DIR="$SANDBOX/mock-state"
    export MOCK_SUDO_N_OK=0
    export MOCK_PACMAN_INSTALLED=""
    export MOCK_PACMAN_Q_FILE=""
    export MOCK_PACMAN_Q_FILE_1=""
    export MOCK_PACMAN_Q_FILE_2=""
    export MOCK_PACMAN_QO=""
    export MOCK_PACMAN_SYU_EXIT=0
    export MOCK_PACMAN_S_EXIT=0
    export MOCK_SYSTEMCTL_ACTIVE_UNITS=""
    export MOCK_SYSTEMD_RUN_EXIT=0
    export MOCK_MHWD_OUTPUT=""
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    export MOCK_HOSTNAME="test-host"
    export MOCK_ID_U=1000
    export MOCK_CRONTAB_FILE="$SANDBOX/crontab.txt"
    export MOCK_CRONTAB_INSTALL_EXIT=0
    export MOCK_YAY_EXIT=0
    export MOCK_NOTIFY_SEND_EXIT=0
    export MOCK_WALL_EXIT=0
    export MOCK_VERCMP_EXIT=""
    export MOCK_GIT_EXIT=0
    export MOCK_MAKEPKG_EXIT=0
    export SANDBOX SANDBOX_HOME SANDBOX_PATH SANDBOX_MOCK_LOG
}

_prepare_script() {
    local src="$1"
    local dst="$2"
    local mode="$3"

    sed \
        -e "s|/var/lib/system-update|$SANDBOX/var/lib/system-update|g" \
        -e "s|/etc/system-update|$SANDBOX/etc/system-update|g" \
        -e "s|/etc/profile.d/99-system-update.sh|$SANDBOX/etc/profile.d/99-system-update.sh|g" \
        -e "s|/usr/bin/system-update|$SANDBOX/usr/bin/system-update|g" \
        -e "s|/usr/local/bin/system-update|$SANDBOX/usr/local/bin/system-update|g" \
        -e "s|/tmp/system-update.lock|$SANDBOX/tmp/system-update.lock|g" \
        -e "s|find /etc |find $SANDBOX/etc |g" \
        "$src" > "$dst"

    chmod "$mode" "$dst"
}

# ---------------------------------------------------------------------------
# Config writers
#
# These accept the entire configuration content as a single argument. They
# MUST NOT read from stdin: on CI runners the test process's stdin is not
# a terminal and may carry unexpected bytes, which previously caused the
# sandbox config to be populated with garbage.
# ---------------------------------------------------------------------------

write_config() {
    if [ "$#" -ge 1 ]; then
        printf '%s\n' "$1" > "$SANDBOX/etc/system-update/config.conf"
    else
        : > "$SANDBOX/etc/system-update/config.conf"
    fi
}

write_user_config() {
    if [ "$#" -ge 1 ]; then
        printf '%s\n' "$1" > "$SANDBOX_HOME/.config/system-update/config.conf"
    else
        : > "$SANDBOX_HOME/.config/system-update/config.conf"
    fi
}

# ---------------------------------------------------------------------------
# Mock setup helpers
# ---------------------------------------------------------------------------

setup_pacman_q() {
    local content="$1"
    local f="$SANDBOX/pacman_q.$$"
    printf '%s\n' "$content" > "$f"
    export MOCK_PACMAN_Q_FILE="$f"
}

setup_pacman_before_after() {
    local before="$1"
    local after="$2"
    local fb="$SANDBOX/pacman_q_before.$$"
    local fa="$SANDBOX/pacman_q_after.$$"
    printf '%s\n' "$before" > "$fb"
    printf '%s\n' "$after" > "$fa"
    export MOCK_PACMAN_Q_FILE_1="$fb"
    export MOCK_PACMAN_Q_FILE_2="$fa"
}

# ---------------------------------------------------------------------------
# Runtime invocation helpers
#
# Stdin is redirected to /dev/null so the runtime can never consume bytes
# from the CI runner's stdin.
# ---------------------------------------------------------------------------

run_updater() {
    local args=("$@")

    set +e
    UPDATER_OUTPUT="$(
        PATH="$SANDBOX_PATH" HOME="$SANDBOX_HOME" \
            bash "$SANDBOX/usr/bin/system-update" "${args[@]}" \
            </dev/null 2>&1
    )"
    UPDATER_EXIT=$?
    set -e

    sleep 0.1
}

run_notify() {
    local args=("$@")

    set +e
    NOTIFY_OUTPUT="$(
        PATH="$SANDBOX_PATH" HOME="$SANDBOX_HOME" \
            bash "$SANDBOX/usr/bin/system-update-notify" "${args[@]}" \
            </dev/null 2>&1
    )"
    NOTIFY_EXIT=$?
    set -e

    sleep 0.05
}

run_profile_hook() {
    local hook="$SANDBOX/etc/profile.d/99-system-update.sh"

    set +e
    PROFILE_OUTPUT="$(
        PATH="$SANDBOX_PATH" HOME="$SANDBOX_HOME" \
            bash --norc --noprofile -i -c "source \"$hook\"" \
            </dev/null 2>/dev/null
    )"
    PROFILE_EXIT=$?
    set -e

    sleep 0.05
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

assert_exit() {
    local expected="$1"
    if [ "$UPDATER_EXIT" -ne "$expected" ]; then
        echo "    assert_exit FAILED: expected $expected, got $UPDATER_EXIT"
        printf '%s\n' "$UPDATER_OUTPUT" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

assert_notify_exit() {
    local expected="$1"
    if [ "$NOTIFY_EXIT" -ne "$expected" ]; then
        echo "    assert_notify_exit FAILED: expected $expected, got $NOTIFY_EXIT"
        printf '%s\n' "$NOTIFY_OUTPUT" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

assert_profile_exit() {
    local expected="$1"
    if [ "$PROFILE_EXIT" -ne "$expected" ]; then
        echo "    assert_profile_exit FAILED: expected $expected, got $PROFILE_EXIT"
        printf '%s\n' "$PROFILE_OUTPUT" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

assert_mock_called() {
    local pattern="$1"
    if ! grep -qF -- "$pattern" "$SANDBOX_MOCK_LOG"; then
        echo "    assert_mock_called FAILED: '$pattern' not found"
        sed 's/^/      /' "$SANDBOX_MOCK_LOG" >&2
        return 1
    fi
    return 0
}

assert_mock_not_called() {
    local pattern="$1"
    if grep -qF -- "$pattern" "$SANDBOX_MOCK_LOG"; then
        echo "    assert_mock_not_called FAILED: '$pattern' found"
        grep -nF -- "$pattern" "$SANDBOX_MOCK_LOG" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

assert_mock_line() {
    local pattern="$1"
    if ! grep -qxF -- "$pattern" "$SANDBOX_MOCK_LOG"; then
        echo "    assert_mock_line FAILED: no line exactly '$pattern'"
        sed 's/^/      /' "$SANDBOX_MOCK_LOG" >&2
        return 1
    fi
    return 0
}

assert_mock_no_line() {
    local pattern="$1"
    if grep -qxF -- "$pattern" "$SANDBOX_MOCK_LOG"; then
        echo "    assert_mock_no_line FAILED: found line '$pattern'"
        return 1
    fi
    return 0
}

assert_file_exists() {
    if [ ! -e "$1" ]; then
        echo "    assert_file_exists FAILED: $1 missing"
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    if [ -e "$1" ]; then
        echo "    assert_file_not_exists FAILED: $1 exists"
        return 1
    fi
    return 0
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    if [ ! -r "$file" ]; then
        echo "    assert_file_contains FAILED: $file not readable"
        return 1
    fi
    if ! grep -qF -- "$pattern" "$file"; then
        echo "    assert_file_contains FAILED: '$pattern' not in $file"
        sed 's/^/      /' "$file" >&2
        return 1
    fi
    return 0
}

assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    if [ -r "$file" ] && grep -qF -- "$pattern" "$file"; then
        echo "    assert_file_not_contains FAILED: '$pattern' in $file"
        return 1
    fi
    return 0
}

assert_output_contains() {
    local pattern="$1"
    if ! printf '%s\n' "$UPDATER_OUTPUT" | grep -qF -- "$pattern"; then
        echo "    assert_output_contains FAILED: '$pattern' not found"
        printf '%s\n' "$UPDATER_OUTPUT" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

assert_notify_output_contains() {
    local pattern="$1"
    if ! printf '%s\n' "$NOTIFY_OUTPUT" | grep -qF -- "$pattern"; then
        echo "    assert_notify_output_contains FAILED: '$pattern' not found"
        printf '%s\n' "$NOTIFY_OUTPUT" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

assert_profile_output_contains() {
    local pattern="$1"
    if ! printf '%s\n' "$PROFILE_OUTPUT" | grep -qF -- "$pattern"; then
        echo "    assert_profile_output_contains FAILED: '$pattern' not found"
        printf '%s\n' "$PROFILE_OUTPUT" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

assert_profile_output_empty() {
    if [ -n "$PROFILE_OUTPUT" ]; then
        echo "    assert_profile_output_empty FAILED: output was non-empty"
        printf '%s\n' "$PROFILE_OUTPUT" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}