#!/usr/bin/env bash
#
# Crontab management.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_setup_common() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    setup_pacman_q "linux618 6.18.50-1"
}

test_crontab_disabled_does_not_modify() {
    sandbox_prepare
    _setup_common
    write_config $'INSTALL_CRONTAB=false\nAUTOMATIC_REBOOT=false'

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_no_line "crontab -" || return 1
}

test_crontab_installed_uses_bin_path() {
    sandbox_prepare
    _setup_common
    write_config $'INSTALL_CRONTAB=true\nCRONTAB_SCHEDULE=0 */6 * * *\nAUTOMATIC_REBOOT=false'

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_line "crontab -" || return 1
    assert_file_contains "$SANDBOX/crontab.txt" "$SANDBOX/usr/bin/system-update" || return 1
}

test_crontab_preserves_unrelated_jobs() {
    sandbox_prepare
    _setup_common
    write_config $'INSTALL_CRONTAB=true\nCRONTAB_SCHEDULE=0 */6 * * *\nAUTOMATIC_REBOOT=false'

    cat > "$SANDBOX/crontab.txt" <<'EOF'
15 3 * * * /usr/bin/unrelated-job --daily
30 4 * * * /usr/bin/system-update-notify --gui
EOF

    run_updater || return 1
    assert_exit 0 || return 1
    assert_file_contains "$SANDBOX/crontab.txt" "/usr/bin/unrelated-job --daily" || return 1
    assert_file_contains "$SANDBOX/crontab.txt" "/usr/bin/system-update-notify --gui" || return 1
    assert_file_contains "$SANDBOX/crontab.txt" "$SANDBOX/usr/bin/system-update" || return 1
}

test_crontab_preserves_notify_helper_entries() {
    sandbox_prepare
    _setup_common
    write_config $'INSTALL_CRONTAB=true\nCRONTAB_SCHEDULE=0 */6 * * *\nAUTOMATIC_REBOOT=false'

    cat > "$SANDBOX/crontab.txt" <<EOF
0 12 * * 0 $SANDBOX/usr/bin/system-update-notify --gui
EOF

    run_updater || return 1
    assert_exit 0 || return 1
    assert_file_contains "$SANDBOX/crontab.txt" "system-update-notify --gui" || return 1
}

test_crontab_failure_marks_attention() {
    sandbox_prepare
    _setup_common
    write_config $'INSTALL_CRONTAB=true\nCRONTAB_SCHEDULE=0 */6 * * *\nAUTOMATIC_REBOOT=false'
    export MOCK_CRONTAB_INSTALL_EXIT=1

    run_updater || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "UPDATE_FAILED=1" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "NEEDS_ATTENTION=1" || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "cron" || return 1
}

t test_crontab_disabled_does_not_modify
t test_crontab_installed_uses_bin_path
t test_crontab_preserves_unrelated_jobs
t test_crontab_preserves_notify_helper_entries
t test_crontab_failure_marks_attention

summary