# awesome-updater

A Manjaro-focused unattended system updater with persistent kernel reboot
handling and user-facing notifications.

The `awesome-updater` package provides the `system-update` command.

## Scope

This project is intentionally **Manjaro-specific**. It does not target
Ubuntu, Debian, or other distributions. It uses Manjaro's `mhwd-kernel`
with a `pacman -Qo` fallback to identify the running kernel package.

Login notifications use `/etc/profile.d/`, the standard Manjaro / Arch
mechanism. `/etc/update-motd.d/` is out of scope.

## Installation

Install the package. No manual configuration is required.

The package installs a working default configuration at:

    /etc/system-update/config.conf

The defaults are safe and suitable for a fresh Manjaro system.

If a previous manual installation of the original single-script version
is still present on disk, read the migration section below before
installing.

## Commands

    system-update                 # run the update
    system-update --help
    system-update --version
    system-update --status        # read-only state report

    system-update-notify --tty
    system-update-notify --gui
    system-update-notify --gui-watch

## Configuration

Configuration is loaded in the following order. Later sources override
earlier ones:

    Built-in defaults
            ↓
    /etc/system-update/config.conf          (installed by the package)
            ↓
    ~/.config/system-update/config.conf     (optional user overrides)

The user override file is optional and normally does not exist. To
override a setting, create the file and include only the keys you want to
change.

Format: `KEY=VALUE`. No shell code is executed.

Supported keys:

    OFFICIAL_UPDATES_ENABLED
    AUR_ENABLED
    AUTOMATIC_REBOOT
    REBOOT_TIME
    INSTALL_CRONTAB
    CRONTAB_SCHEDULE
    NOTIFY_PROFILE_D
    NOTIFY_WALL
    NOTIFY_GUI
    LOG_RETENTION_DAYS

`NOTIFY_PROFILE_D` controls whether
`/etc/profile.d/99-system-update.sh` prints the attention message on
interactive login. The profile hook reads this key directly from the
configuration hierarchy at login time; the updater does not rewrite the
package-owned hook.

## AUR support

AUR updates are **disabled by default**:

    AUR_ENABLED=false

When disabled:

- `yay` is not installed by this script
- `git` and `makepkg` are not required
- no AUR operation is performed

When enabled (`AUR_ENABLED=true`), the script bootstraps `yay` from the
AUR if missing and runs `yay -Sua`.

> Warning: unattended AUR updates accept AUR PKGBUILD changes without
> review. Only enable this if you understand and accept that risk.

## Automatic kernel reboot

When a kernel package that provides the currently running kernel is
updated, the script records a persistent reboot requirement.

With `AUTOMATIC_REBOOT=true` (default), a one-time transient systemd
timer is scheduled for the next occurrence of `REBOOT_TIME` (default
`02:15:00` local time). The timer is created with `systemd-run` and is not
persistent across reboots.

With `AUTOMATIC_REBOOT=false`, no reboot is scheduled. The attention state
and login notifications report that a manual reboot is required.

## Periodic execution

The updater is designed to be run from the user's crontab.

By default the package does **not** modify the crontab. To let the script
install its own entry, set in the configuration:

    INSTALL_CRONTAB=true
    CRONTAB_SCHEDULE="0 */6 * * *"

Then run `system-update` once. The script adds (or updates) a crontab
entry pointing at `/usr/bin/system-update`. Existing entries that invoke
the notification helper or any other command are preserved. Only entries
whose command is exactly the updater path are replaced.

## Notifications

Three notification channels are available:

- **TTY / SSH login**: `/etc/profile.d/99-system-update.sh` invokes
  `system-update-notify --tty` on interactive logins when
  `NOTIFY_PROFILE_D` is `true`. The hook is package-managed and is not
  rewritten at runtime.
- **Wall broadcast**: `system-update` calls `wall` when the attention
  state changes, reaching all connected terminals.
- **Desktop**: an XDG autostart entry runs
  `system-update-notify --gui-watch` inside the desktop session. It uses
  `notify-send` if available. Setting `NOTIFY_GUI=false` removes the
  autostart entry on the next updater run.

## Logs

    ~/logs/latest_update.log
    ~/logs/system-update_YYYY-MM-DD_HH-MM-SS.log

Logs older than `LOG_RETENTION_DAYS` are removed automatically.

## Runtime state

    /var/lib/system-update/attention.state
    /var/lib/system-update/kernel-reboot-needed

The state directory is fixed and is not configurable.

## Migration from an older manual installation

A previous manual installation of the original single-script version may
have created files that are not owned by any pacman package. Because
pacman refuses to overwrite unowned files, the first package installation
can fail unless those files are removed first.

The paths to check are:

    /usr/local/bin/system-update
    /usr/local/bin/system-update-notify
    /etc/profile.d/99-system-update.sh
    /etc/system-update/config.conf

The first two shadow the package-managed binaries because `/usr/local/bin`
precedes `/usr/bin` in `PATH`. The third conflicts directly with the
`/etc/profile.d/99-system-update.sh` hook installed by the package. The
fourth conflicts with the package-managed default configuration file.

The package refuses to delete any of these files automatically. The
`pre_install` scriptlet of the package prints a non-destructive notice
listing every unowned conflicting path it detects.

To complete the migration manually:

    sudo rm -f /usr/local/bin/system-update
    sudo rm -f /usr/local/bin/system-update-notify
    sudo rm -f /etc/profile.d/99-system-update.sh
    sudo rm -f /etc/system-update/config.conf

Then install the package. If a crontab entry still references the legacy
path, update it to `/usr/bin/system-update`.

## License

MIT.