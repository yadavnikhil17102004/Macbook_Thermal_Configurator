# How It Works — macOS Thermal Architecture Deep Dive

This document explains the *why* behind every decision in `thermal_manager.sh`.
Understanding the underlying system makes you a better operator of this tool.

---

## The Problem: kernel_task Is Not a Bug

When your Mac gets hot, you'll see `kernel_task` consuming 200–400% CPU in Activity Monitor.
Your first instinct is to kill it. You can't — and you shouldn't.

`kernel_task` is macOS's **intentional thermal throttle mechanism**. It works by monopolizing CPU time slices so your actual workload gets fewer cycles, forcing lower sustained clock speeds, and therefore lower heat output. It's not broken — it's working exactly as designed.

The root cause is always upstream: **a thermal sensor crossed a threshold**.

---

## macOS Thermal Subsystem Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Your Workload                         │
│         (Safari, Xcode, ffmpeg, whatever)                │
└────────────────────┬────────────────────────────────────┘
                     │ CPU cycles
                     ▼
┌─────────────────────────────────────────────────────────┐
│                  macOS Scheduler                         │
│         distributes CPU time between processes           │
└────────────────────┬────────────────────────────────────┘
                     │ reads thermal state
                     ▼
┌─────────────────────────────────────────────────────────┐
│              SMC (System Management Controller)          │
│  reads sensors → compares to thresholds → signals OS    │
│                                                          │
│  Sensors on A1990:                                       │
│   • CPU die temp (TC0P, TC0D)                           │
│   • GPU die temp  (TGDD, TG0D)                          │
│   • CPU proximity (TC0E, TC0F)                          │
│   • Thunderbolt left controller (TTLD)                   │
│   • Palm rest / chassis temps                            │
└────────────────────┬────────────────────────────────────┘
                     │ threshold exceeded
                     ▼
┌─────────────────────────────────────────────────────────┐
│              thermald (thermal daemon)                   │
│  interprets SMC signals, applies throttle policy         │
│  instructs kernel_task to consume CPU cycles             │
└─────────────────────────────────────────────────────────┘
```

**The key insight**: `thermald` reacts to *sensor readings*, not to actual junction temperatures.
On aging hardware with degraded thermal paste, sensor readings are inflated — the paste no longer efficiently transfers heat from the die to the heat spreader to the sensor. So `thermald` throttles earlier than necessary.

This script can't fix the physics, but it can **reduce the heat input** so sensors trigger less often.

---

## Why Each Setting Matters Thermally

### `gpuswitch 0` — Force Integrated GPU

The A1990 has two GPUs:
- **Intel UHD 630** (iGPU) — integrated on the CPU die, draws ~5–15W
- **AMD Radeon Pro 555X** (dGPU) — discrete chip with its own die, draws ~20–45W under load

macOS uses `gpuswitch 2` (Auto) by default, which activates the dGPU whenever:
- An external display is connected
- A Metal/OpenCL app requests GPU acceleration
- Chrome, Electron apps, or games run

The dGPU adds 10–20°C to overall chassis temperature under sustained use because:
1. It has its own thermal dissipation budget competing with the CPU's
2. On the A1990, the GPU die is physically close to the CPU die on the board
3. The single heat pipe system serves both — GPU heat raises CPU sensor readings

**What we set:** `sudo pmset -a gpuswitch 0` forces iGPU only, eliminating the dGPU's heat contribution entirely.

---

### `powernap 0` — Stop Background Wake Activity

PowerNap allows the Mac to wake from sleep periodically to:
- Check email (Mail app)
- Sync iCloud Drive
- Fetch App Store updates
- Run Time Machine backups
- Index Spotlight changes

Each wakeup spins up the CPU, NVMe, and network interfaces — generating heat bursts even when you think the machine is idle or sleeping.

**What we set:** `sudo pmset -a powernap 0` — disables all of this.

---

### `hibernatemode 0` — Eliminate Hibernate Write I/O Spikes

macOS has three hibernate modes:

| Mode | Behavior | I/O impact |
|---|---|---|
| `0` | RAM stays powered during sleep (no disk write) | None |
| `3` | RAM powered + RAM image written to disk (safe sleep) | NVMe write on every sleep |
| `25` | RAM off, full hibernation to disk | Full RAM dump on every sleep |

Default on MacBooks is `3` (safe sleep). Every time your Mac sleeps, it dumps your entire RAM contents (~8–32 GB) to `/var/vm/sleepimage` on the NVMe. This causes an I/O and CPU spike that generates heat just as the machine is trying to cool down.

**What we set:** `hibernatemode 0` — removes the disk write. If power is lost during sleep, you lose unsaved work (just like a normal suspend). Acceptable trade-off for reduced thermal events.

---

### `standby 0` — Disable Deep Sleep Transition

After staying in sleep for a while (default: ~3–24 hours), macOS transitions from sleep to "standby," which:
1. Cuts power to RAM (requires hibernate image for wake)
2. Writes a RAM image to disk even in `hibernatemode 0` (overrides it)
3. Causes another NVMe I/O spike

**What we set:** `standby 0` — prevents this transition. Machine stays in normal sleep indefinitely.

---

### `sms 0` — Sudden Motion Sensor

Originally designed for spinning hard drives: if the accelerometer detected a drop, SMS would park the read heads to prevent physical damage.

**On SSDs, this is irrelevant.** The A1990 has an NVMe SSD — no moving parts. But SMS still fires its interrupt handler and wakes the CPU briefly on movement detection events.

**What we set:** `sms 0` — disables it. No effect on SSDs. Do NOT disable if you have a spinning HDD.

---

### `mdutil -a -i off` — Pause Spotlight Indexing

Spotlight's `mds` (metadata server) and `mds_stores` processes run continuously to maintain a search index across all volumes. After macOS updates, app installs, or `git` operations, they go into overdrive.

This causes:
- Sustained NVMe read/write cycles
- CPU wakeups for every file system event
- Periods of 10–30% CPU usage by `mds` alone

**What we set:** `mdutil -a -i off` — stops indexing. Existing index still works for search. The index will catch up when re-enabled.

---

### `tmutil disable` — Stop Time Machine

Time Machine runs backup jobs on a roughly hourly schedule. Each backup:
- Reads changed files (disk I/O)
- Computes checksums (CPU)
- Writes to backup volume (more I/O)
- Triggers Spotlight re-indexing of changed files (compound effect)

During sustained workloads or video watching, Time Machine backups arriving at the wrong moment cause temperature spikes that trigger `kernel_task`.

---

### `launchctl unload` — Kill Idle Background Agents

`com.apple.gamed` — Game Center daemon. Polls for game achievements, leaderboard updates, and multiplayer state. Wakes up on a timer even if you never use Game Center. Contributes to background CPU baseline.

`com.apple.Siri.agent` — Siri's "always ready" background daemon. Maintains a processing pipeline for voice commands. Contributes to both CPU and microphone hardware wakeups.

Neither of these is essential during sustained workloads.

---

### `defaults write reduceMotion / reduceTransparency`

The macOS window compositor (WindowServer) runs on the GPU. Two of its most expensive operations:

- **Motion animations**: Every window open, close, minimize, expose — GPU renders interpolated frames at 60/120fps. Forces GPU activity even when applications themselves are idle.
- **Transparency/blur**: The menu bar, Dock, notification center, and dozens of UI surfaces use a real-time Gaussian blur shader running continuously on the GPU.

Disabling these reduces the compositor's GPU demand, which:
1. Directly reduces GPU power draw (→ lower GPU temp)
2. On Auto GPU mode, may prevent dGPU from activating just for compositor work

---

## The Thunderbolt Left Port Problem (A1990 Specific)

The A1990 has 4 Thunderbolt 3 / USB-C ports:

```
┌─ MacBook Pro A1990 ──────────────────────────────────────┐
│                                                           │
│  LEFT SIDE              │              RIGHT SIDE         │
│  ┌──┐ ┌──┐             │             ┌──┐ ┌──┐           │
│  │TB│ │TB│  ← HOT      │       COOL →│TB│ │TB│           │
│  └──┘ └──┘             │             └──┘ └──┘           │
│                                                           │
│  Left Thunderbolt controller routes through CPU die       │
│  Right Thunderbolt controller has separate thermal path   │
└───────────────────────────────────────────────────────────┘
```

The left Thunderbolt controller sits in the CPU's thermal zone. When you connect a charger, display, or hub to the left side:
1. The Thunderbolt controller draws power and generates heat
2. This heat is in the same zone as the CPU sensors
3. The SMC reads elevated temperatures even if CPU load is minimal
4. `thermald` triggers `kernel_task` throttling

**The fix**: Always charge from the **right-rear** port. This is free and immediate.

---

## What This Script Cannot Do

- **Override SMC firmware limits** — Apple's SMC has hard-coded temperature ceilings. No software can bypass them without a kernel extension (kext) that modern macOS (SIP-enabled) won't load.
- **Disable Turbo Boost natively** — Turbo Boost is controlled via CPU MSR (Model Specific Register) 0x1A0. Writing to MSRs requires a kernel extension. Use [Turbo Boost Switcher](https://www.rugarciap.com/turbo-boost-switcher-for-os-x/) which ships its own signed kext.
- **Fix degraded thermal paste** — If your CPU proximity sensor reads 75°C at idle, no software optimization will fully compensate. The paste-to-heatspreader interface is degraded after 5+ years. A repaste ($30–50 service) will drop idle temps by 10–15°C.
- **Control fan RPM directly** — macOS doesn't expose fan RPM control through `pmset`. Use [Macs Fan Control](https://crystalidea.com/macs-fan-control) which writes directly to SMC fan keys (`F0Mn`, `F1Mn`).

---

## Reading `powermetrics` Output

```
sudo powermetrics --samplers smc,cpu_power,gpu_power -i 1000
```

Key fields to watch:

| Field | What it means | Danger zone |
|---|---|---|
| `CPU die temperature` | CPU junction temperature | > 90°C sustained |
| `GPU die temperature` | AMD 555X junction temp | > 95°C |
| `CPU Proximity` | Board temp near CPU | > 75°C |
| `Fan 0 speed` | Left fan RPM | < 2000 RPM under load |
| `Fan 1 speed` | Right fan RPM | < 2000 RPM under load |
| `CPU Power` | Package power draw in Watts | > 45W sustained |
| `GPU Power` | dGPU power draw | > 0W when you expect iGPU only |

If `GPU Power` shows > 0W after setting `gpuswitch 0`, there's an app holding a GPU context open. Quit all GPU-accelerated apps and reconnect.

---

*Back to [README](../README.md)*
