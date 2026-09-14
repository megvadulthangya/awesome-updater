#!/bin/bash
#
# /etc/profile.d/99-system-update.sh
#
# Login-time notification hook installed by the awesome-updater package.
#
# This file is sourced into the login shell. It must NEVER call "exit".
# It uses "return" exclusively.
#
# Behavior:
#   - Does nothing for non-interactive shells.
#   - Does nothing if the notification helper is not available.
#   - Never fails the login shell.

# Only run in interactive shells.
case "$-" in
    *i*) ;;
    *) return 0 2>/dev/null || true ;;
esac

# Only run if the helper is installed.
[ -x /usr/bin/system-update-notify ] || return 0 2>/dev/null || true

# Never propagate errors to the login shell.
/usr/bin/system-update-notify --tty 2>/dev/null || true