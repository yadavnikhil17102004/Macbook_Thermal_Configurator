# Changelog

All notable changes to this project will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [1.1.0] — 2026-03-31

### Fixed
- `standby` display in system state snapshot was showing multiple values
  (matched `standbydelay`, `standbydelaylow`, etc.). Now uses exact key match.

### Added
- `--version` flag: `./thermal_manager.sh --version`
- `--help` flag: `./thermal_manager.sh --help` (non-interactive usage guide)
- `VERSION` constant inside the script for programmatic version checks
- `install.sh` — zero-friction installer that sets up a global `modes` alias
- `docs/HOW_IT_WORKS.md` — deep-dive into macOS thermal architecture
- `docs/TROUBLESHOOTING.md` — common failure scenarios and fixes
- `.github/workflows/shellcheck.yml` — automated shell linting on every push

### Changed
- README: replaced `YOUR_USERNAME/YOUR_REPO` placeholders with actual repo URLs
- README: added Quickstart section with real one-liner

---

## [1.0.0] — 2026-03-31

### Added
- Initial release
- Interactive menu with 6 modes: Chill, Programming, Beast, Marathon, Monitor, Restore
- CLI mode: `./thermal_manager.sh <mode>` for non-interactive / alias use
- Sudo keepalive background loop with `trap`-based cleanup
- Full `pmset` power management per mode
- Spotlight indexing control via `mdutil`
- Time Machine control via `tmutil`
- LaunchAgent unloading via `launchctl`
- UI compositor reduction via `defaults write`
- Live thermal monitoring via `powermetrics`
- Dependency check on startup
- `README.md` with full trust audit documenting every system call
