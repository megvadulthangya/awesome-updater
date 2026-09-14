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
#   - Honors NOTIFY_PROFILE_D from the configuration hierarchy:
#         built-in default ("true")
#         /etc/system-update/config.conf
#         ~/.config/system-update/config.conf
#     Later sources override earlier ones.
#   - The configuration is parsed as plain KEY=VALUE. No shell code is
#     executed, and only the NOTIFY_PROFILE_D key is consulted.
#   - Does nothing if the notification helper is not available.
#   - Never fails the login shell.

# Only run in interactive shells.
case "$-" in
    *i*) ;;
    *) return 0 2>/dev/null || true ;;
esac

# Only run if the helper is installed.
[ -x /usr/bin/system-update-notify ] || return 0 2>/dev/null || true

# ---------------------------------------------------------------------------
# Determine whether the TTY login notification is enabled.
#
# Runs in a subshell so the helper variables do not leak into the login
# shell.
# ---------------------------------------------------------------------------

_notify_profile_d_value="$(
    value="true"
    for file in \
        /etc/system-update/config.conf \
        "$HOME/.config/system-update/config.conf"
    do
        [ -r "$file" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            # Trim leading and trailing whitespace.
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"

            case "$line" in
                ''|\#*) continue ;;
            esac
            case "$line" in
                *=*) ;;
                *) continue ;;
            esac

            key="${line%%=*}"
            val="${line#*=}"

            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"

            case "$val" in
                \"*\") val="${val#\"}"; val="${val%\"}" ;;
                \'*\') val="${val#\'}"; val="${val%\'}" ;;
            esac

            if [ "$key" = "NOTIFY_PROFILE_D" ]; then
                value="$val"
            fi
        done < "$file"
    done
    printf '%s' "$value"
)"

case "$_notify_profile_d_value" in
    false)
        unset _notify_profile_d_value
        return 0 2>/dev/null || true
        ;;
esac

unset _notify_profile_d_value

# Never propagate errors to the login shell.
/usr/bin/system-update-notify --tty 2>/dev/null || true