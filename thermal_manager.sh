#!/usr/bin/env bash
# =============================================================================
#  thermal_manager.sh — MacBook Pro A1990 Advanced Thermal Controller
#  Repo   : https://github.com/yadavnikhil17102004/Macbook_Thermal_Configurator
#  Author : yadavnikhil17102004
#  HW     : Intel i7 / AMD Radeon 555X (A1990)
#  Req    : sudo — uses only built-in macOS tools + optional blueutil
# =============================================================================

VERSION="2.1.0"
DRY_RUN=false
set -euo pipefail

# ── Platform guard ────────────────────────────────────────────────────────────
check_platform() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "  \033[0;31m✗\033[0m This script requires macOS. Detected OS: $(uname -s)"
    exit 1
  fi
}

# ── Dry-run command wrapper ───────────────────────────────────────────────────
# Usage: xcmd sudo pmset -a gpuswitch 0
# In dry-run mode: prints the command instead of executing it.
xcmd() {
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${DIM}[dry-run]${RESET} $*"
  else
    "$@"
  fi
}

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'
MAGENTA='\033[0;35m'; RESET='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
info()  { echo -e "  ${CYAN}→${RESET} $*"; }
ok()    { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()   { echo -e "  ${RED}✗${RESET} $*"; }
step()  { echo -e "\n${BOLD}${BLUE}[$1]${RESET} $2"; }
sep()   { echo -e "${DIM}──────────────────────────────────────────────────────${RESET}"; }

# ── Global state ──────────────────────────────────────────────────────────────
SUDO_KEEPALIVE_PID=""
MACOS_VERSION=0          # Set by check_deps before any mode runs
WIFI_IF=""               # Set by detect_wifi_interface
KILLED_DAEMONS=()        # Tracks what we killed for the restore summary

# ── Sudo management ───────────────────────────────────────────────────────────
cleanup_sudo() {
  [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  sudo -k  # Revoke sudo timestamp on exit
}

require_sudo() {
  if [[ "$DRY_RUN" == true ]]; then
    info "Running in DRY-RUN mode. Sudo not required."
    return 0
  fi

  if ! sudo -n true 2>/dev/null; then
    echo -e "\n${YELLOW}Thermal controls require sudo.${RESET}"
    sudo -v || { err "Authentication failed."; exit 1; }
  fi

  # Sudo refresh loop with 8-hour ceiling (28800s)
  (
    for ((i=0; i<960; i++)); do
      sudo -v
      sleep 30
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
  trap cleanup_sudo EXIT INT TERM
}

# ── Dependency + environment setup ────────────────────────────────────────────
check_deps() {
  local missing=()
  for cmd in pmset launchctl defaults system_profiler sysctl mdutil tmutil renice taskpolicy; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 1
  fi

  # Set global macOS major version — used by version-aware functions
  MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)

  # Detect WiFi interface once
  WIFI_IF=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}' | head -1)

  # Optional dependency check
  command -v blueutil &>/dev/null || warn "blueutil not found — Bluetooth control disabled.  Install: brew install blueutil"
}

# ── System state snapshot ─────────────────────────────────────────────────────
show_current_state() {
  sep
  echo -e "${BOLD}  System Snapshot${RESET}"
  sep

  local gpu gpuswitch gpumode powernap standby kernel_cpu wifi_state
  gpu=$(system_profiler SPDisplaysDataType 2>/dev/null \
        | grep "Chipset Model" | head -1 | awk -F': ' '{print $2}' \
        || echo "Unknown")
  gpuswitch=$(pmset -g | grep gpuswitch | awk '{print $2}' || echo "?")
  case "$gpuswitch" in
    0) gpumode="iGPU only (dGPU OFF)" ;;
    1) gpumode="dGPU only" ;;
    2) gpumode="Auto (default)" ;;
    *) gpumode="Unknown" ;;
  esac
  powernap=$(pmset -g | grep powernap | awk '{print $2}' || echo "?")
  standby=$(pmset -g | grep -w "^[[:space:]]*standby " | awk '{print $2}' | head -1 || echo "?")
  kernel_cpu=$(ps aux 2>/dev/null | awk '/kernel_task/ && !/awk/ {print $3; exit}')
  wifi_state=$(networksetup -getairportpower "${WIFI_IF:-en0}" 2>/dev/null | awk '{print $NF}' || echo "?")

  echo -e "  Active GPU      : ${CYAN}${gpu}${RESET}"
  echo -e "  GPU Mode        : ${CYAN}${gpumode}${RESET}"
  echo -e "  Power Nap       : ${CYAN}${powernap}${RESET}"
  echo -e "  Standby         : ${CYAN}${standby}${RESET}"
  echo -e "  WiFi            : ${CYAN}${wifi_state}${RESET}"
  echo -e "  kernel_task CPU : ${CYAN}${kernel_cpu:-?}%${RESET}"
  local cpu_int=${kernel_cpu%.*}
  if [[ "${cpu_int:-0}" -gt 50 ]]; then
    warn "THROTTLING ACTIVE — kernel_task consuming ${kernel_cpu}% CPU."
  fi
  sep
}

# ── GPU control with verification + retry ────────────────────────────────────
set_gpu_mode() {
  local mode=$1   # 0 = iGPU only | 2 = Auto
  local label
  [[ $mode -eq 0 ]] && label="iGPU only" || label="Auto"

  if ! pmset -g | grep -q gpuswitch; then
    warn "gpuswitch unavailable on this system."
    return 0
  fi

  xcmd sudo pmset -a gpuswitch "$mode"
  sleep 2

  [[ "$DRY_RUN" == true ]] && return 0

  # Verify with up to 3 retries
  local retries=3
  while [[ $retries -gt 0 ]]; do
    local current
    current=$(pmset -g | grep gpuswitch | awk '{print $2}')
    if [[ "$current" == "$mode" ]]; then
      ok "GPU mode: ${label} (verified)."
      return 0
    fi
    warn "GPU state mismatch (expected=$mode, got=${current:-?}). Retrying... ($retries left)"
    xcmd sudo pmset -a gpuswitch "$mode"
    sleep 2
    (( retries-- ))
  done

  err "GPU switch verification failed after 3 retries. A logout may be required."
}

# ── AI / ML daemon management ────────────────────────────────────────────────
KNOWN_AI_DAEMONS=(
  "mediaanalysisd"      # Photos/video ML frame analysis
  "knowledge-agent"     # CoreML on-device learning (Siri intelligence)
  "suggestd"            # Siri Suggestions + Spotlight learning
  "parsecd"             # Siri natural-language parsing server
  "coreduetd"           # Activity + usage pattern prediction
  "UsageTrackingAgent"  # App usage analytics
  "routined"            # Location + routine ML model
)

AI_DAEMON_PLISTS=(
  "com.apple.mediaanalysisd"
  "com.apple.knowledge-agent"
  "com.apple.suggestd"
  "com.apple.parsecd"
  "com.apple.coreduetd"
  "com.apple.UsageTrackingAgent"
  "com.apple.routined"
)

kill_ai_daemons() {
  local killed=0

  for i in "${!KNOWN_AI_DAEMONS[@]}"; do
    local daemon="${KNOWN_AI_DAEMONS[$i]}"
    local plist="${AI_DAEMON_PLISTS[$i]}"
    local pids
    pids=$(pgrep -x "$daemon" 2>/dev/null || true)

    if [[ -n "$pids" ]]; then
      # Step 1: Signal via launchctl (user domain)
      xcmd launchctl kill SIGTERM "gui/$(id -u)/${plist}" 2>/dev/null || true

      # Step 2: Direct kill as fallback
      for pid in $pids; do
        if xcmd sudo kill -TERM "$pid" 2>/dev/null; then
          ok "Killed ${daemon} (PID ${pid})"
          KILLED_DAEMONS+=("$daemon")
          killed=$(( killed + 1 ))
        else
          warn "Could not kill ${daemon} (PID ${pid}) — likely SIP-protected"
        fi
      done

      # Step 3: renice any survivors
      sleep 0.5
      local new_pids
      new_pids=$(pgrep -x "$daemon" 2>/dev/null || true)
      for pid in $new_pids; do
        if xcmd sudo renice 15 "$pid" 2>/dev/null; then
          ok "Reniced ${daemon} (PID ${pid}) → nice=15"
        fi
      done
    fi
  done

  if [[ "$killed" -eq 0 ]]; then
    info "No AI daemons found running."
  else
    ok "${killed} AI daemon(s) terminated."
  fi
}

# ── QoS enforcement via taskpolicy ───────────────────────────────────────────
# Pushes non-critical background apps to Background QoS tier.
# The kernel gives Background-QoS processes minimal CPU time slices —
# they only run when the CPU is otherwise idle.
QOS_TARGETS=(
  "Google Chrome Helper"
  "Electron"
  "Slack Helper"
  "Dropbox"
  "OneDrive"
  "Microsoft AutoUpdate"
  "CrashReporter"
  "backupd"
)

throttle_background_processes() {
  local throttled=0
  for proc in "${QOS_TARGETS[@]}"; do
    local pids
    pids=$(pgrep -if "$proc" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
      for pid in $pids; do
        if xcmd sudo taskpolicy -b -p "$pid" 2>/dev/null; then
          ok "Background QoS: ${proc} (PID ${pid})"
          throttled=$(( throttled + 1 ))
        fi
      done
    fi
  done
  [[ "$throttled" -eq 0 ]] && info "No background QoS targets found running."
}

# ── Memory flush ──────────────────────────────────────────────────────────────
flush_memory() {
  local before_pages before_mb freed_mb
  # shellcheck disable=SC2006
  before_pages=$(vm_stat | awk '/Pages inactive/{gsub(/\./,"",$3); print $3}')
  before_mb=$(( (before_pages * 4096) / 1024 / 1024 ))

  xcmd sudo purge
  sleep 1

  local after_pages after_mb
  # shellcheck disable=SC2006
  after_pages=$(vm_stat | awk '/Pages inactive/{gsub(/\./,"",$3); print $3}')
  after_mb=$(( (after_pages * 4096) / 1024 / 1024 ))
  freed_mb=$(( before_mb - after_mb ))

  ok "Purged ~${freed_mb} MB inactive memory. Swap pressure reduced."
}

# ── Spotlight — kill + disable ────────────────────────────────────────────────
kill_spotlight() {
  # Kill running indexers first (immediate heat reduction)
  xcmd sudo killall mds mds_stores mdworker_shared 2>/dev/null || true
  sleep 0.5
  if xcmd sudo mdutil -a -i off 2>/dev/null; then
    ok "Spotlight indexing disabled (all volumes)."
  else
    warn "Spotlight control limited (SIP may be blocking). Continuing."
  fi
}

# ── Time Machine — version-aware ─────────────────────────────────────────────
disable_timemachine() {
  if [[ "$MACOS_VERSION" -ge 12 ]]; then
    if xcmd sudo tmutil disable 2>/dev/null; then
      ok "Time Machine disabled."
    else
      warn "tmutil disable unavailable (already off or restricted)."
    fi
  else
    if xcmd sudo tmutil disablelocal 2>/dev/null || xcmd sudo tmutil disable 2>/dev/null; then
      ok "Time Machine disabled."
    else
      warn "tmutil unavailable. Skipping."
    fi
  fi
}

enable_timemachine() {
  if xcmd sudo tmutil enable 2>/dev/null; then
    ok "Time Machine re-enabled."
  else
    warn "tmutil enable unavailable."
  fi
}

# ── Radio control (WiFi + Bluetooth) ─────────────────────────────────────────
disable_radios() {
  # WiFi
  if [[ -n "$WIFI_IF" ]]; then
    if xcmd sudo networksetup -setairportpower "$WIFI_IF" off 2>/dev/null; then
      ok "WiFi disabled (${WIFI_IF})."
    else
      warn "Could not disable WiFi."
    fi
  else
    warn "WiFi interface not found."
  fi

  # Bluetooth (optional — needs blueutil)
  if command -v blueutil &>/dev/null; then
    if xcmd blueutil -p 0; then
      ok "Bluetooth disabled."
    else
      warn "blueutil: Bluetooth disable failed."
    fi
  else
    warn "Bluetooth still active. Install blueutil: brew install blueutil"
  fi
}

enable_radios() {
  if [[ -n "$WIFI_IF" ]]; then
    if xcmd sudo networksetup -setairportpower "$WIFI_IF" on 2>/dev/null; then
      ok "WiFi re-enabled (${WIFI_IF})."
    else
      warn "Could not re-enable WiFi."
    fi
  fi
  if command -v blueutil &>/dev/null; then
    if xcmd blueutil -p 1; then
      ok "Bluetooth re-enabled."
    fi
  fi
}

# ── LaunchAgent management ────────────────────────────────────────────────────
unload_agent() {
  local plist="$1"
  if xcmd launchctl unload -w "${plist}" 2>/dev/null; then
    ok "Unloaded: $(basename "$plist" .plist)"
  else
    warn "Could not unload: $(basename "$plist" .plist) (may be SIP-protected or absent)"
  fi
}

load_agent() {
  local plist="$1"
  if xcmd launchctl load -w "${plist}" 2>/dev/null; then
    ok "Loaded: $(basename "$plist" .plist)"
  fi
}

LA="/System/Library/LaunchAgents"

# ═══════════════════════════════════════════════════════════════════════════════
#  MODES
# ═══════════════════════════════════════════════════════════════════════════════

# ── ICEBERG — Absolute maximum cooling ───────────────────────────────────────
apply_iceberg() {
  step "1/10" "GPU → iGPU only"
  set_gpu_mode 0

  step "2/10" "AI Daemons → Kill + renice survivors"
  kill_ai_daemons

  step "3/10" "Background Apps → Background QoS"
  throttle_background_processes

  step "4/10" "Memory → Flush inactive pages"
  flush_memory

  step "5/10" "Radios → Disable WiFi + Bluetooth"
  disable_radios

  step "6/10" "Spotlight → Kill + Disable"
  kill_spotlight

  step "7/10" "Time Machine → Disable"
  disable_timemachine

  step "8/10" "Power Management → Maximum suppression"
  xcmd sudo pmset -a powernap 0 standby 0 hibernatemode 0 sms 0 sleep 0
  ok "Sleep=0, PowerNap=0, Standby=0."

  step "9/10" "UI Compositor → Minimal"
  xcmd defaults write com.apple.universalaccess reduceMotion -bool true
  xcmd defaults write com.apple.universalaccess reduceTransparency -bool true
  ok "Motion + Transparency disabled."

  step "10/10" "CPU Turbo hint → Efficiency preference"
  xcmd sudo sysctl -w machdep.xcpm.perf_hint=3 2>/dev/null \
    && ok "CPU efficiency hint applied." \
    || warn "machdep.xcpm.perf_hint unavailable on this macOS version."

  echo -e "\n${BLUE}${BOLD}  ❄❄❄  ICEBERG — Maximum cooling active.${RESET}"
  warn "Network is OFFLINE. Run 'restore' to re-enable WiFi."
}

# ── CHILL — Light work / video ────────────────────────────────────────────────
apply_chill() {
  step "1/8" "GPU → iGPU only"
  set_gpu_mode 0

  step "2/8" "AI Daemons → Kill + renice"
  kill_ai_daemons

  step "3/8" "Memory → Flush"
  flush_memory

  step "4/8" "Power Management → Suppress background wakeups"
  xcmd sudo pmset -a powernap 0 standby 0 hibernatemode 0 sms 0
  ok "PowerNap / Standby / SMS disabled."

  step "5/8" "Spotlight → Pause"
  kill_spotlight

  step "6/8" "Time Machine → Disable"
  disable_timemachine

  step "7/8" "Background Apps → Background QoS"
  throttle_background_processes

  step "8/8" "UI Compositor → Reduce"
  xcmd defaults write com.apple.universalaccess reduceMotion -bool true
  xcmd defaults write com.apple.universalaccess reduceTransparency -bool true
  ok "Motion + Transparency reduced."

  echo -e "\n${GREEN}${BOLD}  ❄  CHILL mode active.${RESET}"
}

# ── PROGRAMMING — Code editors / compilers ────────────────────────────────────
apply_programming() {
  step "1/6" "GPU → Auto (Metal editors supported)"
  set_gpu_mode 2

  step "2/6" "AI Daemons → Kill + renice"
  kill_ai_daemons

  step "3/6" "Memory → Flush"
  flush_memory

  step "4/6" "Power Management → CPU headroom"
  xcmd sudo pmset -a powernap 0 standby 0 hibernatemode 0 sms 0
  ok "Background wakeups suppressed."

  step "5/6" "Spotlight → Re-enable (needed for code search)"
  if xcmd sudo mdutil -a -i on 2>/dev/null; then
    ok "Spotlight on."
  else
    warn "Could not enable Spotlight."
  fi

  step "6/6" "UI Compositor → Balanced"
  xcmd defaults write com.apple.universalaccess reduceMotion -bool true
  xcmd defaults write com.apple.universalaccess reduceTransparency -bool false
  ok "Motion reduced. Transparency kept (editor contrast)."

  echo -e "\n${GREEN}${BOLD}  💻  PROGRAMMING mode active.${RESET}"
}

# ── BEAST — Maximum raw performance ──────────────────────────────────────────
apply_beast() {
  step "1/7" "GPU → Auto (dGPU available for compute)"
  set_gpu_mode 2

  step "2/7" "AI Daemons → Kill + renice"
  kill_ai_daemons

  step "3/7" "Memory → Flush"
  flush_memory

  step "4/7" "Power Management → Max headroom"
  xcmd sudo pmset -a powernap 0 standby 0 hibernatemode 0 sms 0 sleep 0
  ok "Sleep disabled. Machine stays awake."

  step "5/7" "Spotlight → Disable (I/O competition)"
  kill_spotlight

  step "6/7" "Time Machine → Disable"
  disable_timemachine

  step "7/7" "UI Compositor → Minimal"
  xcmd defaults write com.apple.universalaccess reduceMotion -bool true
  xcmd defaults write com.apple.universalaccess reduceTransparency -bool true
  ok "Motion + Transparency disabled."

  echo -e "\n${RED}${BOLD}  ⚡  BEAST mode active.${RESET}"
}

# ── MARATHON — Long tasks / stable thermals ───────────────────────────────────
apply_marathon() {
  step "1/9" "GPU → iGPU only"
  set_gpu_mode 0

  step "2/9" "AI Daemons → Kill + renice"
  kill_ai_daemons

  step "3/9" "Background Apps → Background QoS"
  throttle_background_processes

  step "4/9" "Memory → Flush"
  flush_memory

  step "5/9" "Power Management → No interruptions"
  xcmd sudo pmset -a powernap 0 standby 0 hibernatemode 0 sms 0 sleep 0
  ok "Machine will not sleep."

  step "6/9" "Spotlight → Disable"
  kill_spotlight

  step "7/9" "Time Machine → Disable"
  disable_timemachine

  step "8/9" "Siri + Game Center → Unload"
  unload_agent "${LA}/com.apple.Siri.agent.plist"
  unload_agent "${LA}/com.apple.gamed.plist"

  step "9/9" "UI Compositor → Minimal"
  xcmd defaults write com.apple.universalaccess reduceMotion -bool true
  xcmd defaults write com.apple.universalaccess reduceTransparency -bool true
  ok "UI impact minimized."

  echo -e "\n${YELLOW}${BOLD}  🕰  MARATHON mode active.${RESET}"
}

# ── RESTORE — Return to macOS defaults ───────────────────────────────────────
apply_restore() {
  step "1/7" "GPU → Auto"
  set_gpu_mode 2

  step "2/7" "Radios → Re-enable"
  enable_radios

  step "3/7" "pmset → Restore macOS defaults"
  xcmd sudo pmset -a powernap 1 standby 1 hibernatemode 3 sms 1 sleep 1
  ok "Power management restored."

  step "4/7" "Spotlight → Re-enable"
  if xcmd sudo mdutil -a -i on 2>/dev/null; then
    ok "Spotlight indexing on."
  fi

  step "5/7" "Time Machine → Re-enable"
  enable_timemachine

  step "6/7" "Siri + Game Center → Reload"
  load_agent "${LA}/com.apple.Siri.agent.plist"
  load_agent "${LA}/com.apple.gamed.plist"

  step "7/7" "UI Compositor → Restore defaults"
  xcmd defaults write com.apple.universalaccess reduceMotion -bool false
  xcmd defaults write com.apple.universalaccess reduceTransparency -bool false
  ok "Motion + Transparency restored."

  echo -e "\n${GREEN}${BOLD}  🔄  System restored to macOS defaults.${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  AUDIT — Full Thermal Diagnostic Report
# ─────────────────────────────────────────────────────────────────────────────
run_audit() {
  clear
  echo ""
  echo -e "${BOLD}${MAGENTA}  ╔═══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${MAGENTA}  ║         THERMAL AUDIT — Full System Scan          ║${RESET}"
  echo -e "${BOLD}${MAGENTA}  ╚═══════════════════════════════════════════════════╝${RESET}"
  echo ""

  # ── 1. Hardware profile ───────────────────────────────────────────────────
  step "1/7" "Hardware Profile"
  local model cpu gpu smc_ver
  model=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
  cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  gpu=$(system_profiler SPDisplaysDataType 2>/dev/null \
        | grep "Chipset Model" | head -1 | awk -F': ' '{print $2}' || echo "Unknown")
  smc_ver=$(system_profiler SPHardwareDataType 2>/dev/null \
            | awk '/SMC Version/{print $3}' || echo "Unknown")
  echo -e "  Model       : ${CYAN}${model}${RESET}"
  echo -e "  CPU         : ${CYAN}${cpu}${RESET}"
  echo -e "  Active GPU  : ${CYAN}${gpu}${RESET}"
  echo -e "  SMC Version : ${CYAN}${smc_ver}${RESET}"
  echo -e "  macOS       : ${CYAN}$(sw_vers -productVersion)${RESET}"

  # ── 2. Battery health ─────────────────────────────────────────────────────
  step "2/7" "Battery Health"
  local cycles health max_cap max_cap_int
  cycles=$(system_profiler SPPowerDataType 2>/dev/null | awk '/Cycle Count/{print $3}')
  health=$(system_profiler SPPowerDataType 2>/dev/null | awk '/Condition/{print $2}')
  max_cap=$(system_profiler SPPowerDataType 2>/dev/null | awk '/Maximum Capacity/{print $3}')
  max_cap_int=${max_cap//%/}  # Strip % for numeric comparison

  echo -e "  Cycle Count     : ${CYAN}${cycles:-?}${RESET}"
  echo -e "  Condition       : ${CYAN}${health:-Unknown}${RESET}"
  echo -e "  Max Capacity    : ${CYAN}${max_cap:-?}${RESET}"

  local cycles_int=${cycles:-0}
  [[ "${cycles_int}" -gt 1000 ]] \
    && warn "High cycle count (${cycles_int}). Degraded cells increase charge heat."
  [[ "${max_cap_int:-100}" -lt 80 ]] \
    && warn "Battery capacity < 80%. Degraded cell = higher charge current = more heat."
  [[ "${health:-Normal}" != "Normal" ]] \
    && err "Battery condition: ${health}. Replacement recommended."

  # ── 3. Disk space ─────────────────────────────────────────────────────────
  step "3/7" "SSD Usage (low space → write amplification → heat)"
  local free_gb total_gb used_pct
  free_gb=$(df -g / 2>/dev/null | tail -1 | awk '{print $4}')
  total_gb=$(df -g / 2>/dev/null | tail -1 | awk '{print $2}')
  used_pct=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
  echo -e "  Free / Total    : ${CYAN}${free_gb:-?} GB / ${total_gb:-?} GB (${used_pct:-?}% used)${RESET}"
  [[ "${free_gb:-100}" -lt 20 ]] \
    && warn "< 20 GB free. SSD garbage collection + wear leveling causes thermal spikes."
  [[ "${used_pct:-0}" -gt 90 ]] \
    && warn "SSD > 90% full. NVMe thermal throttling very likely."

  # ── 4. Live thermal sensors ────────────────────────────────────────────────
  step "4/7" "Live Thermal Sensors (5-second sample)"
  info "Sampling — please wait 5s..."
  local sensor_output
  sensor_output=$(sudo powermetrics --samplers smc -n 1 -i 5000 2>/dev/null \
                  | grep -E "CPU die|GPU die|Proximity|Fan" || echo "  No data (powermetrics failed)")
  echo ""
  while IFS= read -r line; do
    # Highlight danger zones
    if echo "$line" | grep -qE "[89][0-9]\.[0-9]+ C|100\.[0-9]+ C"; then
      echo -e "  ${RED}${line}${RESET}  ← DANGER"
    elif echo "$line" | grep -qE "7[5-9]\.[0-9]+ C|8[0-9]\.[0-9]+ C"; then
      echo -e "  ${YELLOW}${line}${RESET}  ← HIGH"
    else
      echo -e "  ${DIM}${line}${RESET}"
    fi
  done <<< "$sensor_output"

  # ── 5. Throttle detection ─────────────────────────────────────────────────
  step "5/7" "Thermal Throttle Detection"
  local kernel_cpu kernel_int
  kernel_cpu=$(ps aux 2>/dev/null | awk '/kernel_task/ && !/awk/ {print $3; exit}')
  kernel_int=${kernel_cpu%.*}

  echo -e "  kernel_task CPU : ${CYAN}${kernel_cpu:-?}%${RESET}"
  if [[ "${kernel_int:-0}" -gt 100 ]]; then
    err "SEVERE THROTTLING — kernel_task at ${kernel_cpu}%. System critically hot."
    warn "Recommended: Apply ICEBERG mode, charge from RIGHT port, ensure airflow."
  elif [[ "${kernel_int:-0}" -gt 50 ]]; then
    warn "ACTIVE THROTTLING — kernel_task at ${kernel_cpu}%. Apply Chill or Iceberg mode."
  elif [[ "${kernel_int:-0}" -gt 20 ]]; then
    warn "MILD THROTTLING — kernel_task at ${kernel_cpu}%. Temps elevated."
  else
    ok "No active throttling (kernel_task: ${kernel_cpu}%)."
  fi

  # ── 6. AI daemon heat source scan ─────────────────────────────────────────
  step "6/7" "AI/ML Background Daemons (Confirmed Heat Sources)"
  local running_count=0
  for daemon in "${KNOWN_AI_DAEMONS[@]}"; do
    local pid daemon_cpu
    pid=$(pgrep -x "$daemon" 2>/dev/null | head -1 || true)
    if [[ -n "$pid" ]]; then
      daemon_cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "?")
      warn "${daemon} RUNNING — PID ${pid}, CPU ${daemon_cpu}%"
      (( running_count++ ))
    fi
  done
  if [[ $running_count -eq 0 ]]; then
    ok "No AI daemons running. (Already killed or never started.)"
  else
    info "Run 'iceberg' or 'chill' mode to terminate these ${running_count} daemon(s)."
  fi

  # ── 7. Power settings audit ───────────────────────────────────────────────
  step "7/7" "Current Power Settings vs. Optimal"
  local gsw pnap stby hib sms_val
  gsw=$(pmset -g | grep gpuswitch | awk '{print $2}')
  pnap=$(pmset -g | grep powernap | awk '{print $2}')
  stby=$(pmset -g | grep -w "^[[:space:]]*standby " | awk '{print $2}' | head -1)
  hib=$(pmset -g | grep hibernatemode | awk '{print $2}')
  sms_val=$(pmset -g | grep "^[[:space:]]*sms " | awk '{print $2}')

  printf "  %-20s %-12s %-12s %s\n" "Setting" "Current" "Optimal" "Status"
  printf "  %-20s %-12s %-12s %s\n" "───────" "───────" "───────" "──────"
  _audit_row "gpuswitch"    "${gsw:-?}"    "0"  "(0=iGPU only for cooling)"
  _audit_row "powernap"     "${pnap:-?}"   "0"  "(0=no background wake)"
  _audit_row "standby"      "${stby:-?}"   "0"  "(0=no hibernate transition)"
  _audit_row "hibernatemode" "${hib:-?}"   "0"  "(0=no RAM dump on sleep)"
  _audit_row "sms"          "${sms_val:-?}" "0" "(0=safe on SSD)"

  sep
  echo ""
  echo -e "${BOLD}  Audit complete.${RESET}"
  echo -e "  ${DIM}Apply 'chill' mode to address warnings above, or 'iceberg' for maximum cooling.${RESET}"
  echo ""
}

# Audit helper: print a settings row with pass/warn colouring
_audit_row() {
  local name="$1" current="$2" optimal="$3" desc="$4"
  if [[ "$current" == "$optimal" ]]; then
    printf "  %-20s ${GREEN}%-12s${RESET} %-12s ${GREEN}✓${RESET} %s\n" "$name" "$current" "$optimal" "$desc"
  else
    printf "  %-20s ${YELLOW}%-12s${RESET} %-12s ${YELLOW}⚠${RESET} %s\n" "$name" "$current" "$optimal" "$desc"
  fi
}

# ── MONITOR — Live thermal dashboard ─────────────────────────────────────────
show_monitor() {
  echo -e "\n${BOLD}  Live Thermal Monitor${RESET} — ${DIM}Ctrl+C to exit${RESET}\n"
  warn "Sampling: CPU/GPU temp, fan speeds, power draw, throttle events."
  echo -e "  ${DIM}Starting in 2s...${RESET}\n"
  sleep 2
  xcmd sudo powermetrics \
    --samplers smc,cpu_power,gpu_power \
    -i 2000 \
    2>/dev/null \
    | grep --line-buffered -E "CPU die|GPU die|Fan|Power|Throttl|System Average" \
    | while IFS= read -r line; do
        echo -e "  ${DIM}$(date +%H:%M:%S)${RESET}  $line"
      done
}

# ── Status snapshot (No sudo needed) ──────────────────────────────────────────
show_status() {
  sep
  echo -ne "${BOLD}  Current Configuration Snapshot${RESET}\n"
  sep

  local gpuswitch standby powernap hibernatemode sleep_val sms_val motion transparency

  # shellcheck disable=SC2006
  gpuswitch=$(pmset -g | grep gpuswitch | awk '{print $2}' || echo "N/A")
  # shellcheck disable=SC2006
  standby=$(pmset -g | grep -w standby | awk '{print $2}' || echo "N/A")
  # shellcheck disable=SC2006
  powernap=$(pmset -g | grep -w powernap | awk '{print $2}' || echo "N/A")
  # shellcheck disable=SC2006
  hibernatemode=$(pmset -g | grep -w hibernatemode | awk '{print $2}' || echo "N/A")
  # shellcheck disable=SC2006
  sleep_val=$(pmset -g | grep -w " sleep" | awk '{print $2}' | head -1 || echo "N/A")
  # shellcheck disable=SC2006
  sms_val=$(pmset -g | grep -w sms | awk '{print $2}' || echo "N/A")

  motion=$(defaults read com.apple.universalaccess reduceMotion 2>/dev/null || echo "0")
  transparency=$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo "0")

  echo -e "  GPU Switch   : $([[ "$gpuswitch" == 0 ]] && echo -e "${BLUE}iGPU Only${RESET}" || echo "Auto/dGPU")"
  echo -e "  PowerNap     : $([[ "$powernap" == 0 ]] && echo -e "${GREEN}OFF${RESET}" || echo -e "${YELLOW}ON${RESET}")"
  echo -e "  Standby      : $([[ "$standby" == 0 ]] && echo -e "${GREEN}OFF${RESET}" || echo -e "${YELLOW}ON${RESET}")"
  echo -e "  Hibernatemode: $hibernatemode"
  echo -e "  Sleep Timer  : $([[ "$sleep_val" == 0 ]] && echo -e "${GREEN}Disabled (0)${RESET}" || echo "$sleep_val min")"
  echo -e "  SMS (Sensor) : $([[ "$sms_val" == 0 ]] && echo -e "${GREEN}OFF${RESET}" || echo -e "${YELLOW}ON${RESET}")"
  echo -e "  ReduceMotion : $([[ "$motion" == 1 ]] && echo -e "${GREEN}Enabled${RESET}" || echo "Disabled")"
  echo -e "  ReduceTransp : $([[ "$transparency" == 1 ]] && echo -e "${GREEN}Enabled${RESET}" || echo "Disabled")"
  sep
}

# ─────────────────────────────────────────────────────────────────────────────
#  HELP
# ─────────────────────────────────────────────────────────────────────────────
show_help() {
  cat <<EOF

Mac Thermal Manager v${VERSION}
https://github.com/yadavnikhil17102004/Macbook_Thermal_Configurator

USAGE:
  sudo ./thermal_manager.sh [MODE] [OPTIONS]

MODES:
  (none)        Launch interactive menu
  iceberg       ❄❄❄  Absolute max cooling — radios OFF, AI killed, QoS enforced,
                     memory flushed, CPU efficiency hint applied
  chill         ❄    Video / browsing — iGPU only, AI killed, Spotlight off
  programming   💻   Code editors — Auto GPU, AI killed, Spotlight ON
  beast         ⚡   Max performance — dGPU auto, sleep=0, AI killed
  marathon      🕰   Long tasks — iGPU, QoS enforced, Siri/GameCenter off
  audit         📊   Full thermal diagnostic (battery, sensors, throttle, daemons)
  monitor       📈   Live thermal dashboard (CPU temp, GPU power, fan speeds)
  restore       🔄   Reset ALL settings to macOS defaults + re-enable radios

OPTIONS:
  --help | -h   Show this help
  --version     Show version
  --status      Snapshot of current config (no sudo needed)
  --dry-run | -n  Preview commands without making changes

EXAMPLES:
  sudo ./thermal_manager.sh iceberg
  ./thermal_manager.sh --status
  ./thermal_manager.sh --dry-run chill

EOF
}

show_header() {
  echo -e "${BOLD}${CYAN}  ╔═══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}  ║   MacBook Thermal Manager v${VERSION} — Intelligence     ║${RESET}"
  echo -e "${BOLD}${CYAN}  ║   Intel i7 / AMD Radeon 555X (A1990)              ║${RESET}"
  echo -e "${BOLD}${CYAN}  ╚═══════════════════════════════════════════════════╝${RESET}"
  echo ""
}

# ── Main Menu ─────────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    clear
    echo ""
    show_header
    [[ "$DRY_RUN" == true ]] && echo -e "  ${YELLOW}${BOLD}⚠ DRY-RUN mode active — no system changes will be pushed.${RESET}\n"
    show_current_state

    echo -e "  ${BOLD}Select Optimization Mode:${RESET}\n"
    echo -e "  ${BLUE}[1]${RESET}  ❄❄❄  ICEBERG      — ${DIM}Radios OFF, AI killed, QoS, purge${RESET}"
    echo -e "  ${GREEN}[2]${RESET}  ❄    Chill        — ${DIM}iGPU, AI killed, Spotlight off${RESET}"
    echo -e "  ${BLUE}[3]${RESET}  💻   Programming  — ${DIM}Auto GPU, AI killed, Spotlight on${RESET}"
    echo -e "  ${RED}[4]${RESET}  ⚡   Beast         — ${DIM}dGPU auto, sleep=0, AI killed${RESET}"
    echo -e "  ${YELLOW}[5]${RESET}  🕰   Marathon      — ${DIM}iGPU, QoS enforced, stable temps${RESET}"
    echo -e "  ${MAGENTA}[6]${RESET}  📊   AUDIT         — ${DIM}Battery health, throttle detection, sensor scan${RESET}"
    echo -e "  ${DIM}[7]${RESET}  📈   Monitor       — ${DIM}Live thermal dashboard${RESET}"
    echo -e "  ${DIM}[8]${RESET}  🔄   Restore       — ${DIM}Reset to macOS defaults + re-enable radios${RESET}"
    echo -e "  ${DIM}[0]${RESET}  ✗    Exit"
    echo ""
    echo -ne "  ${BOLD}Choice [0-8]:${RESET} "
    read -r choice

    # Sanitize choice
    choice="${choice//[^0-8]/}"
    [[ -z "$choice" ]] && continue

    case "$choice" in
      1) sep; apply_iceberg ;;
      2) sep; apply_chill ;;
      3) sep; apply_programming ;;
      4) sep; apply_beast ;;
      5) sep; apply_marathon ;;
      6) run_audit ;;
      7) show_monitor ;;
      8) sep; apply_restore ;;
      0) echo -e "\n  Goodbye!\n"; cleanup_sudo; exit 0 ;;
      *) warn "Invalid choice."; sleep 1 ;;
    esac

    echo ""
    sep
    echo -ne "\n  ${DIM}Press Enter to return to menu, or Ctrl+C to exit...${RESET}"
    read -r
  done
}

# ── Entry Point ───────────────────────────────────────────────────────────────
check_platform

# Parse global flags
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    --status)     show_status; exit 0 ;;
    --version)    echo "thermal_manager.sh v${VERSION}"; exit 0 ;;
    --help|-h)    show_help; exit 0 ;;
  esac
done

# Strip flags for positional MODE
# shellcheck disable=SC2048
for arg in $*; do
  case "$arg" in
    iceberg|chill|programming|beast|marathon|audit|monitor|restore)
      MODE="$arg"
      break
      ;;
  esac
done

if [[ -n "${MODE:-}" ]]; then
  # Sudo required for all modes except monitor
  [[ "$MODE" != "monitor" ]] && require_sudo

  case "$MODE" in
    iceberg)     apply_iceberg ;;
    chill)       apply_chill ;;
    programming) apply_programming ;;
    beast)       apply_beast ;;
    marathon)    apply_marathon ;;
    audit)       run_audit ;;
    monitor)     show_monitor ;;
    restore)     apply_restore ;;
  esac
else
  main_menu
fi
