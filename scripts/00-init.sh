#!/usr/bin/env bash
set -e
cd /root

# Ensure UTF-8 locale for proper Unicode display (spinner characters)
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# =============================================================================
# Colors and configuration
# =============================================================================
CLR_RED=$'\033[1;31m'
CLR_GREEN=$'\033[1;32m'
CLR_YELLOW=$'\033[1;33m'
CLR_BLUE=$'\033[1;34m'
CLR_CYAN=$'\033[1;36m'
CLR_RESET=$'\033[m'

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
        local error_content="An error occurred and the installation was aborted."$'\n'
        error_content+=$'\n'
        error_content+="Please check the log file for details:"$'\n'
        error_content+="  ${LOG_FILE}"$'\n'
        error_content+=$'\n'
        error_content+="View the last 50 lines with:"$'\n'
        error_content+="  tail -50 ${LOG_FILE}"

        if command -v boxes &>/dev/null; then
            {
                echo "INSTALLATION FAILED"
                echo ""
                echo "$error_content"
            } | boxes -d stone -p a1 -s 60
        else
            echo -e "${CLR_RED}*** INSTALLATION FAILED ***${CLR_RESET}"
            echo ""
            echo -e "${CLR_YELLOW}${error_content}${CLR_RESET}"
        fi
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
