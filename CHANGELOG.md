# Changelog

All notable changes to this project will be documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Package skeleton.
- Default configuration installed by the package at
  `/etc/system-update/config.conf`.
- Static helper `system-update-notify`.
- Static login hook `/etc/profile.d/99-system-update.sh`.
- Man pages for both commands.
- GitHub Actions ShellCheck workflow.
- Root-execution guard in `system-update` (matches the original script).
- Non-destructive migration notice in the package install scriptlet.
- Per-field cron schedule validation for `CRONTAB_SCHEDULE`.
- `NOTIFY_GUI=false` now removes any previously created XDG autostart
  entry instead of leaving it in place.

### Changed
- Project is being converted from a single-script implementation into a
  package-managed project.
- Scope restricted to Manjaro Linux. No Ubuntu/Debian compatibility.
- AUR support is present but disabled by default via `AUR_ENABLED=false`.
- `/etc/profile.d/99-system-update.sh` now honors `NOTIFY_PROFILE_D` by
  reading the configuration hierarchy directly at login time. The hook
  file itself is not rewritten at runtime.
- Crontab handling now removes only entries whose command is exactly the
  updater path, preserving unrelated jobs.
- `config_error` uses `sudo -n` so an invalid configuration can never
  block on an interactive password prompt.
- Cron installation failure now propagates into `UPDATE_FAILED` and
  `NEEDS_ATTENTION`, matching the original script.
- Early failure paths in `system-update` preserve a pre-existing
  `kernel-reboot-needed` state instead of resetting `REBOOT_REQUIRED`.
- Wall broadcasts are emitted on the AUR update failure path.
- Package now declares `inetutils` as a runtime dependency and `cronie`
  as an optional dependency.
- Runtime version string is single-sourced from `pkgver` via the
  `@VERSION@` placeholder.
- README and man page wording updated to reflect the actual runtime
  behaviour.

### Removed
- Placeholder note in the changelog that claimed the runtime was not
  implemented.
- Unused colour variables and dead locals in the runtime script.

## [0.1.0] - 2026-09-14

Initial package skeleton.