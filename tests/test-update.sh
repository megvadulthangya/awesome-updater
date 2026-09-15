#!/usr/bin/env bash
#
# Basic update pipeline.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_common_setup() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    setup_pacman_q "linux618 6.18.50-1"
    write_config "AUTOMATIC_REBOOT=false"
}

test_official_update_uses_syu_noconfirm() {
    sandbox_prepare
    _common_setup
    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_called "pacman -Syu --noconfirm" || return 1
    assert_mock_not_called "pacman -Sy " || return 1
    assert_mock_not_called "pacman -Su " || return 1
    assert_mock_not_called "pacman -Sc" || return 1
}

test_pacman_failure_sets_attention_state() {
    sandbox_prepare
    _common_setup
    export MOCK_PACMAN_SYU_EXIT=1

    run_updater || return 1
    assert_exit 1 || return 1
    assert_file_exists "$SANDBOX/var/lib/system-update/attention.state" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "UPDATE_FAILED=1" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "NEEDS_ATTENTION=1" || return 1
}

test_official_updates_disabled_skips_pacman() {
    sandbox_prepare
    _common_setup
    write_config $'OFFICIAL_UPDATES_ENABLED=false\nAUTOMATIC_REBOOT=false'

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_not_called "pacman -Syu" || return 1
}

test_pacnew_files_detected_and_not_deleted() {
    sandbox_prepare
    _common_setup
    : > "$SANDBOX/etc/foo.conf.pacnew"
    : > "$SANDBOX/etc/bar.conf.pacnew"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_output_contains ".pacnew files found: 2" || return 1
    assert_file_exists "$SANDBOX/etc/foo.conf.pacnew" || return 1
    assert_file_exists "$SANDBOX/etc/bar.conf.pacnew" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "PACNEW_COUNT=2" || return 1
}

t test_official_update_uses_syu_noconfirm
t test_pacman_failure_sets_attention_state
t test_official_updates_disabled_skips_pacman
t test_pacnew_files_detected_and_not_deleted

summary