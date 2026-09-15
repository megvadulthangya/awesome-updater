#!/usr/bin/env bash
#
# Configuration hierarchy, validation, and error handling.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_common_setup() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    setup_pacman_q "linux618 6.18.50-1"
}

test_user_config_overrides_system_config() {
    sandbox_prepare
    _common_setup
    write_config "OFFICIAL_UPDATES_ENABLED=false"
    write_user_config "OFFICIAL_UPDATES_ENABLED=true"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_called "pacman -Syu --noconfirm" || return 1
}

test_system_config_disables_official() {
    sandbox_prepare
    _common_setup
    write_config "OFFICIAL_UPDATES_ENABLED=false"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_not_called "pacman -Syu" || return 1
}

test_invalid_boolean_aborts_before_pacman() {
    sandbox_prepare
    _common_setup
    write_config "AUR_ENABLED=maybe"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_output_contains "must be 'true' or 'false'" || return 1
    assert_mock_not_called "pacman -Syu" || return 1
    assert_mock_not_called "yay" || return 1
    assert_mock_not_called "systemd-run" || return 1
}

test_invalid_reboot_time_aborts() {
    sandbox_prepare
    _common_setup
    write_config "REBOOT_TIME=25:99:99"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_output_contains "REBOOT_TIME" || return 1
    assert_mock_not_called "pacman -Syu" || return 1
}

test_invalid_cron_schedule_aborts() {
    sandbox_prepare
    _common_setup
    write_config "CRONTAB_SCHEDULE=nonsense here"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_output_contains "CRONTAB_SCHEDULE" || return 1
    assert_mock_not_called "pacman -Syu" || return 1
}

test_invalid_cron_field_range_aborts() {
    sandbox_prepare
    _common_setup
    write_config "CRONTAB_SCHEDULE=99 99 99 99 99"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_output_contains "CRONTAB_SCHEDULE" || return 1
    assert_mock_not_called "pacman -Syu" || return 1
}

test_invalid_log_retention_aborts() {
    sandbox_prepare
    _common_setup
    write_config "LOG_RETENTION_DAYS=0"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_output_contains "LOG_RETENTION_DAYS" || return 1
    assert_mock_not_called "pacman -Syu" || return 1
}

test_unknown_keys_are_ignored() {
    sandbox_prepare
    _common_setup
    write_config "UNKNOWN_KEY=whatever"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_output_contains "Ignoring unknown configuration key" || return 1
}

test_quoted_values_are_accepted() {
    sandbox_prepare
    _common_setup
    write_config 'OFFICIAL_UPDATES_ENABLED="true"'

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_called "pacman -Syu --noconfirm" || return 1
}

test_config_error_never_prompts_for_sudo() {
    sandbox_prepare
    _common_setup
    write_config "AUR_ENABLED=maybe"
    export MOCK_SUDO_N_OK=1

    run_updater || return 1
    assert_exit 1 || return 1
    # A config error must not need interactive sudo. The mock sudo does
    # not fail on non-passwordless calls, but the script must not call
    # sudo install before checking passwordless availability.
    assert_mock_called "sudo -n true" || return 1
}

t test_user_config_overrides_system_config
t test_system_config_disables_official
t test_invalid_boolean_aborts_before_pacman
t test_invalid_reboot_time_aborts
t test_invalid_cron_schedule_aborts
t test_invalid_cron_field_range_aborts
t test_invalid_log_retention_aborts
t test_unknown_keys_are_ignored
t test_quoted_values_are_accepted
t test_config_error_never_prompts_for_sudo

summary