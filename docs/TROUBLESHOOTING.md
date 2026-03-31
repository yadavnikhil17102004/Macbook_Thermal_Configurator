# Troubleshooting

Common failure scenarios, what causes them, and exactly how to fix them.

---

## Script Issues

### `zsh: command not found: thermal_manager.sh`

You're trying to run it without `./`. The shell doesn't look in the current directory by default.

```bash
# Wrong
thermal_manager.sh

# Correct
./thermal_manager.sh
# or
sudo ./thermal_manager.sh
```

---

### `Permission denied`

The script isn't executable yet.

```bash
chmod +x thermal_manager.sh
```

---

### `sudo: no tty present and no askpass program specified`

You're running the script in a context where sudo can't prompt for a password (e.g., piped from curl without a TTY).

**Fix**: Run it in an interactive terminal, not inside a pipe:

```bash
# Download first, then run
curl -fsSL https://raw.githubusercontent.com/yadavnikhil17102004/Macbook_Thermal_Configurator/main/thermal_manager.sh -o /tmp/thermal_manager.sh
chmod +x /tmp/thermal_manager.sh
sudo /tmp/thermal_manager.sh
```

---

### Script exits immediately with no output

`set -euo pipefail` is active — the script exits on the first error. Run with `bash -x` to trace:

```bash
bash -x ./thermal_manager.sh 2>&1 | head -50
```

The failing line will show with a `+` prefix. File a bug report with that output.

---

## `pmset` Issues

### `gpuswitch` change has no effect — dGPU still active

Some apps hold a persistent GPU context that prevents the switch.

```bash
# See which process holds a dGPU connection
sudo powermetrics --samplers gpu_power -i 500 -n 3 | grep -E "GPU|process"

# Check GPU usage per app
sudo powermetrics --samplers tasks -i 2000 -n 1 | grep -i "gpu"
```

**Fix**: Quit Chrome, Electron-based apps (VS Code, Slack, Discord), and external display connections. Then re-run the mode.

---

### `pmset` changes don't persist after reboot

`pmset -a` does persist across reboots in most cases. However, some macOS updates silently reset power management settings.

**Verify your settings survived:**
```bash
pmset -g | grep -E "gpuswitch|powernap|standby|hibernatemode"
```

**If they reset:** Re-run `./thermal_manager.sh <mode>`. For truly persistent settings, add the mode to a Login Item or a LaunchAgent. Open an issue if you want a guide on this.

---

### `pmset: unrecognized setting 'sms'`

Occurs on some macOS 13+ configurations. `sms` may not be supported on all hardware profiles.

The script uses `|| warn` for these — it will print a warning and continue. This is non-critical.

---

## `launchctl` Issues

### `launchctl unload: Could not find specified service`

The agent is either already unloaded or doesn't exist on your macOS version.

This is handled gracefully — the script warns and continues. If you see this, the agent was likely already not running.

---

### `launchctl unload: Operation not permitted`

SIP (System Integrity Protection) is blocking the unload. This happens on macOS 12+ for some protected agents.

```bash
# Check SIP status
csrutil status
```

**You don't need to disable SIP.** The affected agents (Game Center, Siri) are non-critical. The script skips them gracefully. The thermal benefit from other settings is sufficient.

---

### Siri/Game Center came back after restart

`launchctl unload -w` is persistent but some agents are re-enabled by system updates or by System Settings.

**Re-run the mode** after a macOS update if you notice agents returning:
```bash
sudo ./thermal_manager.sh marathon
```

---

## `mdutil` / Spotlight Issues

### `mdutil: could not change indexing on: /`

This usually means Spotlight is currently mid-index and locked. Wait a few minutes and retry, or force it:

```bash
sudo killall mds 2>/dev/null; sudo mdutil -a -i off
```

---

### Spotlight search stopped working entirely

If you disabled indexing and want it back immediately:

```bash
sudo mdutil -a -i on
```

The index will rebuild in the background over 10–30 minutes (depending on disk size). CPU and temp will spike during this — normal behavior, it will settle.

---

### Spotlight won't re-enable

```bash
# Nuclear option — rebuild the entire index from scratch
sudo mdutil -a -i off
sudo rm -rf /.Spotlight-V100
sudo mdutil -a -i on
```

---

## Thermal Issues (Still Throttling After Running Script)

### Temps still high after Chill mode

**Check which process is causing it:**
```bash
sudo powermetrics --samplers tasks -i 5000 -n 1 | head -40
```

Common culprits:
- `mds_stores` — Spotlight still indexing. Wait for it to finish or kill it: `sudo killall mds_stores`
- `backupd` — Time Machine still running. `sudo tmutil disable`
- `kernel_task` — Still throttling. See below.
- `WindowServer` — GPU compositor still heavy. Ensure Reduce Transparency/Motion are set in System Settings → Accessibility → Display.

---

### kernel_task won't calm down even after all optimizations

This is the "phantom throttle" scenario — the SMC is reacting to a sensor that's running hot for physical reasons (degraded thermal paste, dust-blocked vents).

**Diagnostic:**
```bash
sudo powermetrics --samplers smc -i 1000 -n 3 | grep -E "CPU die|Proximity|Throttl"
```

If `CPU die` is above 80°C at idle with no load:
1. Blow compressed air through the vents (left and right sides)
2. Ensure the bottom of the laptop is not resting on soft surfaces (bed, couch)
3. If it persists at 80°C+ idle — the thermal paste needs replacement. Software cannot fix this.

**Temporary workaround**: SMC reset can clear phantom sensor states:
- Shut down completely
- Hold Left Shift + Control + Option + Power for 10 seconds
- Release all keys simultaneously
- Power on normally

---

### Fan not spinning up under load

If fans stay at minimum RPM while the CPU is hot:

```bash
# Check fan speed
sudo powermetrics --samplers smc -i 1000 -n 1 | grep Fan
```

If fans show < 1500 RPM at CPU temps > 80°C, the SMC fan curve may be miscalibrated. An SMC reset usually fixes this. If not, use [Macs Fan Control](https://crystalidea.com/macs-fan-control) to set a manual curve.

---

## macOS Version Differences

| macOS Version | Known Issues |
|---|---|
| Big Sur (11) | `tmutil disablelocal` available and effective |
| Monterey (12) | `tmutil disablelocal` removed. Some `launchctl` unloads blocked by SIP. |
| Ventura (13) | Same as Monterey. `pmset gpuswitch` confirmed working. |
| Sonoma (14) | Same as Ventura. GPU switch can take longer to apply (~5s). |
| Sequoia (15) | Testing in progress. File an issue if you hit a regression. |

---

## Filing a Bug Report

If something breaks that isn't covered here, run this diagnostic and include the output:

```bash
bash -x ./thermal_manager.sh restore 2>&1 | tee /tmp/thermal_debug.txt
cat /tmp/thermal_debug.txt
```

Also include:
```bash
sw_vers                                          # macOS version
system_profiler SPHardwareDataType | grep -E "Model|SMC|Chip"  # hardware info
pmset -g                                         # current power settings
csrutil status                                   # SIP state
```

Open an issue at: https://github.com/yadavnikhil17102004/Macbook_Thermal_Configurator/issues

---

*Back to [README](../README.md)*
