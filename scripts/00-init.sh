#!/usr/bin/env bash
set -e
cd /root

# Ensure UTF-8 locale for proper Unicode display (spinner characters)
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# =============================================================================
# Colors and configuration
# =============================================================================
CLR_RED="\033[1;31m"
CLR_GREEN="\033[1;32m"
CLR_YELLOW="\033[1;33m"
CLR_BLUE="\033[1;34m"
CLR_CYAN="\033[1;36m"
CLR_RESET="\033[m"

# Version
VERSION="1.2.3"

# Log file
LOG_FILE="/root/pve-install-$(date +%Y%m%d-%H%M%S).log"

# Track if installation completed successfully
INSTALL_COMPLETED=false

# Error handler - show message when script exits unexpectedly
error_handler() {
    local exit_code=$?
    if [[ "$INSTALL_COMPLETED" != "true" && $exit_code -ne 0 ]]; then
        echo ""
        echo -e "${CLR_RED}╔════════════════════════════════════════════════════════════╗${CLR_RESET}"
        echo -e "${CLR_RED}║                    INSTALLATION FAILED                     ║${CLR_RESET}"
        echo -e "${CLR_RED}╚════════════════════════════════════════════════════════════╝${CLR_RESET}"
        echo ""
        echo -e "${CLR_YELLOW}An error occurred and the installation was aborted.${CLR_RESET}"
        echo -e "${CLR_YELLOW}Please check the log file for details:${CLR_RESET}"
        echo ""
        echo -e "  ${CLR_CYAN}${LOG_FILE}${CLR_RESET}"
        echo ""
        echo -e "${CLR_YELLOW}You can view the last 50 lines with:${CLR_RESET}"
        echo -e "  ${CLR_CYAN}tail -50 ${LOG_FILE}${CLR_RESET}"
        echo ""
    fi
}

trap error_handler EXIT

# Start time for total duration tracking
INSTALL_START_TIME=$(date +%s)

# Default values
NON_INTERACTIVE=false
CONFIG_FILE=""
SAVE_CONFIG=""
TEST_MODE=false
VALIDATE_ONLY=false

# QEMU resource overrides (empty = auto-detect)
QEMU_RAM_OVERRIDE=""
QEMU_CORES_OVERRIDE=""

# Proxmox ISO version (empty = show menu in interactive, use latest in non-interactive)
PROXMOX_ISO_VERSION=""

# Proxmox repository type (no-subscription, enterprise, test)
PVE_REPO_TYPE=""
PVE_SUBSCRIPTION_KEY=""

# SSL certificate (self-signed, letsencrypt)
SSL_TYPE=""
