#!/usr/bin/env bash
#
# Refuses to run as root.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

test_root_execution_is_refused() {
    sandbox_prepare

    export MOCK_ID_U=0
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    setup_pacman_q "linux618 6.18.50-1"
    write_config "OFFICIAL_UPDATES_ENABLED=true"

    run_updater || return 1

    assert_exit 1 || return 1
    assert_output_contains "must be run as a normal user" || return 1
    assert_mock_not_called "pacman -Syu" || return 1
    assert_mock_not_called "systemd-run" || return 1
    assert_mock_not_called "crontab -" || return 1
    assert_mock_not_called "sudo install" || return 1
}

t test_root_execution_is_refused

summary