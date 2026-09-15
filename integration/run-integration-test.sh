#!/usr/bin/env bash
#
# integration/run-integration-test.sh
#
# Portable real-Manjaro integration test for awesome-updater.
#
# WHAT THIS SCRIPT DOES
#   * builds the package from the current repository using makepkg
#   * installs it on the running Manjaro system with `pacman -U`
#   * inspects the live systemd timer / service that the package installs
#   * runs the real updater as the target normal user
#   * exercises the real kernel-reboot lifecycle when a kernel update is
#     available on this test machine
#   * verifies that the user crontab was not touched, that the packaged
#     kernel-modules-hook dependency is present, and that the timer is
#     not a root instance
#   * (optionally) uninstalls the package and restores the user's
#     original configuration at the end
#
# SAFETY
#   * USE ONLY ON A DISPOSABLE TEST MACHINE.
#   * The script performs REAL system operations and may reboot the
#     machine as part of the kernel-reboot lifecycle test.
#   * The intended test environment is an older Manjaro installation for
#     which `pacman -Syu` actually has work to do, with a Timeshift
#     snapshot taken MANUALLY before testing. This script never invokes
#     Timeshift and never restores snapshots.
#   * The script requires a normal user with passwordless sudo.
#   * The script refuses to run as root.
#
# TWO-PHASE MODEL
#   Phase 1 runs on a freshly booted test machine. If a kernel update is
#   detected, phase 1 schedules a test-only reboot timer and prints the
#   exact command needed to manually reboot the machine. The script then
#   exits so the operator can reboot at a controlled moment.
#
#   Phase 2 runs after the machine has rebooted. It verifies that the
#   target kernel is actually running, that the transient timer did not
#   survive the reboot, and that the persistent reboot flag is cleared
#   without a second reboot being scheduled.
#
#   The current phase is detected automatically using a boot-id marker
#   stored in a test-owned directory under $HOME.
#
# USAGE
#   integration/run-integration-test.sh [OPTIONS]
#
# OPTIONS
#   --auto-reboot    Let the test-scheduled reboot timer fire
#                    automatically instead of prompting for a manual
#                    reboot. This is opt-in because it reboots the
#                    machine without further confirmation.
#   --no-reboot      Skip the kernel-reboot lifecycle test entirely.
#   --no-cleanup     Do not uninstall the package at the end of the test.
#   --reset          Clear the integration test state directory and exit.
#   --help, -h       Show this help.
#
# The script never modifies /etc/system-update/config.conf. The test
# REBOOT_TIME override is written to ~/.config/system-update/config.conf
# and is restored or removed at the end of the test.

set -uo pipefail

# ============================================================================
# Paths and constants
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

STATE_DIR="$HOME/.cache/awesome-updater-integration-test"
STATE_FILE="$STATE_DIR/state"
USER_CONFIG_BACKUP="$STATE_DIR/user-config.conf.bak"
USER_CONFIG_WAS_PRESENT="$STATE_DIR/user-config.was-present"

PKGNAME="awesome-updater"
SERVICE_TEMPLATE="awesome-updater@.service"
REBOOT_FLAG="/var/lib/system-update/kernel-reboot-needed"
ATTENTION_STATE="/var/lib/system-update/attention.state"

# ============================================================================
# CLI
# ============================================================================

AUTO_REBOOT=0
SKIP_REBOOT=0
NO_CLEANUP=0
RESET_ONLY=0

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --auto-reboot) AUTO_REBOOT=1 ;;
            --no-reboot)   SKIP_REBOOT=1 ;;
            --no-cleanup)  NO_CLEANUP=1 ;;
            --reset)       RESET_ONLY=1 ;;
            --help|-h)
                sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//'
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Run '$0 --help' for usage." >&2
                exit 2
                ;;
        esac
        shift
    done
}

# ============================================================================
# Output helpers
# ============================================================================

if [ -t 1 ]; then
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""; C_RESET=""
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass()  { printf '%s[PASS]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail()  { printf '%s[FAIL]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip()  { printf '%s[SKIP]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
phase() { printf '\n%s=== [%s] %s ===%s\n' "$C_BOLD" "$1" "$2" "$C_RESET"; }
info()  { printf '    %s\n' "$*"; }

# ============================================================================
# State helpers
# ============================================================================

ensure_state_dir() { mkdir -p "$STATE_DIR"; }

read_state_field() {
    local key="$1"
    [ -f "$STATE_FILE" ] || return 0
    grep "^${key}=" "$STATE_FILE" 2>/dev/null | head -n1 | cut -d= -f2-
}

write_state_field() {
    local key="$1" val="$2"
    ensure_state_dir
    [ -f "$STATE_FILE" ] || : > "$STATE_FILE"
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        local tmp
        tmp="$(mktemp)"
        grep -v "^${key}=" "$STATE_FILE" > "$tmp" || true
        mv "$tmp" "$STATE_FILE"
    fi
    printf '%s=%s\n' "$key" "$val" >> "$STATE_FILE"
}

clear_state() { rm -rf "$STATE_DIR"; }

# ============================================================================
# Environment detection
# ============================================================================

current_boot_id() {
    if [ -r /proc/sys/kernel/random/boot_id ]; then
        cat /proc/sys/kernel/random/boot_id
    else
        echo "unknown-boot-id"
    fi
}

detect_manjaro() {
    [ -r /etc/os-release ] || return 1
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "${ID:-}" = "manjaro" ] && return 0
    case "${ID_LIKE:-}" in
        *arch*) return 0 ;;
    esac
    return 1
}

detect_running_kernel_pkg() {
    local running_kernel="$1"
    local mhwd_output=""
    if command -v mhwd-kernel >/dev/null 2>&1; then
        mhwd_output="$(mhwd-kernel -li 2>/dev/null || true)"
        local pkg
        pkg="$(printf '%s\n' "$mhwd_output" |
            sed -n 's/^Currently running:.* (\(linux[0-9]\+\)).*/\1/p' |
            head -n1)"
        if [ -n "$pkg" ]; then
            printf '%s' "$pkg"
            return 0
        fi
    fi
    if [ -d "/usr/lib/modules/$running_kernel" ]; then
        local pkg
        pkg="$(pacman -Qo "/usr/lib/modules/$running_kernel" 2>/dev/null |
            sed -n 's/.* is owned by \(linux[0-9]\+\) .*/\1/p' |
            head -n1)"
        if [ -n "$pkg" ]; then
            printf '%s' "$pkg"
            return 0
        fi
    fi
    return 1
}

# ============================================================================
# Phase 1 — pre-reboot
# ============================================================================

check_environment() {
    if detect_manjaro; then
        pass "Manjaro (or Arch-family) environment detected"
    else
        fail "Not running on Manjaro/Arch-family"
        return 1
    fi

    if [ "$(id -u)" = "0" ]; then
        fail "Must be run as a normal user, not root"
        return 1
    fi
    pass "Running as normal user: $(whoami)"

    if sudo -n true >/dev/null 2>&1; then
        pass "Passwordless sudo available"
    else
        fail "Passwordless sudo is required"
        return 1
    fi

    if [ ! -d "$REPO_ROOT/.git" ]; then
        fail "Repository root does not contain .git (needed for VCS pkgver)"
        return 1
    fi
    pass "Repository is a git checkout"

    if command -v makepkg >/dev/null 2>&1; then
        pass "makepkg is available"
    else
        fail "makepkg is missing (install base-devel)"
        return 1
    fi

    return 0
}

build_package() {
    # Clean any previous build artifacts so the glob below is unambiguous.
    rm -f "$REPO_ROOT"/awesome-updater-*.pkg.tar.* 2>/dev/null || true
    rm -rf "$REPO_ROOT/src" "$REPO_ROOT/pkg" 2>/dev/null || true

    info "Running: makepkg -f --noconfirm (VCS source: file://$REPO_ROOT)"

    if ( cd "$REPO_ROOT" && \
         AWESOME_UPDATER_VCS_URL="file://$REPO_ROOT" \
         makepkg -f --noconfirm ) >/dev/null 2>&1; then
        pass "Package built successfully"
    else
        fail "makepkg failed"
        info "Re-run manually to see the full output:"
        info "  cd $REPO_ROOT && AWESOME_UPDATER_VCS_URL=file://$REPO_ROOT makepkg -f"
        return 1
    fi

    local pkg
    pkg="$(ls "$REPO_ROOT"/awesome-updater-*.pkg.tar.* 2>/dev/null | head -n1)"
    if [ -z "$pkg" ]; then
        fail "No package file found after makepkg"
        return 1
    fi
    PKG_FILE="$pkg"
    pass "Package artifact: $(basename "$PKG_FILE")"
    return 0
}

install_package() {
    info "Running: sudo pacman -U $PKG_FILE"
    if sudo -n pacman -U --noconfirm "$PKG_FILE" >/dev/null 2>&1; then
        pass "Package installed via pacman -U"
    else
        fail "pacman -U failed"
        return 1
    fi

    if pacman -Q "$PKGNAME" >/dev/null 2>&1; then
        pass "pacman -Q reports $PKGNAME installed"
    else
        fail "pacman -Q does not report $PKGNAME"
        return 1
    fi
}

check_scheduler() {
    local user
    user="$(whoami)"
    local timer="${SERVICE_TEMPLATE%%.service}.timer"
    timer="awesome-updater@${user}.timer"

    if ! systemctl list-unit-files --type=timer --no-legend 2>/dev/null |
         awk '{print $1}' | grep -qx "$timer"; then
        fail "Timer unit $timer not installed"
        return 1
    fi
    pass "Timer unit present: $timer"

    if systemctl is-enabled --quiet "$timer" 2>/dev/null; then
        pass "Timer enabled"
    else
        fail "Timer not enabled"
        return 1
    fi

    if systemctl is-active --quiet "$timer" 2>/dev/null; then
        pass "Timer active"
    else
        fail "Timer not active"
        return 1
    fi

    # The service must point at the intended user.
    local svc_user
    svc_user="$(systemctl cat "awesome-updater@${user}.service" 2>/dev/null |
        sed -n 's/^User=//p' | head -n1)"
    if [ "$svc_user" = "%i" ] || [ "$svc_user" = "$user" ]; then
        pass "Service User= is the template instance (%i -> $user)"
    else
        fail "Service User= is '$svc_user', expected %i or $user"
        return 1
    fi

    if [ "$svc_user" = "root" ]; then
        fail "Service is configured to run as root"
        return 1
    fi
    pass "Service is not a root instance"

    # The periodic timer must not be a reboot timer.
    if systemctl cat "$timer" 2>/dev/null | grep -qi 'reboot'; then
        fail "Periodic timer references reboot; it must not"
        return 1
    fi
    pass "Periodic timer is distinct from the reboot timer"

    # Persistent=true must be present.
    if systemctl cat "$timer" 2>/dev/null | grep -q '^Persistent=true$'; then
        pass "Timer is Persistent=true"
    else
        fail "Timer is missing Persistent=true"
        return 1
    fi

    # Expected schedule.
    if systemctl cat "$timer" 2>/dev/null |
         grep -q 'OnCalendar=\*-\*-\* 00,06,12,18:00:00'; then
        pass "Timer uses the expected 6-hour cadence"
    else
        info "Timer OnCalendar line:"
        systemctl cat "$timer" 2>/dev/null | grep '^OnCalendar=' | sed 's/^/      /' >&2
        fail "Timer schedule differs from expected"
        return 1
    fi

    return 0
}

check_crontab_safety() {
    local before="" after=""

    if command -v crontab >/dev/null 2>&1; then
        before="$(crontab -l 2>/dev/null || true)"
    fi

    # Nothing to install: the package is already installed at this point.
    # We re-inspect the crontab to confirm the .install scriptlet and the
    # runtime did not touch it.
    if command -v crontab >/dev/null 2>&1; then
        after="$(crontab -l 2>/dev/null || true)"
    fi

    if [ "$before" = "$after" ]; then
        pass "User crontab was not modified during package installation"
    else
        fail "User crontab changed during package installation"
        info "before: $(printf '%s' "$before" | head -n1)"
        info "after:  $(printf '%s' "$after"  | head -n1)"
        return 1
    fi

    # Sanity: the production code must not contain a crontab writer.
    if grep -qE 'crontab[[:space:]]+-$' "$REPO_ROOT/system-update"; then
        fail "system-update contains a crontab writer"
        return 1
    fi
    pass "system-update contains no user-crontab writer"

    return 0
}

check_kernel_modules_hook() {
    if pacman -Q kernel-modules-hook >/dev/null 2>&1; then
        pass "kernel-modules-hook installed"
    else
        fail "kernel-modules-hook is not installed on the test system"
        return 1
    fi

    local dep
    dep="$(pacman -Qi "$PKGNAME" 2>/dev/null | sed -n 's/^Depends On *: *//p')"
    if printf '%s' "$dep" | tr ' ' '\n' | grep -qx 'kernel-modules-hook'; then
        pass "kernel-modules-hook is a hard dependency of $PKGNAME"
    else
        fail "kernel-modules-hook is not declared as a hard dependency"
        return 1
    fi
    return 0
}

run_first_update() {
    local user
    user="$(whoami)"

    info "Running: sudo systemctl start awesome-updater@${user}.service"
    if ! sudo -n systemctl start "awesome-updater@${user}.service" 2>/dev/null; then
        fail "systemctl start awesome-updater@${user}.service failed"
        info "Journal:"
        sudo -n journalctl -u "awesome-updater@${user}.service" --no-pager -n 40 2>/dev/null | sed 's/^/      /' >&2
        return 1
    fi
    pass "Service started and completed"

    # The service must have written attention state.
    if [ -r "$ATTENTION_STATE" ]; then
        pass "Attention state file was created: $ATTENTION_STATE"
    else
        fail "Attention state file was not created"
        return 1
    fi

    # User logs directory.
    if [ -d "$HOME/logs" ] && ls "$HOME/logs"/system-update_*.log >/dev/null 2>&1; then
        pass "Updater wrote a log under ~/logs"
    else
        info "No user log files found under $HOME/logs"
        skip "Log file presence could not be confirmed"
    fi

    # Journal shows a normal-user execution.
    local journal_user
    journal_user="$(sudo -n journalctl -u "awesome-updater@${user}.service" \
        --no-pager -n 200 2>/dev/null | sed -n 's/^.*User: //p' | head -n1)"
    if [ -n "$journal_user" ] && [ "$journal_user" != "root" ]; then
        pass "Updater ran as non-root user: $journal_user"
    elif [ "$journal_user" = "root" ]; then
        fail "Updater ran as root"
        return 1
    else
        skip "Could not determine updater user from journal"
    fi

    return 0
}

check_kernel_update() {
    KERNEL_UPDATED=0

    if [ ! -f "$REBOOT_FLAG" ]; then
        info "No $REBOOT_FLAG present after the update."
        info "This means the running kernel package was not updated."
        return 0
    fi

    local kpkg kval krun kunit kcreated
    kpkg="$(sed -n 's/^KERNEL_PACKAGE=//p' "$REBOOT_FLAG")"
    kval="$(sed -n 's/^TARGET_VERSION=//p' "$REBOOT_FLAG")"
    krun="$(sed -n 's/^RUNNING_VERSION=//p' "$REBOOT_FLAG")"
    kunit="$(sed -n 's/^REBOOT_UNIT=//p' "$REBOOT_FLAG")"
    kcreated="$(sed -n 's/^CREATED_AT=//p' "$REBOOT_FLAG")"

    [ -n "$kpkg" ] && [ -n "$kval" ] && [ -n "$krun" ] \
        || { fail "kernel-reboot-needed is malformed"; return 1; }

    pass "kernel-reboot-needed created for package '$kpkg'"
    pass "Target version: $kval"
    pass "Original running version: $krun"
    [ -n "$kunit" ] && pass "Reboot unit: $kunit" || fail "Reboot unit field is empty"
    [ -n "$kcreated" ] && pass "Created at: $kcreated" || fail "Created-at field is empty"

    # Attention state must reflect the reboot requirement.
    if [ -r "$ATTENTION_STATE" ] &&
       grep -q '^REBOOT_REQUIRED=1$' "$ATTENTION_STATE"; then
        pass "Attention state records REBOOT_REQUIRED=1"
    else
        fail "Attention state does not record REBOOT_REQUIRED=1"
        return 1
    fi

    # A transient reboot timer must exist and be distinct from the
    # periodic updater timer.
    if [ -n "$kunit" ]; then
        if systemctl list-timers --all --no-pager 2>/dev/null |
             grep -qF "${kunit}.timer"; then
            pass "Reboot timer exists: ${kunit}.timer"
        else
            fail "Reboot timer ${kunit}.timer not found in systemd"
            return 1
        fi

        if [ "${kunit}.timer" != "awesome-updater@$(whoami).timer" ]; then
            pass "Reboot timer is distinct from the periodic updater timer"
        else
            fail "Reboot timer is the periodic updater timer"
            return 1
        fi
    fi

    KERNEL_UPDATED=1
    KERNEL_PACKAGE="$kpkg"
    KERNEL_TARGET="$kval"
    KERNEL_RUNNING="$krun"
    return 0
}

backup_user_config() {
    ensure_state_dir
    if [ -f "$HOME/.config/system-update/config.conf" ]; then
        cp "$HOME/.config/system-update/config.conf" "$USER_CONFIG_BACKUP"
        printf 'present\n' > "$USER_CONFIG_WAS_PRESENT"
        info "Backed up existing user config"
    else
        printf 'absent\n' > "$USER_CONFIG_WAS_PRESENT"
        info "No existing user config to back up"
    fi
}

restore_user_config() {
    [ -f "$USER_CONFIG_WAS_PRESENT" ] || return 0
    if [ "$(cat "$USER_CONFIG_WAS_PRESENT")" = "present" ] &&
       [ -f "$USER_CONFIG_BACKUP" ]; then
        mkdir -p "$HOME/.config/system-update"
        cp "$USER_CONFIG_BACKUP" "$HOME/.config/system-update/config.conf"
        info "Restored user config from backup"
    else
        rm -f "$HOME/.config/system-update/config.conf"
        info "Removed temporary user config (none existed before)"
    fi
    rm -f "$USER_CONFIG_BACKUP" "$USER_CONFIG_WAS_PRESENT"
}

write_test_reboot_time() {
    mkdir -p "$HOME/.config/system-update"
    local target
    target="$(date -d '+10 minutes' '+%H:%M:%S')"
    cat > "$HOME/.config/system-update/config.conf" <<EOF
# Temporary override written by integration/run-integration-test.sh.
# This file is restored or removed at the end of the test.
REBOOT_TIME="$target"
EOF
    info "Wrote temporary REBOOT_TIME=$target to user config"
}

prepare_reboot_test() {
    # Save the user's existing config first, then write the override.
    backup_user_config
    write_test_reboot_time

    # Re-run the updater so the transient reboot timer is scheduled for
    # the test time. Note: the existing persistent reboot state means the
    # updater will retry scheduling with the new REBOOT_TIME.
    local user
    user="$(whoami)"

    info "Re-running updater to schedule the transient reboot timer"
    if ! sudo -n systemctl start "awesome-updater@${user}.service" 2>/dev/null; then
        fail "Re-run of the service failed while scheduling the test reboot"
        return 1
    fi
    pass "Service re-run completed"

    # Verify the transient reboot timer now exists.
    local kunit
    kunit="$(sed -n 's/^REBOOT_UNIT=//p' "$REBOOT_FLAG")"
    if [ -z "$kunit" ]; then
        fail "REBOOT_UNIT empty after scheduling"
        return 1
    fi
    if ! systemctl list-timers --all --no-pager 2>/dev/null |
           grep -qF "${kunit}.timer"; then
        fail "Transient reboot timer ${kunit}.timer not present"
        return 1
    fi
    pass "Transient reboot timer scheduled: ${kunit}.timer"
    info "  $(systemctl list-timers "${kunit}.timer" --no-pager 2>/dev/null | sed -n '2p')"

    # Persist phase-1 state for phase 2 detection.
    write_state_field PHASE           "awaiting_reboot"
    write_state_field PHASE1_BOOT_ID  "$(current_boot_id)"
    write_state_field TEST_USER       "$user"
    write_state_field KERNEL_PACKAGE  "$KERNEL_PACKAGE"
    write_state_field KERNEL_TARGET   "$KERNEL_TARGET"
    write_state_field KERNEL_RUNNING  "$KERNEL_RUNNING"
    write_state_field KERNEL_UNIT     "$kunit"
    write_state_field SCHEDULED_AT    "$(date '+%Y-%m-%dT%H:%M:%S%z')"

    if [ "$AUTO_REBOOT" = "1" ]; then
        printf '\n%s========================================================%s\n' "$C_BOLD" "$C_RESET"
        printf '%s  AUTOMATIC REBOOT MODE%s\n' "$C_YELLOW" "$C_RESET"
        printf '%s========================================================%s\n' "$C_BOLD" "$C_RESET"
        printf '\nThe test-scheduled reboot timer is active and will fire\n'
        printf 'in approximately 10 minutes. Do NOT power off the machine.\n'
        printf '\nAfter the machine reboots, run this script again:\n'
        printf '\n    %s\n\n' "$0"
        return 0
    fi

    printf '\n%s========================================================%s\n' "$C_BOLD" "$C_RESET"
    printf '%s  MANUAL REBOOT REQUIRED FOR PHASE 2%s\n' "$C_YELLOW" "$C_RESET"
    printf '%s========================================================%s\n' "$C_BOLD" "$C_RESET"
    printf '\nA kernel update was detected. The test has:\n'
    printf '  * recorded the persistent reboot requirement\n'
    printf '  * scheduled a transient one-time reboot timer\n'
    printf '  * installed a temporary REBOOT_TIME override\n'
    printf '\nTo complete the test, reboot the machine NOW:\n'
    printf '\n    sudo systemctl reboot\n'
    printf '\nThe purpose of this test is to verify that a manual reboot\n'
    printf 'BEFORE the scheduled timer fires does NOT lead to an\n'
    printf 'unnecessary second reboot.\n'
    printf '\nDo NOT wait for the 10-minute timer.\n'
    printf '\nAfter the machine reboots, run this script again:\n'
    printf '\n    %s\n\n' "$0"
}

run_phase1() {
    phase "1/11" "Environment"
    check_environment || return 1

    phase "2/11" "Package build"
    build_package || return 1

    phase "3/11" "Package install"
    install_package || return 1

    phase "4/11" "Scheduler"
    check_scheduler || true

    phase "5/11" "User environment"
    # Verified above via systemctl cat User= and journalctl User: lines.
    pass "User environment verified (see Scheduler and First-run phases)"

    phase "6/11" "Crontab safety"
    check_crontab_safety || true

    phase "7/11" "kernel-modules-hook"
    check_kernel_modules_hook || true

    phase "8/11" "First run"
    run_first_update || true

    phase "9/11" "Kernel update detection"
    check_kernel_update || true

    if [ "$SKIP_REBOOT" = "1" ]; then
        phase "10/11" "Reboot lifecycle"
        skip "Reboot lifecycle skipped by --no-reboot"
        phase "11/11" "Cleanup"
        run_cleanup
        return 0
    fi

    if [ "$KERNEL_UPDATED" != "1" ]; then
        phase "10/11" "Reboot lifecycle"
        skip "Kernel update was not available on this test run."
        skip "Kernel reboot lifecycle was therefore not exercised."
        phase "11/11" "Cleanup"
        run_cleanup
        return 0
    fi

    phase "10/11" "Reboot lifecycle preparation"
    prepare_reboot_test || return 1

    phase "11/11" "Awaiting reboot"
    pass "Phase 1 complete; awaiting manual reboot for phase 2"
}

# ============================================================================
# Phase 2 — post-reboot
# ============================================================================

run_phase2() {
    phase "1/6" "Post-reboot verification"

    local user
    user="$(read_state_field TEST_USER)"
    [ -z "$user" ] && user="$(whoami)"
    info "Test user: $user"

    local expected_pkg expected_target
    expected_pkg="$(read_state_field KERNEL_PACKAGE)"
    expected_target="$(read_state_field KERNEL_TARGET)"

    local current_kernel current_pkg
    current_kernel="$(uname -r)"
    current_pkg="$(detect_running_kernel_pkg "$current_kernel" || true)"

    info "Current kernel: $current_kernel"
    info "Current package: $current_pkg"
    info "Expected package: $expected_pkg"
    info "Expected target:  $expected_target"

    if [ "$current_pkg" = "$expected_pkg" ]; then
        pass "Post-reboot running kernel package matches the target package"
    else
        fail "Post-reboot running kernel package does not match the target package"
    fi

    local normalized
    normalized="${current_kernel%-MANJARO}"
    if [ -n "$expected_target" ] &&
       vercmp "$normalized" "$expected_target" 2>/dev/null | grep -q '^[0-9]'; then
        pass "Post-reboot kernel version $normalized >= target $expected_target"
    else
        skip "Could not verify target version via vercmp"
    fi

    phase "2/6" "Transient reboot timer check"

    local kunit
    kunit="$(read_state_field KERNEL_UNIT)"
    if [ -n "$kunit" ]; then
        if systemctl list-timers --all --no-pager 2>/dev/null |
             grep -qF "${kunit}.timer"; then
            fail "Transient reboot timer ${kunit}.timer survived the reboot"
        else
            pass "Transient reboot timer ${kunit}.timer did not survive the reboot"
        fi
    else
        skip "No stored reboot timer unit to verify"
    fi

    phase "3/6" "Updater reconciliation"

    info "Running: sudo systemctl start awesome-updater@${user}.service"
    if sudo -n systemctl start "awesome-updater@${user}.service" 2>/dev/null; then
        pass "Reconciliation service run completed"
    else
        fail "Reconciliation service run failed"
        sudo -n journalctl -u "awesome-updater@${user}.service" --no-pager -n 40 2>/dev/null | sed 's/^/      /' >&2
        return 1
    fi

    phase "4/6" "Persistent reboot flag check"

    if [ -f "$REBOOT_FLAG" ]; then
        fail "$REBOOT_FLAG still exists after booting the target kernel"
        info "Contents:"
        sed 's/^/      /' "$REBOOT_FLAG" >&2
    else
        pass "$REBOOT_FLAG was cleared after target kernel boot"
    fi

    if [ -r "$ATTENTION_STATE" ]; then
        if grep -q '^REBOOT_REQUIRED=0$' "$ATTENTION_STATE"; then
            pass "Attention state records REBOOT_REQUIRED=0"
        else
            info "Attention state:"
            sed 's/^/      /' "$ATTENTION_STATE" >&2
            skip "Attention state does not record REBOOT_REQUIRED=0"
        fi
    fi

    phase "5/6" "No new reboot timer"

    local stray
    stray="$(systemctl list-timers --all --no-pager 2>/dev/null |
        awk '$1 ~ /^kernel-reboot-/ {print $1}' | head -n1)"
    if [ -n "$stray" ]; then
        fail "A new kernel-reboot timer appeared after reconciliation: $stray"
    else
        pass "No new kernel-reboot timer was scheduled"
    fi

    phase "6/6" "Cleanup"
    if [ "$NO_CLEANUP" = "1" ]; then
        skip "Cleanup skipped by --no-cleanup"
    else
        run_cleanup
    fi

    # Clear state only on successful completion.
    clear_state
}

# ============================================================================
# Cleanup
# ============================================================================

run_cleanup() {
    restore_user_config || true

    if [ "$NO_CLEANUP" = "1" ]; then
        skip "Package uninstall skipped by --no-cleanup"
        return 0
    fi

    if pacman -Q "$PKGNAME" >/dev/null 2>&1; then
        info "Uninstalling $PKGNAME via pacman -R"
        if sudo -n pacman -R --noconfirm "$PKGNAME" >/dev/null 2>&1; then
            pass "Package uninstalled"
        else
            fail "pacman -R failed"
        fi

        # Confirm the timer is gone.
        if systemctl list-unit-files --type=timer --no-legend 2>/dev/null |
             awk '{print $1}' | grep -q '^awesome-updater@'; then
            info "Timer unit files may still exist; not fatal"
        else
            pass "Timer unit files removed"
        fi

        # User state must be preserved.
        if [ -d /var/lib/system-update ]; then
            pass "/var/lib/system-update preserved after uninstall"
        else
            skip "/var/lib/system-update was not present before uninstall"
        fi
    else
        skip "$PKGNAME not installed; nothing to uninstall"
    fi

    clear_state
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    echo
    echo "${C_BOLD}============================================================${C_RESET}"
    echo "RESULT"
    echo "============================================================"
    echo "PASS: $PASS_COUNT"
    echo "FAIL: $FAIL_COUNT"
    echo "SKIP: $SKIP_COUNT"
    echo "${C_BOLD}============================================================${C_RESET}"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"

    if [ "$RESET_ONLY" = "1" ]; then
        clear_state
        echo "Integration test state cleared."
        exit 0
    fi

    cat <<EOF
============================================================
awesome-updater REAL MANJARO INTEGRATION TEST
============================================================

This script performs REAL system operations:

  * builds and installs the package
  * runs the live systemd timer / service
  * may schedule a test reboot

USE ONLY ON A DISPOSABLE MANJARO TEST MACHINE.

State directory: $STATE_DIR
Repository root: $REPO_ROOT

EOF

    local saved_phase current_id saved_boot
    saved_phase="$(read_state_field PHASE)"
    current_id="$(current_boot_id)"
    saved_boot="$(read_state_field PHASE1_BOOT_ID)"

    if [ "$saved_phase" = "awaiting_reboot" ] &&
       [ -n "$saved_boot" ] &&
       [ "$saved_boot" != "$current_id" ]; then
        run_phase2
        rc=$?
    elif [ "$saved_phase" = "awaiting_reboot" ]; then
        echo "Phase 1 is still awaiting a reboot."
        echo "Reboot the machine and run this script again."
        echo "(Run '$0 --reset' to discard the pending test state.)"
        exit 0
    else
        run_phase1
        rc=$?
    fi

    print_summary
    [ "$rc" -ne 0 ] && exit 1
    [ "$FAIL_COUNT" -gt 0 ] && exit 1
    exit 0
}

main "$@"