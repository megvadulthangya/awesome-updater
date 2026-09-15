#!/usr/bin/env bash
#
# Verify the shipped systemd unit files.

: "${TESTS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/harness.sh
source "$TESTS_DIR/lib/harness.sh"

SERVICE="$PROJECT_DIR/systemd/awesome-updater@.service"
TIMER="$PROJECT_DIR/systemd/awesome-updater@.timer"

test_service_file_exists() {
    if [ ! -f "$SERVICE" ]; then
        echo "    $SERVICE missing"
        return 1
    fi
    return 0
}

test_service_type_oneshot() {
    grep -qE '^Type=oneshot$' "$SERVICE" || {
        echo "    Type=oneshot not found"
        return 1
    }
    return 0
}

test_service_runs_as_instance_user() {
    grep -qE '^User=%i$' "$SERVICE" || {
        echo "    User=%i not found"
        grep -v '^#' "$SERVICE"
        return 1
    }
    return 0
}

test_service_execs_system_update() {
    grep -qE '^ExecStart=/usr/bin/system-update$' "$SERVICE" || {
        echo "    ExecStart wrong"
        grep '^ExecStart' "$SERVICE"
        return 1
    }
    return 0
}

test_service_does_not_run_as_root() {
    # The unit must not contain User=root or fall through to root.
    if grep -qE '^User=root$' "$SERVICE"; then
        echo "    service runs as root"
        return 1
    fi
    return 0
}

test_timer_file_exists() {
    if [ ! -f "$TIMER" ]; then
        echo "    $TIMER missing"
        return 1
    fi
    return 0
}

test_timer_schedule() {
    grep -qF 'OnCalendar=*-*-* 00,06,12,18:00:00' "$TIMER" || {
        echo "    OnCalendar wrong"
        grep '^OnCalendar' "$TIMER"
        return 1
    }
    return 0
}

test_timer_persistent() {
    grep -qE '^Persistent=true$' "$TIMER" || {
        echo "    Persistent=true not found"
        return 1
    }
    return 0
}

test_timer_targets_service() {
    grep -qE '^Unit=awesome-updater@%i\.service$' "$TIMER" || {
        echo "    Unit= line wrong"
        grep '^Unit=' "$TIMER"
        return 1
    }
    return 0
}

test_timer_wantedby_timers_target() {
    grep -qE '^WantedBy=timers\.target$' "$TIMER" || {
        echo "    WantedBy=timers.target not found"
        return 1
    }
    return 0
}

t test_service_file_exists
t test_service_type_oneshot
t test_service_runs_as_instance_user
t test_service_execs_system_update
t test_service_does_not_run_as_root
t test_timer_file_exists
t test_timer_schedule
t test_timer_persistent
t test_timer_targets_service
t test_timer_wantedby_timers_target

summary