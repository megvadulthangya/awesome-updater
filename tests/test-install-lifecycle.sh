#!/usr/bin/env bash
#
# Package install lifecycle: user discovery and scheduler activation.
#
# Sources awesome-updater.install in a subshell with mocked systemctl and
# a mock passwd file, then calls its functions directly. Never touches
# the real systemd, the real passwd database, or the real crontab.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

INSTALL_FILE="$PROJECT_DIR/awesome-updater.install"

_setup_install_sandbox() {
    sandbox_prepare
    export PATH="$SANDBOX_PATH"
    unset SUDO_USER PKEXEC_UID DOAS_USER
}

_call_discover() {
    (
        # shellcheck disable=SC1090
        source "$INSTALL_FILE"
        _discover_user
    ) 2>/dev/null
}

_run_install_fn() {
    local fn="$1"
    (
        # shellcheck disable=SC1090
        source "$INSTALL_FILE"
        "$fn"
    ) > "$SANDBOX/install-out.$$" 2>&1
    INSTALL_STATUS=$?
    INSTALL_OUTPUT="$(cat "$SANDBOX/install-out.$$")"
    rm -f "$SANDBOX/install-out.$$"
    return "$INSTALL_STATUS"
}

test_install_file_exists() {
    if [ ! -f "$INSTALL_FILE" ]; then
        echo "    $INSTALL_FILE missing"
        return 1
    fi
    return 0
}

test_install_file_is_syntactically_valid() {
    bash -n "$INSTALL_FILE" || {
        echo "    syntax error in $INSTALL_FILE"
        return 1
    }
    return 0
}

test_discover_sudo_user() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    export SUDO_USER=testuser

    user="$(_call_discover)"
    if [ "$user" != "testuser" ]; then
        echo "    got '$user', expected 'testuser'"
        return 1
    fi
    return 0
}

test_discover_via_pkexec_uid() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    export PKEXEC_UID=1001

    user="$(_call_discover)"
    if [ "$user" != "testuser" ]; then
        echo "    got '$user', expected 'testuser'"
        return 1
    fi
    return 0
}

test_discover_via_doas_user() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    export DOAS_USER=testuser

    user="$(_call_discover)"
    if [ "$user" != "testuser" ]; then
        echo "    got '$user', expected 'testuser'"
        return 1
    fi
    return 0
}

test_discover_rejects_root() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    export SUDO_USER=root

    if user="$(_call_discover)"; then
        echo "    expected failure, got '$user'"
        return 1
    fi
    return 0
}

test_discover_rejects_missing_identity() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    # No SUDO_USER, PKEXEC_UID, or DOAS_USER.

    if user="$(_call_discover)"; then
        echo "    expected failure, got '$user'"
        return 1
    fi
    return 0
}

test_discover_rejects_nonexistent_user() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    export SUDO_USER="__nonexistent_user_12345__"

    if user="$(_call_discover)"; then
        echo "    expected failure, got '$user'"
        return 1
    fi
    return 0
}

test_discover_rejects_invalid_home() {
    _setup_install_sandbox
    # Create passwd entry whose home directory does not exist.
    pf="$SANDBOX/passwd"
    printf 'testuser:x:1001:1001::%s/nonexistent:/bin/bash\n' "$SANDBOX" > "$pf"
    printf 'root:x:0:0::/root:/bin/bash\n' >> "$pf"
    export MOCK_PASSWD_FILE="$pf"
    export SUDO_USER=testuser

    if user="$(_call_discover)"; then
        echo "    expected failure, got '$user'"
        return 1
    fi
    return 0
}

test_post_install_enables_timer_for_user() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    export SUDO_USER=testuser

    _run_install_fn post_install

    assert_mock_called "systemctl enable --now awesome-updater@testuser.timer" || return 1
    return 0
}

test_post_install_never_enables_root_timer() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    # No user env vars: must print manual instructions, not enable root.

    _run_install_fn post_install

    if grep -qF "systemctl enable --now awesome-updater@root.timer" "$SANDBOX_MOCK_LOG"; then
        echo "    root timer was enabled"
        return 1
    fi
    if grep -qF "systemctl enable" "$SANDBOX_MOCK_LOG"; then
        echo "    unexpected systemctl enable call:"
        grep "systemctl enable" "$SANDBOX_MOCK_LOG" | sed 's/^/      /'
        return 1
    fi
    if ! printf '%s\n' "$INSTALL_OUTPUT" | grep -qF "systemctl enable --now awesome-updater@"; then
        echo "    manual activation instruction not printed"
        printf '%s\n' "$INSTALL_OUTPUT" | sed 's/^/      /'
        return 1
    fi
    return 0
}

test_post_upgrade_preserves_existing_instance() {
    _setup_install_sandbox
    write_mock_passwd testuser "$SANDBOX/home/testuser"
    export SUDO_USER=testuser
    export MOCK_SYSTEMCTL_ENABLED_TIMERS="awesome-updater@alice.timer"

    _run_install_fn post_upgrade

    if grep -qF "systemctl enable --now awesome-updater@testuser.timer" "$SANDBOX_MOCK_LOG"; then
        echo "    post_upgrade enabled a new timer despite an existing one"
        return 1
    fi
    return 0
}

test_pre_remove_disables_timers() {
    _setup_install_sandbox
    export MOCK_SYSTEMCTL_ENABLED_TIMERS="awesome-updater@alice.timer"

    _run_install_fn pre_remove

    assert_mock_called "systemctl disable --now awesome-updater@alice.timer" || return 1
    return 0
}

test_pre_remove_preserves_user_state_in_message() {
    _setup_install_sandbox

    _run_install_fn pre_remove

    if ! printf '%s\n' "$INSTALL_OUTPUT" | grep -qF "/var/lib/system-update"; then
        echo "    pre_remove message does not mention preserved state"
        printf '%s\n' "$INSTALL_OUTPUT" | sed 's/^/      /'
        return 1
    fi
    return 0
}

t test_install_file_exists
t test_install_file_is_syntactically_valid
t test_discover_sudo_user
t test_discover_via_pkexec_uid
t test_discover_via_doas_user
t test_discover_rejects_root
t test_discover_rejects_missing_identity
t test_discover_rejects_nonexistent_user
t test_discover_rejects_invalid_home
t test_post_install_enables_timer_for_user
t test_post_install_never_enables_root_timer
t test_post_upgrade_preserves_existing_instance
t test_pre_remove_disables_timers
t test_pre_remove_preserves_user_state_in_message

summary