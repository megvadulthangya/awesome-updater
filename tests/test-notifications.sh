#!/usr/bin/env bash
#
# Wall broadcasts, notify-send helper, and the login profile hook.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_setup_common() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    setup_pacman_q "linux618 6.18.50-1"
}

_attention_with_pacnew() {
    write_config $'AUTOMATIC_REBOOT=false\nNOTIFY_WALL=true'
    : > "$SANDBOX/etc/foo.conf.pacnew"
}

test_wall_fires_on_state_change() {
    sandbox_prepare
    _setup_common
    _attention_with_pacnew

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_called "wall" || return 1
}

test_wall_suppressed_when_disabled() {
    sandbox_prepare
    _setup_common
    write_config $'AUTOMATIC_REBOOT=false\nNOTIFY_WALL=false'
    : > "$SANDBOX/etc/foo.conf.pacnew"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_not_called "wall" || return 1
}

test_wall_not_repeated_on_identical_state() {
    sandbox_prepare
    _setup_common
    _attention_with_pacnew

    run_updater || return 1
    run_updater || return 1
    assert_exit 0 || return 1

    count="$(grep -c '^wall' "$SANDBOX_MOCK_LOG" || true)"
    if [ "$count" -ne 1 ]; then
        echo "    expected wall exactly once, got $count"
        grep -n '^wall' "$SANDBOX_MOCK_LOG" || true
        return 1
    fi
    return 0
}

test_notify_tty_prints_when_attention() {
    sandbox_prepare
    _setup_common
    cat > "$SANDBOX/var/lib/system-update/attention.state" <<'EOF'
NEEDS_ATTENTION=1
UPDATE_FAILED=0
REBOOT_REQUIRED=0
REBOOT_SCHEDULE_FAILED=0
PACNEW_COUNT=1
REASON=.pacnew files require review
ACTION=Review .pacnew
DETAIL=1 file
EOF

    run_notify --tty || return 1
    assert_notify_exit 0 || return 1
    assert_notify_output_contains "ATTENTION REQUIRED" || return 1
    assert_notify_output_contains ".pacnew files require review" || return 1
}

test_notify_tty_silent_when_no_attention() {
    sandbox_prepare
    _setup_common
    cat > "$SANDBOX/var/lib/system-update/attention.state" <<'EOF'
NEEDS_ATTENTION=0
UPDATE_FAILED=0
REBOOT_REQUIRED=0
REBOOT_SCHEDULE_FAILED=0
PACNEW_COUNT=0
REASON=
ACTION=
DETAIL=
EOF

    run_notify --tty || return 1
    assert_notify_exit 0 || return 1
    if printf '%s\n' "$NOTIFY_OUTPUT" | grep -qF "ATTENTION"; then
        echo "    notify-send output should be empty"
        return 1
    fi
    return 0
}

test_notify_gui_uses_notify_send() {
    sandbox_prepare
    _setup_common
    cat > "$SANDBOX/var/lib/system-update/attention.state" <<'EOF'
NEEDS_ATTENTION=1
UPDATE_FAILED=1
REBOOT_REQUIRED=0
REBOOT_SCHEDULE_FAILED=0
PACNEW_COUNT=0
REASON=Official system update failed
ACTION=Review the log
DETAIL=pacman -Syu returned non-zero
EOF

    run_notify --gui || return 1
    assert_notify_exit 0 || return 1
    assert_mock_called "notify-send" || return 1
}

test_notify_gui_silent_when_no_attention() {
    sandbox_prepare
    _setup_common
    cat > "$SANDBOX/var/lib/system-update/attention.state" <<'EOF'
NEEDS_ATTENTION=0
UPDATE_FAILED=0
REBOOT_REQUIRED=0
REBOOT_SCHEDULE_FAILED=0
PACNEW_COUNT=0
REASON=
ACTION=
DETAIL=
EOF

    run_notify --gui || return 1
    assert_notify_exit 0 || return 1
    assert_mock_not_called "notify-send" || return 1
}

test_profile_hook_prints_when_enabled() {
    sandbox_prepare
    write_config "NOTIFY_PROFILE_D=true"
    cat > "$SANDBOX/var/lib/system-update/attention.state" <<'EOF'
NEEDS_ATTENTION=1
UPDATE_FAILED=1
REBOOT_REQUIRED=0
REBOOT_SCHEDULE_FAILED=0
PACNEW_COUNT=0
REASON=Official system update failed
ACTION=Review the log
DETAIL=pacman -Syu returned non-zero
EOF

    run_profile_hook || return 1
    assert_profile_output_contains "ATTENTION REQUIRED" || return 1
}

test_profile_hook_silent_when_disabled() {
    sandbox_prepare
    write_config "NOTIFY_PROFILE_D=false"
    cat > "$SANDBOX/var/lib/system-update/attention.state" <<'EOF'
NEEDS_ATTENTION=1
UPDATE_FAILED=1
REBOOT_REQUIRED=0
REBOOT_SCHEDULE_FAILED=0
PACNEW_COUNT=0
REASON=Official system update failed
ACTION=Review the log
DETAIL=pacman -Syu returned non-zero
EOF

    run_profile_hook || return 1
    assert_profile_output_empty || return 1
}

t test_wall_fires_on_state_change
t test_wall_suppressed_when_disabled
t test_wall_not_repeated_on_identical_state
t test_notify_tty_prints_when_attention
t test_notify_tty_silent_when_no_attention
t test_notify_gui_uses_notify_send
t test_notify_gui_silent_when_no_attention
t test_profile_hook_prints_when_enabled
t test_profile_hook_silent_when_disabled

summary