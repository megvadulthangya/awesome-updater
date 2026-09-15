#!/usr/bin/env bash
#
# Legacy manual installation warning.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_setup_common() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    setup_pacman_q "linux618 6.18.50-1"
    write_config "AUTOMATIC_REBOOT=false"
}

test_legacy_files_trigger_warning_and_are_not_removed() {
    sandbox_prepare
    _setup_common

    cat > "$SANDBOX/usr/local/bin/system-update" <<'EOF'
#!/bin/sh
# legacy
EOF
    cat > "$SANDBOX/usr/local/bin/system-update-notify" <<'EOF'
#!/bin/sh
# legacy
EOF
    chmod +x "$SANDBOX/usr/local/bin/system-update" \
             "$SANDBOX/usr/local/bin/system-update-notify"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_output_contains "Legacy manual installation detected" || return 1
    assert_file_exists "$SANDBOX/usr/local/bin/system-update" || return 1
    assert_file_exists "$SANDBOX/usr/local/bin/system-update-notify" || return 1
}

test_legacy_crontab_reference_warned() {
    sandbox_prepare
    _setup_common
    cat > "$SANDBOX/crontab.txt" <<EOF
0 3 * * * $SANDBOX/usr/local/bin/system-update >/dev/null 2>&1
EOF

    run_updater || return 1
    assert_exit 0 || return 1
    assert_output_contains "legacy path" || return 1
}

t test_legacy_files_trigger_warning_and_are_not_removed
t test_legacy_crontab_reference_warned

summary