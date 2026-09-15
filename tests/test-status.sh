#!/usr/bin/env bash
#
# system-update --status must be truly read-only and truthful.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_setup_common() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    : > "$SANDBOX/var/lib/system-update/attention.state"
}

test_status_no_pending_reboot() {
    sandbox_prepare
    _setup_common
    run_updater --status || return 1
    assert_exit 0 || return 1
    assert_output_contains "Pending reboot: none" || return 1
}

test_status_reports_active_timer() {
    sandbox_prepare
    _setup_common
    cat > "$SANDBOX/var/lib/system-update/kernel-reboot-needed" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-99-99
CREATED_AT=2026-01-01T00:00:00+0000
EOF
    export MOCK_SYSTEMCTL_ACTIVE_UNITS="kernel-reboot-99-99.timer"

    run_updater --status || return 1
    assert_exit 0 || return 1
    assert_output_contains "scheduled (timer active)" || return 1
}

test_status_reports_inactive_timer() {
    sandbox_prepare
    _setup_common
    cat > "$SANDBOX/var/lib/system-update/kernel-reboot-needed" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-99-99
CREATED_AT=2026-01-01T00:00:00+0000
EOF
    export MOCK_SYSTEMCTL_ACTIVE_UNITS=""

    run_updater --status || return 1
    assert_exit 0 || return 1
    assert_output_contains "timer not active" || return 1
}

test_status_never_performs_maintenance() {
    sandbox_prepare
    _setup_common
    cat > "$SANDBOX/var/lib/system-update/kernel-reboot-needed" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-99-99
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    run_updater --status || return 1
    assert_exit 0 || return 1
    assert_mock_not_called "pacman -Syu" || return 1
    assert_mock_not_called "systemd-run" || return 1
    assert_mock_not_called "crontab -" || return 1
    assert_file_exists "$SANDBOX/var/lib/system-update/kernel-reboot-needed" || return 1
}

t test_status_no_pending_reboot
t test_status_reports_active_timer
t test_status_reports_inactive_timer
t test_status_never_performs_maintenance

summary