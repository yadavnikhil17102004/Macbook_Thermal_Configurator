# Changelog

All notable changes to this project will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [1.2.0] — 2026-03-31

### Security
- **Pin GitHub Actions**: `ludeeus/action-shellcheck@master` → `@2.0.0` to prevent
  supply-chain attacks from a compromised `master` branch.
- **Fix stack exhaustion**: `main_menu()` was implemented with unbounded tail recursion
  (each menu return called `main_menu` again). Replaced with a `while true` loop so
  the call stack stays constant regardless of how many menu cycles the user goes through.
- **Add macOS platform guard** (`check_macos`): script now exits cleanly with a clear
  error if run on a non-Darwin OS, preventing confusing failures on Linux/WSL.
- **Bound sudo keepalive loop**: the background `sudo -n true` keepalive loop previously
  ran indefinitely until the EXIT trap fired. It now has an 8-hour ceiling so it cannot
  persist beyond any reasonable session.

### Added
- `xcmd()` helper: thin wrapper that either executes a command normally or prints it
  as `[dry-run] <cmd>` when `DRY_RUN=true`. All state-changing calls in every mode
  function now route through `xcmd`.
- `--dry-run` / `-n` flag: run any mode (or the interactive menu) without making any
  system changes. Prints every command that *would* execute. Sudo is not required.
  Examples:
  - `./thermal_manager.sh --dry-run chill`
  - `sudo ./thermal_manager.sh -n beast`
  - `./thermal_manager.sh --dry-run` (interactive dry-run menu)
- `--status` flag: prints a detailed snapshot of current thermal configuration
  (GPU switch, powernap, standby, hibernatemode, sleep, SMS, reduceMotion,
  reduceTransparency) without requiring sudo.
  Example: `./thermal_manager.sh --status`
- Interactive menu shows a visible `⚠ DRY-RUN mode` banner when launched with
  `--dry-run`.

### Changed
- Updated `show_help` to document `--status` and `--dry-run` flags with examples.
- VERSION bumped from 1.1.0 → 1.2.0.

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
