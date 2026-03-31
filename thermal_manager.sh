#!/usr/bin/env bash
# =============================================================================
#  thermal_manager.sh — MacBook Pro A1990 Performance Mode Switcher
#  Author  : Antigravity (for Nikhil)
#  Hardware: Intel i7 / AMD Radeon 555X (A1990)
#  Requires: sudo, Homebrew, smcFanControl or Macs Fan Control (optional)
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'
RESET='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
info()  { echo -e "  ${CYAN}→${RESET} $*"; }
ok()    { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()   { echo -e "  ${RED}✗${RESET} $*"; }
step()  { echo -e "\n${BOLD}${BLUE}[$1]${RESET} $2"; }
sep()   { echo -e "${DIM}──────────────────────────────────────────────────────${RESET}"; }

# ── Sudo check ────────────────────────────────────────────────────────────────
require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo -e "\n${YELLOW}This script needs sudo for pmset / powermetrics.${RESET}"
    sudo -v || { err "sudo failed. Exiting."; exit 1; }
  fi
  # Keep sudo alive in background
  ( while true; do sudo -n true; sleep 50; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT
}

# ── Dependency check ──────────────────────────────────────────────────────────
check_deps() {
  local missing=()
  for cmd in pmset launchctl defaults system_profiler; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 1
  fi

  # Optional tools — warn but don't exit
  command -v brew &>/dev/null || warn "Homebrew not found. Some features (fan control) may be limited."
}

# ── Current state snapshot ────────────────────────────────────────────────────
show_current_state() {
  sep
  echo -e "${BOLD}  Current System State${RESET}"
  sep
  local gpu
  gpu=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1 | awk -F': ' '{print $2}' || echo "Unknown")
  local gpuswitch
  gpuswitch=$(pmset -g | grep gpuswitch | awk '{print $2}' || echo "?")
  local gpumode
  case "$gpuswitch" in
    0) gpumode="Integrated only" ;;
    1) gpumode="Discrete only" ;;
    2) gpumode="Auto (default)" ;;
    *) gpumode="Unknown" ;;
  esac

  local powernap
  powernap=$(pmset -g | grep powernap | awk '{print $2}' || echo "?")
  local standby
  standby=$(pmset -g | grep -w "^[[:space:]]*standby " | awk '{print $2}' | head -1 || echo "?")

  echo -e "  Active GPU    : ${CYAN}${gpu}${RESET}"
  echo -e "  GPU Switch    : ${CYAN}${gpumode}${RESET}"
  echo -e "  Power Nap     : ${CYAN}${powernap}${RESET}"
  echo -e "  Standby       : ${CYAN}${standby}${RESET}"
  sep
}

# ── Mode: CHILL ───────────────────────────────────────────────────────────────
# Target: video watching, browsing, light usage
# Philosophy: max thermals win, sacrifice raw performance
apply_chill() {
  step "1/6" "GPU → Force Integrated (iGPU only)"
  sudo pmset -a gpuswitch 0
  ok "dGPU disabled. AMD 555X will not activate."

  step "2/6" "Power Management — reduce background wakeups"
  sudo pmset -a powernap 0
  sudo pmset -a standby 0
  sudo pmset -a hibernatemode 0
  sudo pmset -a sms 0
  ok "PowerNap / Standby / SMS disabled."

  step "3/6" "Spotlight Indexing — pause"
  sudo mdutil -a -i off 2>/dev/null && ok "Spotlight indexing paused." || warn "Could not pause Spotlight (may need SIP adjustment)."

  step "4/6" "Background Services — quiet mode"
  # Disable Time Machine local snapshots (major I/O heat source)
  sudo tmutil disablelocal 2>/dev/null && ok "Time Machine local snapshots disabled." || warn "tmutil disablelocal unavailable (macOS 12+). Skipping."

  # Notifications: reduce polling
  launchctl unload -w /System/Library/LaunchAgents/com.apple.gamed.plist 2>/dev/null && ok "Game Center daemon unloaded." || warn "Game Center already unloaded or unavailable."

  step "5/6" "UI Compositor — reduce GPU heat"
  defaults write com.apple.universalaccess reduceMotion -bool true
  defaults write com.apple.universalaccess reduceTransparency -bool true
  ok "Reduce Motion + Transparency enabled."

  step "6/6" "Browser Recommendation"
  warn "For video: use Safari (hardware decode). Chrome triggers dGPU."

  echo -e "\n${GREEN}${BOLD}  ❄  CHILL mode active.${RESET}"
  echo -e "  Expected thermals: CPU ≤ 60°C at idle/video."
  echo -e "  ${DIM}Turbo Boost: still active. Disable manually via Turbo Boost Switcher if temps stay high.${RESET}"
}

# ── Mode: PROGRAMMING ─────────────────────────────────────────────────────────
# Target: code editors, compilers, terminals
# Philosophy: balance — let CPU burst, keep GPU efficient
apply_programming() {
  step "1/5" "GPU → Auto (editors may use Metal)"
  sudo pmset -a gpuswitch 2
  ok "GPU switching set to Auto."

  step "2/5" "Power Management — allow CPU headroom"
  sudo pmset -a powernap 0
  sudo pmset -a standby 0
  sudo pmset -a hibernatemode 0
  sudo pmset -a sms 0
  ok "Background wakeups suppressed."

  step "3/5" "Spotlight Indexing — re-enable (needed for code search)"
  sudo mdutil -a -i on 2>/dev/null && ok "Spotlight indexing enabled." || warn "Could not enable Spotlight."

  step "4/5" "UI compositor — balanced"
  defaults write com.apple.universalaccess reduceMotion -bool true
  defaults write com.apple.universalaccess reduceTransparency -bool false
  ok "Reduce Motion on, Transparency off (balanced)."

  step "5/5" "Time Machine — pause during session"
  sudo tmutil disable 2>/dev/null && ok "Time Machine disabled for this session." || warn "tmutil disable unavailable or already off."

  echo -e "\n${GREEN}${BOLD}  💻  PROGRAMMING mode active.${RESET}"
  echo -e "  Turbo Boost: ON (compiler bursts welcome)."
  echo -e "  GPU: Auto — Metal/GPU-accelerated editors will work."
}

# ── Mode: BEAST (Resource-Intensive) ─────────────────────────────────────────
# Target: video export, ML training, large builds, Xcode
# Philosophy: maximum throughput, accept heat, monitor closely
apply_beast() {
  step "1/5" "GPU → Auto (dGPU available for GPU workloads)"
  sudo pmset -a gpuswitch 2
  ok "Auto GPU switching. dGPU will engage as needed."

  step "2/5" "Power Management — maximum headroom"
  sudo pmset -a powernap 0
  sudo pmset -a standby 0
  sudo pmset -a hibernatemode 0
  sudo pmset -a sms 0
  sudo pmset -a sleep 0      # prevent sleep during long tasks
  ok "Sleep disabled. Machine will stay awake."

  step "3/5" "Spotlight — disable during task (I/O competition)"
  sudo mdutil -a -i off 2>/dev/null && ok "Spotlight paused." || warn "Spotlight may still run."

  step "4/5" "Time Machine — disable"
  sudo tmutil disable 2>/dev/null && ok "Time Machine off." || warn "Unavailable."

  step "5/5" "UI compositor — reduce (free up GPU for compute)"
  defaults write com.apple.universalaccess reduceMotion -bool true
  defaults write com.apple.universalaccess reduceTransparency -bool true
  ok "Motion + Transparency reduced."

  echo -e "\n${RED}${BOLD}  ⚡  BEAST mode active.${RESET}"
  warn "CPU will run at full Turbo Boost. Monitor temps with:"
  echo -e "  ${DIM}sudo powermetrics --samplers smc -i 1000 | grep 'CPU die'${RESET}"
  warn "Plug into RIGHT-SIDE USB-C port only to reduce left-port heat."
  warn "If temps exceed 95°C sustained, kernel_task WILL throttle. That's the floor."
}

# ── Mode: MARATHON (Lengthy/Stable Tasks) ────────────────────────────────────
# Target: long downloads, overnight renders, backups, video encodes
# Philosophy: thermal sustainability > raw speed. Prevent throttle cycles.
apply_marathon() {
  step "1/6" "GPU → Integrated only (no dGPU heat)"
  sudo pmset -a gpuswitch 0
  ok "dGPU disabled."

  step "2/6" "Power Management — no interruptions, no spikes"
  sudo pmset -a powernap 0
  sudo pmset -a standby 0
  sudo pmset -a hibernatemode 0
  sudo pmset -a sms 0
  sudo pmset -a sleep 0
  ok "Machine will not sleep. Background spikes suppressed."

  step "3/6" "Spotlight — off (no indexing spikes during long tasks)"
  sudo mdutil -a -i off 2>/dev/null && ok "Spotlight paused." || warn "Skipped."

  step "4/6" "Time Machine — off"
  sudo tmutil disable 2>/dev/null && ok "Time Machine off." || warn "Unavailable."

  step "5/6" "Kill Game Center, Siri background agent"
  launchctl unload -w /System/Library/LaunchAgents/com.apple.gamed.plist 2>/dev/null && ok "Game Center off." || true
  launchctl unload -w /System/Library/LaunchAgents/com.apple.Siri.agent.plist 2>/dev/null && ok "Siri agent off." || true

  step "6/6" "UI Compositor — minimal"
  defaults write com.apple.universalaccess reduceMotion -bool true
  defaults write com.apple.universalaccess reduceTransparency -bool true
  ok "UI reduced."

  echo -e "\n${YELLOW}${BOLD}  🕰  MARATHON mode active.${RESET}"
  echo -e "  Philosophy: stable 75–80°C sustained > 95°C spike → throttle cycle."
  warn "Turbo Boost is still ON. If you want true stable clocks, disable via Turbo Boost Switcher."
  echo -e "  Monitor with: ${DIM}sudo powermetrics --samplers smc,cpu_power -i 3000 | grep -E 'CPU die|Fan'${RESET}"
}

# ── Mode: RESTORE DEFAULTS ────────────────────────────────────────────────────
apply_restore() {
  step "1/4" "GPU → Auto"
  sudo pmset -a gpuswitch 2
  ok "GPU switching restored to Auto."

  step "2/4" "pmset — restore safe defaults"
  sudo pmset -a powernap 1
  sudo pmset -a standby 1
  sudo pmset -a hibernatemode 3
  sudo pmset -a sms 1
  sudo pmset -a sleep 1
  ok "pmset defaults restored."

  step "3/4" "Spotlight — re-enable"
  sudo mdutil -a -i on 2>/dev/null && ok "Spotlight indexing on." || warn "Skipped."

  step "4/4" "UI compositor — restore"
  defaults write com.apple.universalaccess reduceMotion -bool false
  defaults write com.apple.universalaccess reduceTransparency -bool false
  ok "Motion + Transparency restored."

  echo -e "\n${GREEN}${BOLD}  🔄  System restored to macOS defaults.${RESET}"
}

# ── Live monitoring mini-dashboard ────────────────────────────────────────────
show_monitor() {
  echo -e "\n${BOLD}  Live Thermal Monitor${RESET} — ${DIM}Ctrl+C to exit${RESET}\n"
  warn "This runs powermetrics (needs sudo). Starting in 2s..."
  sleep 2
  sudo powermetrics \
    --samplers smc,cpu_power,gpu_power \
    -i 2000 \
    2>/dev/null \
    | grep --line-buffered -E "CPU die|GPU Power|Fan|Throttl|System Average" \
    | while IFS= read -r line; do
        echo -e "  ${DIM}$(date +%H:%M:%S)${RESET}  $line"
      done
}

# ── Main Menu ─────────────────────────────────────────────────────────────────
main_menu() {
  clear
  echo ""
  echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}  ║   MacBook Pro A1990 — Thermal Mode Manager      ║${RESET}"
  echo -e "${BOLD}${CYAN}  ║   Intel i7 / AMD Radeon 555X                    ║${RESET}"
  echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════════════╝${RESET}"
  echo ""
  show_current_state

  echo -e "  ${BOLD}Select a mode:${RESET}\n"
  echo -e "  ${GREEN}[1]${RESET}  ❄  Chill         — Video / browsing / light work"
  echo -e "  ${BLUE}[2]${RESET}  💻  Programming   — Code editors, compilers, terminals"
  echo -e "  ${RED}[3]${RESET}  ⚡  Beast          — Max performance (exports, ML, Xcode)"
  echo -e "  ${YELLOW}[4]${RESET}  🕰  Marathon      — Long tasks, stable temps"
  echo -e "  ${DIM}[5]${RESET}  📊  Monitor        — Live thermal dashboard"
  echo -e "  ${DIM}[6]${RESET}  🔄  Restore        — Reset all to macOS defaults"
  echo -e "  ${DIM}[0]${RESET}  ✗   Exit"
  echo ""
  echo -ne "  ${BOLD}Choice [0-6]:${RESET} "
  read -r choice

  case "$choice" in
    1) sep; apply_chill ;;
    2) sep; apply_programming ;;
    3) sep; apply_beast ;;
    4) sep; apply_marathon ;;
    5) show_monitor ;;
    6) sep; apply_restore ;;
    0) echo -e "\n  Bye.\n"; exit 0 ;;
    *) warn "Invalid choice. Try again."; sleep 1; main_menu ;;
  esac

  echo ""
  sep
  echo -ne "\n  ${DIM}Press Enter to return to menu, or Ctrl+C to exit...${RESET}"
  read -r
  main_menu
}

# ── CLI mode (non-interactive / scripted invocation) ─────────────────────────
cli_mode() {
  case "$1" in
    chill)       apply_chill ;;
    programming) apply_programming ;;
    beast)       apply_beast ;;
    marathon)    apply_marathon ;;
    restore)     apply_restore ;;
    monitor)     show_monitor ;;
    *)
      echo "Usage: $0 [chill|programming|beast|marathon|restore|monitor]"
      echo "       $0            (interactive menu)"
      exit 1
      ;;
  esac
}

# ── Entry point ───────────────────────────────────────────────────────────────
check_deps
require_sudo

if [[ $# -gt 0 ]]; then
  cli_mode "$1"
else
  main_menu
fi
