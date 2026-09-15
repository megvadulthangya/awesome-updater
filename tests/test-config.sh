#!/usr/bin/env bash
#
# Configuration hierarchy and validation.

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

# Legacy keys are no longer recognized. They must be ignored, not fatal,
# and must not cause any crontab WRITE. A read-only `crontab -l` probe is
# permitted by the design and is therefore not asserted against.
test_removed_crontab_keys_are_ignored() {
    sandbox_prepare
    _common_setup
    write_config $'INSTALL_CRONTAB=true\nCRONTAB_SCHEDULE=0 */6 * * *\nAUTOMATIC_REBOOT=false'

    run_updater || return 1
    assert_exit 0 || return 1
    assert_output_contains "Ignoring unknown configuration key 'INSTALL_CRONTAB'" || return 1
    assert_output_contains "Ignoring unknown configuration key 'CRONTAB_SCHEDULE'" || return 1
    # The write form is exactly the line "crontab -" (stdin replaced by
    # the runtime). Read-only probes such as "crontab -l" are allowed.
    assert_mock_no_line "crontab -" || return 1
}

test_config_error_never_prompts_for_sudo() {
    sandbox_prepare
    _common_setup
    write_config "AUR_ENABLED=maybe"

    run_updater || return 1
    assert_exit 1 || return 1

    if grep -E '^sudo ' "$SANDBOX_MOCK_LOG" | grep -v '^sudo -n ' >/dev/null; then
        echo "    found a sudo call without the -n flag in the config error path"
        grep -E '^sudo ' "$SANDBOX_MOCK_LOG" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

t test_user_config_overrides_system_config
t test_system_config_disables_official
t test_invalid_boolean_aborts_before_pacman
t test_invalid_reboot_time_aborts
t test_invalid_log_retention_aborts
t test_unknown_keys_are_ignored
t test_quoted_values_are_accepted
t test_removed_crontab_keys_are_ignored
t test_config_error_never_prompts_for_sudo

summary