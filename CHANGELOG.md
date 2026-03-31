## [2.1.0] — 2026-03-31

### Added
- **`--dry-run` / `-n` flag**: Preview all system changes (pmset, launchctl, kill, 
  defaults, sysctl) without executing them. Intercepted via `xcmd` wrapper.
- **`--status` flag**: Displays a complete configuration snapshot (GPU, PowerNap, 
  Standby, Sleep, SMS, UI Motion) without requiring sudo.
- **`check_platform` guard**: Clean exit if run on non-macOS systems.
- **Grouped Redirects** in `install.sh`: Optimized shell config modification.
- **Sudo keepalive ceiling**: Background loop now has an 8-hour limit for security.

### Fixed
- **Menu recursion fix**: Refactored `main_menu()` from tail-recursion to a `while true` 
  loop. Prevents stack exhaustion in extended interactive sessions.
- **ShellCheck Audit (v2.0.1)**: Resolved multiple `SC2015` anti-patterns 
  (`A && B || C`) by switching to explicit `if/then/else` blocks.
- **Robustness**: Replaced `(( i++ ))` with `$(( i + 1 ))` for `set -e` compatibility.
- **Installer Quoting**: Fixed `modes` alias path quoting in `install.sh` to handle 
  space-y home directories.
- **CI/CD Security**: Pinned `ludeeus/action-shellcheck` to `@2.0.0` to avoid 
  unverified `@master` branch updates.

---

## [2.0.0] — 2026-03-31

### Added
- **ICEBERG mode** — absolute maximum cooling: WiFi off, Bluetooth off, all 7 AI daemons
  killed, Background QoS enforced on Electron/Dropbox/Chrome, memory purged,
  CPU efficiency hint applied via `machdep.xcpm.perf_hint`
- **AUDIT mode** — full thermal diagnostic: hardware profile, battery health + cycle count,
  SSD free space check, live 5-second sensor snapshot with danger zone highlighting,
  active throttle detection via `kernel_task` CPU%, AI daemon running scan, pmset settings
  comparison vs optimal values
- **AI daemon management** — 7 confirmed heat sources killed per mode:
  `mediaanalysisd`, `knowledge-agent`, `suggestd`, `parsecd`,
  `coreduetd`, `UsageTrackingAgent`, `routined`
- **`taskpolicy` QoS enforcement** — pushes Electron, Chrome Helper, Dropbox, Slack,
  backupd, CrashReporter to Background QoS tier (kernel gives minimal CPU time slices)
- **`renice 15`** — deprioritizes any AI daemon that respawns after kill
- **`purge` memory flush** — clears inactive pages, reports MB freed, reduces swap I/O heat
- **Radio control** — WiFi disable/enable via `networksetup`; Bluetooth via `blueutil`
  (optional, gracefully skipped if not installed)
- **GPU verification retry loop** — 3-retry verification confirms GPU switch actually applied
- **`launchctl kill` via user domain** — prevents immediate respawn of user LaunchAgents
  before falling back to direct `sudo kill`
- **AUDIT `_audit_row` helper** — coloured comparison of current vs optimal pmset values
- **Siri + Game Center reload** in Restore mode
- **WiFi re-enable** in Restore mode
- **`MACOS_VERSION` global** — version-aware tmutil handling (macOS 12+ has different API)
- **`KILLED_DAEMONS[]` tracking** — summary shown in Restore of what was killed
- **Input sanitizer** in main menu (regex strips non-0-8 chars)
- **Tighter sudo refresh** (30s instead of 50s) + `sudo -k` on exit via `trap`

### Changed
- Complete rewrite — all modes updated to use new helper functions
- `show_current_state()` now shows WiFi state + kernel_task CPU with throttle warning
- Monitor mode adds Power and System Average to grep filter
- Help text updated with all new modes and features
- Header updated to reflect v2.0.0 and remove Antigravity attribution

### Fixed
- `(( killed++ ))` inside `&&` conditional tripped `set -euo pipefail`
  when counter was 0. Replaced with `if/else` + `$(( killed + 1 ))`.

---

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
