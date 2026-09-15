#!/usr/bin/env bash
#
# CLI surface: --help, --version, --status, unknown argument.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

test_help_exits_zero() {
    sandbox_prepare
    run_updater --help || return 1
    assert_exit 0 || return 1
    assert_output_contains "Usage:" || return 1
    assert_mock_not_called "pacman" || return 1
}

test_version_exits_zero() {
    sandbox_prepare
    run_updater --version || return 1
    assert_exit 0 || return 1
    assert_output_contains "system-update" || return 1
    assert_mock_not_called "pacman" || return 1
}

test_unknown_argument_exits_two() {
    sandbox_prepare
    run_updater --bogus || return 1
    assert_exit 2 || return 1
    assert_output_contains "Unknown option" || return 1
    assert_mock_not_called "pacman" || return 1
}

test_status_is_read_only() {
    sandbox_prepare
    run_updater --status || return 1
    assert_exit 0 || return 1
    assert_output_contains "System Update Status" || return 1
    assert_mock_not_called "pacman -Syu" || return 1
    assert_mock_not_called "yay" || return 1
    assert_mock_not_called "systemd-run" || return 1
    assert_mock_not_called "crontab -" || return 1
    assert_mock_not_called "sudo install" || return 1
}

t test_help_exits_zero
t test_version_exits_zero
t test_unknown_argument_exits_two
t test_status_is_read_only

summary