# awesome-updater

[![Tests](https://github.com/megvadulthangya/awesome-updater/actions/workflows/tests.yml/badge.svg)](https://github.com/megvadulthangya/awesome-updater/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Manjaro](https://img.shields.io/badge/Platform-Manjaro-35BF5C.svg)](https://manjaro.org/)

A Manjaro-focused unattended system updater with persistent kernel reboot
handling and user-facing notifications.

The `awesome-updater` package provides the `system-update` command and a
package-managed systemd timer that runs it periodically as a normal user.

## Scope

This project is intentionally **Manjaro-specific**. It does not target
Ubuntu, Debian, or other distributions. It uses Manjaro's `mhwd-kernel`
with a `pacman -Qo` fallback to identify the running kernel package.

Login notifications use `/etc/profile.d/`, the standard Manjaro / Arch
mechanism. `/etc/update-motd.d/` is out of scope.

## Installation

Install the package. When the installer can identify the invoking normal
user (for example via `SUDO_USER` when installing with `sudo`, or via
`PKEXEC_UID`/`DOAS_USER` for `pkexec`/`doas`), periodic updater execution
is activated automatically:

    sudo pacman -S awesome-updater

After installation, a systemd timer named
`awesome-updater@<user>.timer` runs the updater every six hours, at
00:00, 06:00, 12:00 and 18:00 local time.

    systemctl list-timers 'awesome-updater@*'

The user crontab is **not** modified by this package.

If the invoking normal user cannot be determined (for example when the
package is installed directly by `root` without `sudo`), the package still
installs successfully and prints the exact `systemctl enable` command
needed to activate the periodic updater manually. No root updater
instance is ever created.

## Configuration

Configuration is optional. The defaults are safe and suitable for a fresh
Manjaro system. If you want to override individual settings, create the
user override file and include only the keys you want to change.

Configuration is loaded in the following order. Later sources override
earlier ones:

    Built-in defaults
            ↓
    /etc/system-update/config.conf          (installed by the package)
            ↓
    ~/.config/system-update/config.conf     (optional user overrides)

Format: `KEY=VALUE`. No shell code is executed.

Supported keys:

    OFFICIAL_UPDATES_ENABLED
    AUR_ENABLED
    AUTOMATIC_REBOOT
    REBOOT_TIME
    NOTIFY_PROFILE_D
    NOTIFY_WALL
    NOTIFY_GUI
    LOG_RETENTION_DAYS

`NOTIFY_PROFILE_D` controls whether
`/etc/profile.d/99-system-update.sh` prints the attention message on
interactive login. The profile hook reads this key directly from the
configuration hierarchy at login time; the updater does not rewrite the
package-owned hook.

## Scheduler

Periodic execution is provided by a systemd system timer. The package
enables exactly one instance, keyed to the target normal user. The
underlying service is:

    /usr/lib/systemd/system/awesome-updater@.service
    /usr/lib/systemd/system/awesome-updater@.timer

The timer's default cadence is `*-*-* 00,06,12,18:00:00` with
`Persistent=true`.

Useful commands:

    systemctl list-timers 'awesome-updater@*'
    systemctl status 'awesome-updater@<user>.timer'
    systemctl status 'awesome-updater@<user>.service'
    journalctl -u 'awesome-updater@<user>.service'

Override the schedule without editing the package-managed unit file:

    systemctl edit awesome-updater@<user>.timer

Enable a specific user's timer manually (for example, if automatic user
discovery could not determine the invoking normal user):

    sudo systemctl enable --now awesome-updater@<username>.timer

Do not use `root` as the username. The updater refuses to run as root.

## Commands

    system-update                 # run the update manually
    system-update --help
    system-update --version
    system-update --status        # read-only state report

    system-update-notify --tty
    system-update-notify --gui
    system-update-notify --gui-watch

## Passwordless sudo

The updater is intended to run as a normal user with passwordless sudo
available for the specific commands it invokes. The updater performs an
explicit `sudo -n true` preflight check and refuses to continue if
passwordless sudo is not available. The package does not attempt to
handle interactive sudo prompts.

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
updated, the script records a persistent reboot requirement in:

    /var/lib/system-update/kernel-reboot-needed

With `AUTOMATIC_REBOOT=true` (default), a one-time transient systemd
timer is scheduled for the next occurrence of `REBOOT_TIME` (default
`02:15:00` local time). The timer is created with `systemd-run` and is
not persistent across reboots; it is independent of the periodic updater
timer and is never used to reboot the machine on a schedule.

With `AUTOMATIC_REBOOT=false`, no reboot is scheduled. The attention
state and login notifications report that a manual reboot is required.

The reboot requirement is verified at each subsequent run: if the target
kernel is already running, the persistent reboot flag is cleared; if the
machine was rebooted before the scheduled timer fired, the target kernel
is detected as running and no unnecessary reboot is performed.

## Kernel modules

The package depends on `kernel-modules-hook`. This keeps kernel modules
available on the currently running kernel until the machine actually
transitions to the new kernel, so that services do not lose their module
dependencies between a kernel upgrade and the following reboot.

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

Logs older than `LOG_RETENTION_DAYS` are removed automatically. If the
home directory is not writable, file logging is disabled with a warning
and the updater continues; systemd captures the output in the journal.

## Runtime state

    /var/lib/system-update/attention.state
    /var/lib/system-update/kernel-reboot-needed

The state directory is fixed and is not configurable.

## `.pacnew` files

The updater detects and reports `.pacnew` files under `/etc`. It never
merges them and never deletes them. Merging is the administrator's
decision.

## Building the package

The package is a VCS package. `makepkg` obtains the application source
from the project's Git repository and derives the package version from
the current revision:

    git clone https://github.com/megvadulthangya/awesome-updater.git
    cd awesome-updater
    makepkg -f --noconfirm

The resulting package name has the form:

    awesome-updater-r<commit-count>.<short-sha>-<pkgrel>-any.pkg.tar.zst

For reproducible CI builds against a local checkout, the VCS URL used by
`makepkg` can be overridden without editing the PKGBUILD:

    AWESOME_UPDATER_VCS_URL="file://$(pwd)" makepkg -f --noconfirm

## Testing

The project ships two complementary test suites.

**Isolated unit tests** (run automatically in CI, safe everywhere, no
real system modifications):

    ./tests/run-tests.sh

These build an isolated sandbox and mock every privileged tool
(`pacman`, `systemctl`, `systemd-run`, `sudo`, `crontab`, `wall`,
`notify-send`, `mhwd-kernel`, `vercmp`, `hostname`, `id`, `uname`,
`git`, `makepkg`).

**Portable real-Manjaro integration test** (manual, disposable test
machine only):

    integration/run-integration-test.sh

This builds the package, installs it with `pacman -U`, inspects the live
systemd timer and service, runs the real updater as the normal user, and
exercises the real kernel-reboot lifecycle. It performs real system
operations and may reboot the machine; read the header of the script
before running it.

## Migration from an older manual installation

A previous manual installation of the original single-script version may
have created files that are not owned by any pacman package, or a user
crontab entry pointing at the updater. Because pacman refuses to
overwrite unowned files, the first package installation can fail unless
those files are removed first.

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
`pre_install` scriptlet prints a non-destructive notice listing every
unowned conflicting path it detects, and the runtime prints a similar
warning for the `/usr/local/bin` files.

To complete the migration manually:

    sudo rm -f /usr/local/bin/system-update
    sudo rm -f /usr/local/bin/system-update-notify
    sudo rm -f /etc/profile.d/99-system-update.sh
    sudo rm -f /etc/system-update/config.conf

If a user crontab entry still references `/usr/bin/system-update` or
`/usr/local/bin/system-update`, remove it manually with `crontab -e`.
The package will warn about it but will not touch the crontab.

## License

MIT.