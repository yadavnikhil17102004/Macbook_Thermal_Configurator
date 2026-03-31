# 🌡️ Mac Thermal Manager

> **Software-only thermal & performance mode switcher for MacBook Pro (Intel — A1990 and similar)**
> No hardware mods. No 3rd-party daemons. Pure macOS internals.

![ShellCheck](https://github.com/yadavnikhil17102004/Macbook_Thermal_Configurator/actions/workflows/shellcheck.yml/badge.svg)
![macOS](https://img.shields.io/badge/macOS-11%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-1.1.0-orange)

---

## Why This Exists

MacBook Pro models with the Intel i7 + AMD Radeon dGPU combo (especially the **A1990 — 2018 15"**) suffer from aggressive thermal throttling that kicks in well before temperatures are actually critical. macOS's `kernel_task` intentionally consumes CPU cycles to force clock-speed reductions when thermal sensors are triggered — even during light tasks like video playback.

This script gives you **one command** to reconfigure your Mac's software thermal behavior for whatever you're about to do.

→ **Deep dive**: [How it works — macOS thermal architecture](docs/HOW_IT_WORKS.md)

---

## Compatibility

| Model | Status |
|---|---|
| MacBook Pro A1990 (2018 15") — i7/i9 + AMD 555X/560X | ✅ Designed for this |
| MacBook Pro 2019–2020 16" Intel | ✅ Compatible |
| MacBook Pro 2017–2019 13"/15" Intel | ✅ Compatible |
| MacBook Air Intel (2018–2020) | ⚠️ Mostly compatible (single GPU, some flags differ) |
| Apple Silicon (M1/M2/M3/M4) | ❌ Not applicable — different thermal architecture |

---

## Quickstart

### ⚡ Option A — Run directly from GitHub (zero install, zero download)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yadavnikhil17102004/Macbook_Thermal_Configurator/main/thermal_manager.sh)
```

The script will prompt for your password (sudo) and show the interactive menu. Nothing is written to disk.

**Apply a mode directly without the menu:**
```bash
# Chill mode — video watching / light work
bash <(curl -fsSL https://raw.githubusercontent.com/yadavnikhil17102004/Macbook_Thermal_Configurator/main/thermal_manager.sh) chill

# Beast mode — full performance
bash <(curl -fsSL https://raw.githubusercontent.com/yadavnikhil17102004/Macbook_Thermal_Configurator/main/thermal_manager.sh) beast

# Restore all settings to macOS defaults
bash <(curl -fsSL https://raw.githubusercontent.com/yadavnikhil17102004/Macbook_Thermal_Configurator/main/thermal_manager.sh) restore
```

---

### 📦 Option B — Install permanently (adds `modes` alias to your shell)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yadavnikhil17102004/Macbook_Thermal_Configurator/main/install.sh)
```

Then reload your shell:
```bash
source ~/.zshrc
```

Now use it from anywhere:
```bash
modes           # interactive menu
modes chill     # apply Chill mode
modes beast     # full performance
modes restore   # undo everything
modes --help    # full usage guide
```

---

### 🗂 Option C — Clone and run locally

```bash
git clone https://github.com/yadavnikhil17102004/Macbook_Thermal_Configurator.git
cd Macbook_Thermal_Configurator
chmod +x thermal_manager.sh
sudo ./thermal_manager.sh
```

---

## Modes

| Mode | Symbol | Use Case | Key Actions |
|---|---|---|---|
| **Chill** | ❄️ | Video, browsing, light work | Forces iGPU, kills PowerNap, pauses Spotlight, reduces UI compositor |
| **Programming** | 💻 | Editors, compilers, terminals | Auto GPU, Spotlight on, sleep suppressed, motion reduced |
| **Beast** | ⚡ | Exports, ML, Xcode, large builds | Auto GPU, sleep=0, Spotlight + TimeMachine off |
| **Marathon** | 🕰️ | Overnight renders, long encodes | iGPU only, sleep=0, Siri + GameCenter killed, everything quiet |
| **Monitor** | 📊 | Any time | Live `powermetrics` stream → CPU temp + GPU power + fan speeds |
| **Restore** | 🔄 | Done with session | Resets all settings to macOS defaults |

---

## Requirements

- macOS 11 Big Sur or later *(tested on Ventura 13 and Sonoma 14)*
- `sudo` access — you'll be prompted once, no password re-prompts during the session
- **Zero external dependencies** — uses only built-in macOS tools:
  `pmset` · `launchctl` · `defaults` · `mdutil` · `tmutil` · `powermetrics`

**Optional tools (enhance but not required):**
- [Macs Fan Control](https://crystalidea.com/macs-fan-control) — manual fan curve overrides (free)
- [Turbo Boost Switcher](https://www.rugarciap.com/turbo-boost-switcher-for-os-x/) — biggest single thermal lever (~15–20°C drop)
- [Stats](https://github.com/exelban/stats) — free, open-source menubar thermal monitor

---

## What Does the Script Actually Do? (Full Trust Audit)

This section documents **every system call** the script makes, what it modifies, and how to reverse it. Nothing is hidden.

### Global (all modes)

| Action | Command | Reversible? |
|---|---|---|
| Prompt for sudo | `sudo -v` | N/A — just authenticates |
| Keep sudo alive | Background loop: `sudo -n true` every 50s | Killed automatically on script exit via `trap` |
| Check required binaries | `command -v pmset launchctl defaults system_profiler` | Read-only, no changes |

---

### `pmset` settings explained

`pmset` is Apple's built-in power management tool. All changes made with `pmset -a` write to:
`/Library/Preferences/SystemConfiguration/com.apple.PowerManagement.plist`

| Key | What it controls | Script sets it to | Default |
|---|---|---|---|
| `gpuswitch` | GPU selection mode | `0` (iGPU only) or `2` (auto) | `2` |
| `powernap` | Background activity during sleep (email, iCloud sync) | `0` = off | `1` |
| `standby` | Hibernate after extended sleep | `0` = off | `1` |
| `hibernatemode` | Hibernate method (`0`=RAM only, `3`=safe sleep) | `0` | `3` |
| `sms` | Sudden Motion Sensor — parks HDD heads on drop | `0` = off | `1` |
| `sleep` | System sleep timer | `0` = never | `1` |

> ⚠️ **`sms 0`** — Safe to disable on SSDs. Do NOT disable on HDD-based Macs.
> **Restore** mode resets all of these back to macOS defaults.

---

### `mdutil -a -i off/on` — Spotlight Indexing

- `off` → Spotlight stops indexing. Existing search results still work.
- `on` → Re-enables indexing. Changed files re-indexed on background.
- **Why:** Spotlight's `mds` process causes continuous disk I/O + CPU spikes, especially after macOS updates. Disabling it removes a significant background heat source.

---

### `tmutil disable` / `disablelocal` — Time Machine

- `tmutil disable` → Turns off Time Machine for the session.
- `tmutil disablelocal` → Stops local snapshots (macOS 11 and earlier only).
- **Re-enable:** `sudo tmutil enable` or System Settings → Time Machine.

---

### `launchctl unload -w` — Background Agents

Stops and disables a background system agent until manually re-enabled.

| Agent | What it does | Affected modes |
|---|---|---|
| `com.apple.gamed.plist` | Game Center background sync | Chill, Marathon |
| `com.apple.Siri.agent.plist` | Siri background readiness | Marathon |

**Re-enable:**
```bash
launchctl load -w /System/Library/LaunchAgents/com.apple.gamed.plist
launchctl load -w /System/Library/LaunchAgents/com.apple.Siri.agent.plist
```

> ⚠️ On macOS 12+ with SIP enabled, some agents may refuse to unload. The script warns and continues — it never hard-fails on this.

---

### `defaults write com.apple.universalaccess` — UI Compositor

Writes to macOS Accessibility preferences. No SIP bypass required.

| Key | Effect | Thermal benefit |
|---|---|---|
| `reduceMotion true` | Disables window animations, parallax | Fewer GPU composite passes per frame |
| `reduceTransparency true` | Replaces blur/glass UI with flat color | Eliminates GPU blur shader in menu bar + Finder |

**Re-enable:** Restore mode sets both to `false`. Or: System Settings → Accessibility → Display.

---

### `powermetrics` (Monitor mode only)

Read-only. Samples SMC thermal sensors, CPU + GPU power draw. Writes nothing to disk.
Requires sudo to access hardware registers.

---

### What the script does NOT do

- ❌ Does not touch network settings
- ❌ Does not install any software or packages
- ❌ Does not write to `/etc`, `/usr`, or any system binary path
- ❌ Does not create background daemons or LaunchDaemons
- ❌ Does not send any data anywhere (fully offline)
- ❌ Does not modify SIP, kernels, or kexts
- ❌ Does not survive reboot (all changes are session-scoped unless designed to persist)

---

## The "Right Port" Rule (Free, Instant Fix)

The A1990 has 4 Thunderbolt 3 ports. The **two left ports** route through the CPU die thermal path. Charging or connecting peripherals on the left side measurably increases CPU die temperatures.

**Always charge from the right-rear USB-C port.** Zero cost, immediate effect.

---

## Priority Ranking (Biggest Thermal Impact First)

1. 🔌 **Right-side charging port** — immediate, free
2. ⚡ **Disable Turbo Boost** ([Turbo Boost Switcher](https://www.rugarciap.com/turbo-boost-switcher-for-os-x/)) — ~15–20°C drop during light tasks
3. 🖥️ **Force iGPU** (`gpuswitch 0`) — eliminates ~10–15°C from AMD 555X
4. 💨 **Raise fan minimum RPM** ([Macs Fan Control](https://crystalidea.com/macs-fan-control)) — 2500 RPM min vs default 1200 RPM
5. 🔦 **Kill Spotlight + PowerNap** — removes constant background I/O heat
6. 🌐 **Use Safari for video** — hardware decode by default, unlike Chrome/Electron

---

## Monitoring Your Thermals

```bash
# Quick one-liner — CPU die temp + fan + throttle every 2s
sudo powermetrics --samplers smc,cpu_power,gpu_power -i 2000 | grep -E "CPU die|GPU Power|Fan|Throttl"

# All SMC sensor values (single snapshot)
sudo powermetrics --samplers smc -i 1000 -n 1
```

Or use [Stats](https://github.com/exelban/stats) for a persistent menubar readout.

---

## Documentation

| Doc | Description |
|---|---|
| [HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md) | Deep dive: macOS thermal subsystem, SMC, thermald, why each setting matters |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common failure scenarios, SIP issues, Sonoma/Ventura differences, fan not spinning |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## Contributing

PRs welcome. Especially interested in:
- Compatibility reports from other Intel MacBook models
- macOS version-specific `launchctl` differences
- Fan curve profiles for smcFanControl CLI integration
- Testing on Sequoia (15)

---

## License

MIT — do whatever you want with it.

---

## Author

Built by [yadavnikhil17102004](https://github.com/yadavnikhil17102004).
Hardware: MacBook Pro A1990 (i7-8850H / AMD Radeon 555X / Intel UHD 630).
