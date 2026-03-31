#!/usr/bin/env bash
# =============================================================================
#  install.sh — Mac Thermal Manager Installer
#  Repo: https://github.com/yadavnikhil17102004/Macbook_Thermal_Configurator
#
#  What this does:
#    1. Downloads thermal_manager.sh to ~/bin/thermal_manager.sh
#    2. Makes it executable
#    3. Adds a `modes` alias to your shell config (~/.zshrc or ~/.bashrc)
#    4. Nothing else. No daemons, no background processes.
#
#  Run with:
#    bash <(curl -fsSL https://raw.githubusercontent.com/yadavnikhil17102004/Macbook_Thermal_Configurator/main/install.sh)
# =============================================================================

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/yadavnikhil17102004/Macbook_Thermal_Configurator/main"
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="thermal_manager.sh"
INSTALL_PATH="$INSTALL_DIR/$SCRIPT_NAME"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

info() { echo -e "  ${CYAN}→${RESET} $*"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()  { echo -e "  ${RED}✗${RESET} $*"; exit 1; }

echo ""
echo -e "${BOLD}${CYAN}  Mac Thermal Manager — Installer${RESET}"
echo -e "  Repo: https://github.com/yadavnikhil17102004/Macbook_Thermal_Configurator"
echo ""

# ── Step 1: Create ~/bin if it doesn't exist ─────────────────────────────────
info "Creating $INSTALL_DIR if needed..."
mkdir -p "$INSTALL_DIR"
ok "$INSTALL_DIR ready."

# ── Step 2: Download the script ───────────────────────────────────────────────
info "Downloading thermal_manager.sh..."
curl -fsSL "$REPO_RAW/$SCRIPT_NAME" -o "$INSTALL_PATH" \
  || err "Download failed. Check your internet connection."
ok "Downloaded to $INSTALL_PATH"

# ── Step 3: Make it executable ────────────────────────────────────────────────
chmod +x "$INSTALL_PATH"
ok "Made executable."

# ── Step 4: Add alias to shell config ────────────────────────────────────────
ALIAS_LINE="alias modes='sudo \"$INSTALL_PATH\"'"
SHELL_CONFIG=""

if [[ "$SHELL" == *"zsh"* ]] || [[ -f "$HOME/.zshrc" ]]; then
  SHELL_CONFIG="$HOME/.zshrc"
elif [[ "$SHELL" == *"bash"* ]] || [[ -f "$HOME/.bash_profile" ]]; then
  SHELL_CONFIG="$HOME/.bash_profile"
else
  SHELL_CONFIG="$HOME/.profile"
fi

if grep -qF "alias modes=" "$SHELL_CONFIG" 2>/dev/null; then
  warn "Alias 'modes' already exists in $SHELL_CONFIG. Skipping."
else
  {
    echo ""
    echo "# Mac Thermal Manager — https://github.com/yadavnikhil17102004/Macbook_Thermal_Configurator"
    echo "$ALIAS_LINE"
  } >> "$SHELL_CONFIG"
  ok "Alias added to $SHELL_CONFIG"
fi

# ── Step 5: Add ~/bin to PATH if not already there ───────────────────────────
if ! echo "$PATH" | grep -q "$HOME/bin"; then
  # Single quotes are intentional: $HOME must expand when the user sources
  # their shell config, not at install time.
  # shellcheck disable=SC2016
  echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_CONFIG"
  ok "Added ~/bin to PATH in $SHELL_CONFIG"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  ✓ Installation complete!${RESET}"
echo ""
echo -e "  Reload your shell config:"
echo -e "    ${CYAN}source $SHELL_CONFIG${RESET}"
echo ""
echo -e "  Then use:"
echo -e "    ${CYAN}modes${RESET}            — interactive menu"
echo -e "    ${CYAN}modes chill${RESET}      — video / light work"
echo -e "    ${CYAN}modes beast${RESET}      — full performance"
echo -e "    ${CYAN}modes restore${RESET}    — reset to defaults"
echo -e "    ${CYAN}modes --help${RESET}     — full usage guide"
echo ""
