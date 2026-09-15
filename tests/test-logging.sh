#!/usr/bin/env bash
#
# Logging failure handling.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_setup_common() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    setup_pacman_q "linux618 6.18.50-1"
    write_config "AUTOMATIC_REBOOT=false"
}

test_log_file_written_when_home_is_writable() {
    sandbox_prepare
    _setup_common

    run_updater || return 1
    assert_exit 0 || return 1

    count="$(find "$SANDBOX_HOME/logs" -maxdepth 1 -name 'system-update_*.log' -type f 2>/dev/null | wc -l)"
    count="${count//[[:space:]]/}"
    if [ "$count" -lt 1 ]; then
        echo "    expected at least one log file, found $count"
        ls -la "$SANDBOX_HOME/logs" || true
        return 1
    fi
    return 0
}

test_unwritable_log_dir_does_not_kill_updater() {
    sandbox_prepare
    _setup_common
    # Make $HOME/logs a regular file so mkdir -p fails.
    rm -rf "$SANDBOX_HOME/logs"
    : > "$SANDBOX_HOME/logs"

    run_updater || return 1
    assert_exit 0 || return 1
    # The updater must have reached the end of the update pipeline.
    assert_file_exists "$SANDBOX/var/lib/system-update/attention.state" || return 1
    assert_output_contains "Cannot create log directory" || return 1
}

t test_log_file_written_when_home_is_writable
t test_unwritable_log_dir_does_not_kill_updater

summary