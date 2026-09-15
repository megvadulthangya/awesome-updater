#!/usr/bin/env bash
#
# AUR branch behavior.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

_common_setup() {
    export MOCK_MHWD_OUTPUT="Currently running: 6.18.50-1-MANJARO (linux618)"
    export MOCK_UNAME_R="6.18.50-1-MANJARO"
    setup_pacman_q "linux618 6.18.50-1"
}

test_aur_disabled_never_uses_yay() {
    sandbox_prepare
    _common_setup
    write_config $'AUR_ENABLED=false\nAUTOMATIC_REBOOT=false'

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_not_called "yay" || return 1
    assert_mock_not_called "git clone" || return 1
    assert_mock_not_called "makepkg" || return 1
    assert_mock_not_called "base-devel" || return 1
}

test_aur_default_is_disabled() {
    sandbox_prepare
    _common_setup
    write_config "AUTOMATIC_REBOOT=false"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_output_contains "AUR_ENABLED=false" || return 1
    assert_mock_not_called "yay" || return 1
}

test_aur_enabled_runs_yay_sua() {
    sandbox_prepare
    _common_setup
    write_config $'AUR_ENABLED=true\nAUTOMATIC_REBOOT=false'

    # Pretend yay is already installed.
    cat > "$SANDBOX/usr/bin/yay" <<'EOS'
#!/usr/bin/env bash
printf 'yay' >> "$MOCK_LOG"
for a in "$@"; do printf ' %s' "$a" >> "$MOCK_LOG"; done
printf '\n' >> "$MOCK_LOG"
exit "${MOCK_YAY_EXIT:-0}"
EOS
    chmod +x "$SANDBOX/usr/bin/yay"

    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_called "yay -Sua --noconfirm" || return 1
}

test_aur_enabled_bootstraps_yay() {
    sandbox_prepare
    _common_setup
    write_config $'AUR_ENABLED=true\nAUTOMATIC_REBOOT=false'

    # yay is missing: the runtime must build it via git + makepkg.
    run_updater || return 1
    assert_exit 0 || return 1
    assert_mock_called "pacman -S --needed --noconfirm base-devel git" || return 1
    assert_mock_called "git clone https://aur.archlinux.org/yay.git" || return 1
    assert_mock_called "makepkg -si --noconfirm" || return 1
}

test_aur_failure_preserves_reboot_required() {
    sandbox_prepare
    _common_setup
    write_config $'AUR_ENABLED=true\nAUTOMATIC_REBOOT=false'

    # Pre-existing persistent reboot state.
    cat > "$SANDBOX/var/lib/system-update/kernel-reboot-needed" <<'EOF'
KERNEL_PACKAGE=linux618
TARGET_VERSION=6.18.51-1
RUNNING_VERSION=6.18.50-1-MANJARO
REBOOT_UNIT=kernel-reboot-1-1
CREATED_AT=2026-01-01T00:00:00+0000
EOF

    # Pretend yay is present but returns failure.
    cat > "$SANDBOX/usr/bin/yay" <<'EOS'
#!/usr/bin/env bash
printf 'yay' >> "$MOCK_LOG"
for a in "$@"; do printf ' %s' "$a" >> "$MOCK_LOG"; done
printf '\n' >> "$MOCK_LOG"
exit 9
EOS
    chmod +x "$SANDBOX/usr/bin/yay"

    run_updater || return 1
    assert_exit 1 || return 1
    assert_file_contains "$SANDBOX/var/lib/system-update/attention.state" "REBOOT_REQUIRED=1" || return 1
    assert_file_exists "$SANDBOX/var/lib/system-update/kernel-reboot-needed" || return 1
}

t test_aur_disabled_never_uses_yay
t test_aur_default_is_disabled
t test_aur_enabled_runs_yay_sua
t test_aur_enabled_bootstraps_yay
t test_aur_failure_preserves_reboot_required

summary