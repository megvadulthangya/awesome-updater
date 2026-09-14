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

### Changed
- Project is being converted from a single-script implementation into a
  package-managed project.
- Scope restricted to Manjaro Linux. No Ubuntu/Debian compatibility.
- AUR support is present but disabled by default via `AUR_ENABLED=false`.

### Notes
- The main `system-update` runtime is not yet implemented. It is currently
  a placeholder and will be replaced in a later phase.

## [0.1.0] - 2026-09-14

Initial package skeleton.