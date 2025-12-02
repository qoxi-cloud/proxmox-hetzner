#!/usr/bin/env bash
# Proxmox VE Automated Installer for Hetzner Dedicated Servers
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
CLR_CYAN=$'\033[38;2;0;177;255m'
CLR_YELLOW=$'\033[1;33m'
CLR_ORANGE=$'\033[38;5;208m'
CLR_GRAY=$'\033[38;5;240m'
CLR_HETZNER=$'\033[38;5;160m'
CLR_RESET=$'\033[m'

# Spinner characters for progress display (filling circle animation)
# shellcheck disable=SC2034
SPINNER_CHARS=('○' '◔' '◑' '◕' '●' '◕' '◑' '◔')

# Disables all color output variables by setting them to empty strings.
# Called when --no-color flag is used to ensure accessible terminal output.
disable_colors() {
    CLR_RED=''
    CLR_CYAN=''
    CLR_YELLOW=''
    CLR_ORANGE=''
    CLR_GRAY=''
    CLR_HETZNER=''
    CLR_RESET=''
}

# Version (MAJOR only - MINOR.PATCH added by CI from git tags/commits)
VERSION="1"

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

# DNS servers for connectivity checks and resolution (IPv4)
DNS_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="1.0.0.1"
DNS_TERTIARY="8.8.8.8"
DNS_QUATERNARY="8.8.4.4"

# DNS servers (IPv6) - Cloudflare, Google, Quad9
DNS6_PRIMARY="2606:4700:4700::1111"
DNS6_SECONDARY="2606:4700:4700::1001"
DNS6_TERTIARY="2001:4860:4860::8888"
DNS6_QUATERNARY="2001:4860:4860::8844"

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
DEFAULT_SHELL=""
DEFAULT_REPO_TYPE="no-subscription"
DEFAULT_SSL_TYPE="self-signed"

# CPU governor / power profile
# Options: performance, ondemand, powersave, schedutil, conservative
DEFAULT_CPU_GOVERNOR="performance"

# IPv6 configuration defaults
# IPV6_MODE: auto (detect from interface), manual (user-specified), disabled
DEFAULT_IPV6_MODE="auto"
# Default gateway for IPv6 (fe80::1 is standard for Hetzner)
DEFAULT_IPV6_GATEWAY="fe80::1"
# VM subnet prefix length (80 allows 65536 /96 subnets within a /64)
DEFAULT_IPV6_VM_PREFIX=80

# System utilities to install on Proxmox
SYSTEM_UTILITIES="btop iotop ncdu tmux pigz smartmontools jq bat fastfetch"
OPTIONAL_PACKAGES="libguestfs-tools"

# Log file
LOG_FILE="/root/pve-install-$(date +%Y%m%d-%H%M%S).log"

# Track if installation completed successfully
INSTALL_COMPLETED=false

# Cleans up temporary files created during installation.
# Removes ISO files, password files, logs, and other temporary artifacts.
# Behavior depends on INSTALL_COMPLETED flag - preserves files if installation succeeded.
# Uses secure deletion for password files when available.
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

# Cleanup handler invoked on script exit via trap.
# Performs graceful shutdown of background processes, drive cleanup, cursor restoration.
# Displays error message if installation failed (INSTALL_COMPLETED != true).
# Returns: Exit code from the script
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

# CPU governor setting
CPU_GOVERNOR=""

# Auditd installation flag (set by configure_auditd)
# shellcheck disable=SC2034
AUDITD_INSTALLED=""

# vnstat bandwidth monitoring setting (yes/no, default: yes)
INSTALL_VNSTAT=""

# vnstat installation flag (set by configure_vnstat)
# shellcheck disable=SC2034
VNSTAT_INSTALLED=""

# Unattended upgrades setting (yes/no, default: yes)
INSTALL_UNATTENDED_UPGRADES=""
