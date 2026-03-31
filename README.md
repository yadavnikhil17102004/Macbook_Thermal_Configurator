# 🌡️ Mac Thermal Manager

> **Software-only thermal & performance mode switcher for MacBook Pro (A1990 and similar Intel models)**
> No hardware mods. No 3rd-party daemons. Pure macOS internals.

---

## Why This Exists

MacBook Pro models with the Intel i7 + AMD Radeon dGPU combo (especially the A1990 — 2018 15") suffer from aggressive thermal throttling that kicks in well before temperatures are actually critical. macOS's `kernel_task` intentionally consumes CPU cycles to force clock-speed reductions when thermal sensors are triggered — even during light tasks like video playback.

This script gives you **one command** to reconfigure your Mac's software thermal behavior for whatever you're about to do.

---

## Compatibility

| Model | Status |
|---|---|
| MacBook Pro A1990 (2018 15") — i7/i9 + AMD 555X/560X | ✅ Designed for this |
| MacBook Pro 2019–2020 16" Intel | ✅ Compatible |
| MacBook Pro 2017–2019 13"/15" Intel | ✅ Compatible |
| MacBook Air Intel (2018–2020) | ⚠️  Mostly compatible (single GPU, some flags differ) |
| Apple Silicon (M1/M2/M3/M4) | ❌ Not applicable — different thermal architecture |

---

## Quickstart

### Option A — Run directly from GitHub (no download needed)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/thermal_manager.sh)
```

> Replace `YOUR_USERNAME/YOUR_REPO` with your GitHub repo path.
> The script will prompt for your password (sudo) and show the interactive menu.

**Pass a mode directly (non-interactive):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/thermal_manager.sh) chill
```

### Option B — Clone and run locally

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
chmod +x thermal_manager.sh
sudo ./thermal_manager.sh
```

### Option C — Permanent alias (recommended)

Add this to your `~/.zshrc`:

```bash
alias modes='sudo /path/to/thermal_manager.sh'
```

Then from any terminal:
```bash
modes          # interactive menu
modes chill    # go straight to chill mode
modes beast    # full performance
modes restore  # reset everything
```

---

## Modes

| Mode | Symbol | Use Case | Key Actions |
|---|---|---|---|
| **Chill** | ❄️ | Video, browsing, light work | Forces iGPU, kills PowerNap, pauses Spotlight, reduces UI compositor |
| **Programming** | 💻 | Editors, compilers, terminals | Auto GPU, Spotlight on, sleep suppressed, Motion reduced |
| **Beast** | ⚡ | Exports, ML, Xcode, compiles | Max headroom, sleep=0, Spotlight/TimeMachine off, full compositor reduction |
| **Marathon** | 🕰️ | Overnight renders, long encodes | iGPU only, sleep=0, Siri/GameCenter killed, everything quiet |
| **Monitor** | 📊 | Any time | Live `powermetrics` stream → CPU temp + GPU power + fan speeds |
| **Restore** | 🔄 | Done with session | Resets all settings to macOS defaults |

---

## Requirements

- macOS 11 Big Sur or later (tested on Ventura and Sonoma)
- `sudo` access (you'll be prompted)
- Standard macOS tools only: `pmset`, `launchctl`, `defaults`, `mdutil`, `tmutil`, `powermetrics` — all built in

**Optional (enhances but not required):**
- [Macs Fan Control](https://crystalidea.com/macs-fan-control) — manual fan curve overrides
- [Turbo Boost Switcher](https://www.rugarciap.com/turbo-boost-switcher-for-os-x/) — disabling turbo boost is the single highest-impact thermal change you can make

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

`pmset` is Apple's built-in power management tool. All changes made with `pmset -a` write to `/Library/Preferences/SystemConfiguration/com.apple.PowerManagement.plist`.

| Key | What it controls | Script sets it to | Default |
|---|---|---|---|
| `gpuswitch` | GPU selection mode | `0` (iGPU), `2` (auto) | `2` |
| `powernap` | Background activity while sleeping (email, iCloud, etc.) | `0` = off | `1` |
| `standby` | Whether to hibernate after extended sleep | `0` = off | `1` |
| `hibernatemode` | Hibernate method (`0`=sleep-only RAM, `3`=safe sleep) | `0` | `3` |
| `sms` | Sudden Motion Sensor (parks HDD heads on drop) | `0` = off | `1` |
| `sleep` | System sleep timer | `0` = never | `1` |

> ⚠️ **`sms 0`** — Safe to disable on SSDs. Do NOT disable if you have an HDD.
> **Restore** mode resets all of these back to macOS defaults.

---

### `mdutil -a -i off/on`

Controls Spotlight indexing across all volumes.

- `off` → Spotlight stops indexing. Search still works for already-indexed data.
- `on` → Re-enables indexing. Any files changed while off will be re-indexed.
- **Why it matters thermally:** Spotlight's `mds` process causes repeated disk I/O and CPU spikes, especially after macOS updates. Disabling it eliminates a significant background heat source.

---

### `tmutil disable` / `disablelocal`

- `tmutil disable` → Turns off Time Machine backups for the session.
- `tmutil disablelocal` → Stops local Time Machine snapshots (macOS 11 and earlier only; removed in macOS 12+).
- **Re-enable:** Run `sudo tmutil enable` or re-enable in System Preferences → Time Machine.

---

### `launchctl unload -w`

Stops and disables a background system agent until manually re-enabled.

| Agent | What it does | Affected modes |
|---|---|---|
| `com.apple.gamed.plist` | Game Center background sync, achievements, leaderboards | Chill, Marathon |
| `com.apple.Siri.agent.plist` | Siri background readiness daemon | Marathon |

**Re-enable either:**
```bash
launchctl load -w /System/Library/LaunchAgents/com.apple.gamed.plist
launchctl load -w /System/Library/LaunchAgents/com.apple.Siri.agent.plist
```

> ⚠️ On macOS 12+ with SIP enabled, some LaunchAgents may refuse to unload. The script handles this gracefully — it warns and continues rather than failing.

---

### `defaults write com.apple.universalaccess`

Writes to macOS Accessibility preferences. No SIP bypass required.

| Key | Effect | Thermal benefit |
|---|---|---|
| `reduceMotion true` | Disables window animations, parallax effects | Reduces GPU composite passes on every frame |
| `reduceTransparency true` | Replaces blur/frosted-glass UI with flat color | Eliminates GPU blur operations in the menu bar and Finder |

**Re-enable:** Restore mode sets both to `false`. Or: System Settings → Accessibility → Display.

---

### `powermetrics` (Monitor mode only)

Read-only. Samples SMC thermal sensors, CPU power draw, and GPU power draw. Writes nothing to disk. Requires sudo because it reads hardware registers.

```
sudo powermetrics --samplers smc,cpu_power,gpu_power -i 2000
```

- `-i 2000` = sample every 2 seconds
- Output is piped through `grep` to show only relevant lines (CPU die temp, GPU power, fan speed, throttle flags)

---

### What the script does NOT do

- ❌ Does not touch network settings
- ❌ Does not install any software
- ❌ Does not write to `/etc`, `/usr`, or any system binary path
- ❌ Does not create background daemons or LaunchDaemons
- ❌ Does not send any data anywhere
- ❌ Does not modify SIP, kernels, or kexts
- ❌ Does not survive reboot (all `pmset` changes reset on next boot unless they are persistent by design)

---

## The "Right Port" Rule (Hardware Note — Free Fix)

The A1990 has 4 Thunderbolt 3 ports. The **two left ports** route directly through the CPU die thermal path. Charging or connecting peripherals on the left side measurably increases CPU die temperatures.

**Always charge from the right-rear USB-C port.** This is the single most impactful change you can make without software.

---

## Priority Ranking (Biggest Thermal Impact First)

1. 🔌 **Right-side charging port** — immediate, free
2. ⚡ **Disable Turbo Boost** (via [Turbo Boost Switcher](https://www.rugarciap.com/turbo-boost-switcher-for-os-x/)) — ~15–20°C drop during light tasks
3. 🖥️ **Force iGPU** (`gpuswitch 0`) — eliminates ~10–15°C from AMD 555X
4. 💨 **Raise fan minimum RPM** (via Macs Fan Control) — 2500 RPM min vs default 1200 RPM
5. 🔦 **Kill Spotlight + PowerNap** — removes constant background I/O heat
6. 🌐 **Use Safari for video** — hardware decode by default, unlike Chrome

---

## Monitoring Your Thermals

```bash
# Quick one-liner — watch CPU die temp + fan + throttle every 2s
sudo powermetrics --samplers smc,cpu_power,gpu_power -i 2000 | grep -E "CPU die|GPU Power|Fan|Throttl"

# All SMC sensor values
sudo powermetrics --samplers smc -i 1000 -n 1
```

Or use [Stats](https://github.com/exelban/stats) (free, open-source) for a persistent menubar readout.

---

## Contributing

PRs welcome. Especially interested in:
- Compatibility reports from other Intel MacBook models
- macOS version-specific launchctl differences
- Fan curve profiles for smcFanControl CLI integration

---

## License

MIT — do whatever you want with it.

---

## Author

Built by [nikhilyadav](https://github.com/YOUR_USERNAME) with [Antigravity](https://antigravity.dev).  
Hardware: MacBook Pro A1990 (i7-8850H / AMD Radeon 555X / Intel UHD 630).
