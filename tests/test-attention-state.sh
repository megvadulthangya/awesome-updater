#!/usr/bin/env bash
#
# Consolidated attention state must never erase independent failure
# conditions.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_setup_common() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    write_config $'AUTOMATIC_REBOOT=false'
}

test_pacman_failure_preserves_pending_reboot() {
    sandbox_prepare
    _setup_common
    setup_pacman_q "linux618 6.18.51-1"
    export MOCK_PACMAN_SYU_EXIT=1

    cat > "$SANDBOX/var/lib/system-update/kernel-reboot-needed" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-1-1
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    run_updater || return 1
    assert_exit 1 || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "UPDATE_FAILED=1" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "REBOOT_REQUIRED=1" || return 1
}

test_pacnew_and_reboot_coexist() {
    sandbox_prepare
    _setup_common
    export MOCK_SYSTEMD_RUN_EXIT=1  # make scheduling fail
    write_config $'AUTOMATIC_REBOOT=true\nREBOOT_TIME=02:15:00'
    : > "$SANDBOX/etc/foo.conf.pacnew"

    cat > "$SANDBOX/var/lib/system-update/kernel-reboot-needed" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    # Ensure kernel detection finds linux618.
    setup_pacman_q "linux618 6.18.51-1"
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"

    run_updater || return 1
    assert_file_exists "$SANDBOX/var/lib/system-update/attention.state" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "REBOOT_REQUIRED=1" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "PACNEW_COUNT=1" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "REBOOT_SCHEDULE_FAILED=1" || return 1
}

t test_pacman_failure_preserves_pending_reboot
t test_pacnew_and_reboot_coexist

summary