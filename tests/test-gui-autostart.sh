#!/usr/bin/env bash
#
# GUI autostart entry handling.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_setup_common() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    setup_pacman_q "linux618 6.18.50-1"
}

test_gui_autostart_created_with_expected_exec() {
    sandbox_prepare
    _setup_common
    write_config $'NOTIFY_GUI=true\nAUTOMATIC_REBOOT=false'

    run_updater || return 1
    assert_exit 0 || return 1
    file="$SANDBOX_HOME/.config/autostart/system-update-notify.desktop"
    assert_file_exists "$file" || return 1
    assert_file_contains "$file" "Exec=$SANDBOX/usr/bin/system-update-notify --gui-watch" || return 1

    # The autostart file must be created in user space. The runtime may
    # legitimately use `sudo install` to write /var/lib/system-update/*,
    # so the assertion must be scoped to the autostart file itself.
    if grep -E '^sudo .*system-update-notify\.desktop' "$SANDBOX_MOCK_LOG" >/dev/null; then
        echo "    autostart file was created via sudo"
        grep -nE '^sudo .*system-update-notify\.desktop' "$SANDBOX_MOCK_LOG" | sed 's/^/      /' >&2
        return 1
    fi
    return 0
}

test_gui_autostart_removed_when_disabled() {
    sandbox_prepare
    _setup_common
    write_config $'NOTIFY_GUI=true\nAUTOMATIC_REBOOT=false'
    run_updater || return 1

    file="$SANDBOX_HOME/.config/autostart/system-update-notify.desktop"
    assert_file_exists "$file" || return 1

    write_config $'NOTIFY_GUI=false\nAUTOMATIC_REBOOT=false'
    run_updater || return 1
    assert_file_not_exists "$file" || return 1
}

t test_gui_autostart_created_with_expected_exec
t test_gui_autostart_removed_when_disabled

summary