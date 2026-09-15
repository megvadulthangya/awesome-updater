#!/usr/bin/env bash
#
# Config error handling on a fresh install (no pre-existing state dir).

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

test_invalid_config_creates_attention_state_on_fresh_install() {
    sandbox_prepare
    # Simulate a fresh install: remove the state directory that the
    # harness created.
    rm -rf "$SANDBOX/var/lib/system-update"
    write_config "AUR_ENABLED=maybe"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_file_exists "$SANDBOX/var/lib/system-update/attention.state" || return 1
    assert_file_contains \
        "$SANDBOX/var/lib/system-update/attention.state" \
        "NEEDS_ATTENTION=1" || return 1
    assert_file_contains \
        "$SANDBOX/var/lib/system-update/attention.state" \
        "UPDATE_FAILED=1" || return 1
    assert_file_contains \
        "$SANDBOX/var/lib/system-update/attention.state" \
        "Invalid configuration" || return 1
}

test_invalid_config_never_runs_pacman() {
    sandbox_prepare
    rm -rf "$SANDBOX/var/lib/system-update"
    write_config "REBOOT_TIME=99:99:99"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_mock_not_called "pacman -Syu" || return 1
    assert_mock_not_called "systemd-run" || return 1
    assert_mock_not_called "crontab -" || return 1
}

test_invalid_config_preserves_pending_reboot() {
    sandbox_prepare
    rm -rf "$SANDBOX/var/lib/system-update"
    mkdir -p "$SANDBOX/var/lib/system-update"
    cat > "$SANDBOX/var/lib/system-update/kernel-reboot-needed" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-1-1
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    write_config "AUR_ENABLED=maybe"
    run_updater || return 1
    assert_exit 1 || return 1
    assert_file_contains \
        "$SANDBOX/var/lib/system-update/attention.state" \
        "REBOOT_REQUIRED=1" || return 1
    assert_file_exists \
        "$SANDBOX/var/lib/system-update/kernel-reboot-needed" || return 1
}

t test_invalid_config_creates_attention_state_on_fresh_install
t test_invalid_config_never_runs_pacman
t test_invalid_config_preserves_pending_reboot

summary