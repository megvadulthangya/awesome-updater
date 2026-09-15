#!/usr/bin/env bash
#
# Kernel detection and persistent reboot state machine.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

REBOOT_FLAG=""

_setup_common() {
    REBOOT_FLAG="$SANDBOX/var/lib/system-update/kernel-reboot-needed"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    write_config $'AUTOMATIC_REBOOT=false\nOFFICIAL_UPDATES_ENABLED=true'
}

test_no_kernel_detected_aborts_with_attention() {
    sandbox_prepare
    _setup_common
    export MOCK_MHWD_OUTPUT=""
    export MOCK_PACMAN_QO=""
    # No fallback module path means detection fails.
    export MOCK_PACMAN_Q_FILE_1="$SANDBOX/no-kernels.list"
    : > "$MOCK_PACMAN_Q_FILE_1"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_file_exists "$SANDBOX/var/lib/system-update/attention.state" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "UPDATE_FAILED=1" || return 1
}

test_kernel_update_creates_reboot_flag() {
    sandbox_prepare
    _setup_common
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    setup_pacman_before_after "linux618 6.18.50-1" "linux618 6.18.51-1"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_file_exists "$REBOOT_FLAG" || return 1
    assert_file_contains "$REBOOT_FLAG" "KERNEL_PACKAGE=linux618" || return 1
    assert_file_contains "$REBOOT_FLAG" "TARGET_VERSION=6.18.51-1" || return 1
    assert_file_contains "$REBOOT_FLAG" "RUNNING_VERSION=6.18.50-1-MANJARO" || return 1
}

test_repeated_kernel_update_preserves_running_and_created() {
    sandbox_prepare
    _setup_common
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"

    cat > "$REBOOT_FLAG" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-original-42
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    # Second kernel update: same package, newer target.
    setup_pacman_before_after "linux618 6.18.51-1" "linux618 6.18.52-1"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_file_contains "$REBOOT_FLAG" "KERNEL_PACKAGE=linux618" || return 1
    assert_file_contains "$REBOOT_FLAG" "TARGET_VERSION=6.18.52-1" || return 1
    assert_file_contains "$REBOOT_FLAG" "RUNNING_VERSION=6.18.50-1-MANJARO" || return 1
    assert_file_contains "$REBOOT_FLAG" "CREATED_AT=2026-01-01T00:00:00+0000" || return 1
    assert_file_contains "$REBOOT_FLAG" "REBOOT_UNIT=kernel-reboot-original-42" || return 1
}

test_different_booted_kernel_keeps_pending_state() {
    sandbox_prepare
    _setup_common
    export MOCK_MHWD_OUTPUT="Currently running: 6.12.10-1-MANJARO (linux612)"
    export MOCK_UNAME_R="6.12.10-1-MANJARO"
    setup_pacman_q "linux612 6.12.10-1
linux618 6.18.51-1"

    cat > "$REBOOT_FLAG" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-1-1
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    run_updater || return 1
    assert_exit 0 || return 1
    assert_file_exists "$REBOOT_FLAG" || return 1
    assert_file_contains "$REBOOT_FLAG" "KERNEL_PACKAGE=linux618" || return 1
    assert_file_contains "$REBOOT_FLAG" "TARGET_VERSION=6.18.51-1" || return 1
}

test_vercmp_failure_keeps_pending_state() {
    sandbox_prepare
    _setup_common
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    setup_pacman_q "linux618 6.18.51-1"
    export MOCK_VERCMP_EXIT=1

    cat > "$REBOOT_FLAG" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-1-1
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    run_updater || return 1
    assert_exit 0 || return 1
    assert_file_exists "$REBOOT_FLAG" || return 1
    assert_file_contains "$REBOOT_FLAG" "KERNEL_PACKAGE=linux618" || return 1
}

test_actual_target_running_clears_state() {
    sandbox_prepare
    _setup_common
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.51-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.51-1-MANJARO"
    setup_pacman_q "linux618 6.18.51-1"

    cat > "$REBOOT_FLAG" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-1-1
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    run_updater || return 1
    assert_exit 0 || return 1
    assert_file_not_exists "$REBOOT_FLAG" || return 1
}

t test_no_kernel_detected_aborts_with_attention
t test_kernel_update_creates_reboot_flag
t test_repeated_kernel_update_preserves_running_and_created
t test_different_booted_kernel_keeps_pending_state
t test_vercmp_failure_keeps_pending_state
t test_actual_target_running_clears_state

summary