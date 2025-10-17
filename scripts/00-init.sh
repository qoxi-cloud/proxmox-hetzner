#!/usr/bin/env bash
# Note: NOT using set -e because it interferes with trap EXIT handler
# All error handling is done explicitly with exit 1
cd /root || exit 1

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
VERSION="1.3.0"

# =============================================================================
# Configuration constants
# =============================================================================

# GitHub repository for template downloads (can be overridden via environment)
GITHUB_REPO="${GITHUB_REPO:-qoxi-cloud/proxmox-hetzner}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_BASE_URL="https://github.com/${GITHUB_REPO}/raw/refs/heads/${GITHUB_BRANCH}"

# Proxmox ISO download URLs
PROXMOX_ISO_BASE_URL="https://enterprise.proxmox.com/iso/"
PROXMOX_CHECKSUM_URL="https://enterprise.proxmox.com/iso/SHA256SUMS"

# DNS servers for connectivity checks and resolution
DNS_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="1.0.0.1"
DNS_TERTIARY="8.8.8.8"
DNS_QUATERNARY="8.8.4.4"

# Resource requirements
MIN_DISK_SPACE_MB=3000
MIN_RAM_MB=4000
MIN_CPU_CORES=2

# QEMU defaults
DEFAULT_QEMU_RAM=8192
MIN_QEMU_RAM=4096
MAX_QEMU_CORES=16
QEMU_LOW_RAM_THRESHOLD=16384

# Download settings
DOWNLOAD_RETRY_COUNT=3
DOWNLOAD_RETRY_DELAY=2

# SSH settings
SSH_READY_TIMEOUT=120
SSH_CONNECT_TIMEOUT=10
QEMU_BOOT_TIMEOUT=300

# Password settings
DEFAULT_PASSWORD_LENGTH=16

# QEMU memory settings
QEMU_MIN_RAM_RESERVE=2048

# DNS lookup timeout (seconds)
DNS_LOOKUP_TIMEOUT=5

# Retry delays (seconds)
DNS_RETRY_DELAY=10

# Default configuration values
DEFAULT_HOSTNAME="pve"
DEFAULT_DOMAIN="local"
DEFAULT_TIMEZONE="Europe/Kyiv"
DEFAULT_EMAIL="admin@example.com"
DEFAULT_BRIDGE_MODE="internal"
DEFAULT_SUBNET="10.0.0.0/24"
DEFAULT_BRIDGE_MTU=9000
DEFAULT_SHELL="zsh"
DEFAULT_REPO_TYPE="no-subscription"
DEFAULT_SSL_TYPE="self-signed"

# System utilities to install on Proxmox
SYSTEM_UTILITIES="btop iotop ncdu tmux pigz smartmontools jq bat fastfetch"
OPTIONAL_PACKAGES="libguestfs-tools"

# Log file
LOG_FILE="/root/pve-install-$(date +%Y%m%d-%H%M%S).log"

# Track if installation completed successfully
INSTALL_COMPLETED=false

# Cleanup temporary files on exit
cleanup_temp_files() {
    # Clean up standard temporary files
    rm -f /tmp/tailscale_*.txt /tmp/iso_checksum.txt /tmp/*.tmp 2>/dev/null || true
    
    # Clean up ISO and installation files (only if installation failed)
    if [[ "$INSTALL_COMPLETED" != "true" ]]; then
        rm -f /root/pve.iso /root/pve-autoinstall.iso /root/answer.toml /root/SHA256SUMS 2>/dev/null || true
        rm -f /root/qemu_*.log 2>/dev/null || true
    fi
    
    # Clean up password files from /dev/shm and /tmp
    find /dev/shm /tmp -name "pve-passfile.*" -type f -delete 2>/dev/null || true
    find /dev/shm /tmp -name "*passfile*" -type f -delete 2>/dev/null || true
}

# Cleanup handler - restore cursor and show error if needed
cleanup_and_error_handler() {
    local exit_code=$?

    # Stop all background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
    sleep 1
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Release drives if QEMU is still running
    if [[ -n "${QEMU_PID:-}" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        log "Cleaning up QEMU process $QEMU_PID"
        # Source release_drives if available (may not be sourced yet)
        if type release_drives &>/dev/null; then
            release_drives
        else
            # Fallback cleanup
            pkill -TERM qemu-system-x86 2>/dev/null || true
            sleep 2
            pkill -9 qemu-system-x86 2>/dev/null || true
        fi
    fi

    # Always restore cursor visibility
    tput cnorm 2>/dev/null || true

    # Show error message if installation failed
    if [[ "$INSTALL_COMPLETED" != "true" && $exit_code -ne 0 ]]; then
        echo ""
        echo -e "${CLR_RED}*** INSTALLATION FAILED ***${CLR_RESET}"
        echo ""
        echo -e "${CLR_YELLOW}An error occurred and the installation was aborted.${CLR_RESET}"
        echo ""
        echo -e "${CLR_YELLOW}Please check the log file for details:${CLR_RESET}"
        echo -e "${CLR_YELLOW}  ${LOG_FILE}${CLR_RESET}"
        echo ""
    fi
}

trap cleanup_and_error_handler EXIT

# Start time for total duration tracking
INSTALL_START_TIME=$(date +%s)

# Default values
NON_INTERACTIVE=false
CONFIG_FILE=""
SAVE_CONFIG=""
TEST_MODE=false
VALIDATE_ONLY=false
DRY_RUN=false

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

# Fail2Ban installation flag (set by configure_fail2ban)
# shellcheck disable=SC2034
FAIL2BAN_INSTALLED=""

# Auditd installation setting (yes/no, default: no)
INSTALL_AUDITD=""

# Auditd installation flag (set by configure_auditd)
# shellcheck disable=SC2034
AUDITD_INSTALLED=""
