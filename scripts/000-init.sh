#!/usr/bin/env bash
# Qoxi - Proxmox VE Automated Installer for Dedicated Servers
# Note: NOT using set -e because it interferes with trap EXIT handler
# All error handling is done explicitly with exit 1
cd /root || exit 1

# Ensure UTF-8 locale for proper Unicode display
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# =============================================================================
# Colors and configuration
# =============================================================================
readonly CLR_RED=$'\033[1;31m'
readonly CLR_CYAN=$'\033[38;2;0;177;255m'
readonly CLR_YELLOW=$'\033[1;33m'
readonly CLR_ORANGE=$'\033[38;5;208m'
readonly CLR_GRAY=$'\033[38;5;240m'
readonly CLR_GOLD=$'\033[38;5;179m'
readonly CLR_RESET=$'\033[m'

# Hex colors for gum (terminal UI toolkit)
readonly HEX_RED="#ff0000"
readonly HEX_CYAN="#00b1ff"
readonly HEX_YELLOW="#ffff00"
readonly HEX_ORANGE="#ff8700"
readonly HEX_GRAY="#585858"
readonly HEX_WHITE="#ffffff"
readonly HEX_NONE="7"

# Version (MAJOR only - MINOR.PATCH added by CI from git tags/commits)
readonly VERSION="2"

# =============================================================================
# Configuration constants
# =============================================================================

# GitHub repository for template downloads (can be overridden via environment)
GITHUB_REPO="${GITHUB_REPO:-qoxi-cloud/proxmox-installer}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_BASE_URL="https://github.com/${GITHUB_REPO}/raw/refs/heads/${GITHUB_BRANCH}"

# Proxmox ISO download URLs
readonly PROXMOX_ISO_BASE_URL="https://enterprise.proxmox.com/iso/"
readonly PROXMOX_CHECKSUM_URL="https://enterprise.proxmox.com/iso/SHA256SUMS"

# DNS servers for connectivity checks and resolution (IPv4)
readonly DNS_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
readonly DNS_PRIMARY="1.1.1.1"
readonly DNS_SECONDARY="1.0.0.1"

# DNS servers (IPv6) - Cloudflare
readonly DNS6_PRIMARY="2606:4700:4700::1111"
readonly DNS6_SECONDARY="2606:4700:4700::1001"

# Resource requirements (ISO ~3.5GB + QEMU + overhead = 6GB)
readonly MIN_DISK_SPACE_MB=6000
readonly MIN_RAM_MB=4000
readonly MIN_CPU_CORES=2

# QEMU defaults
readonly MIN_QEMU_RAM=4096

# Download settings
readonly DOWNLOAD_RETRY_COUNT=3
readonly DOWNLOAD_RETRY_DELAY=2

# SSH settings
readonly SSH_CONNECT_TIMEOUT=10

# Ports configuration
readonly SSH_PORT_QEMU=5555        # SSH port for QEMU VM (installer-internal)
readonly PORT_SSH=22               # Standard SSH port for firewall rules
readonly PORT_PROXMOX_UI=8006      # Proxmox Web UI port
readonly PORT_NETDATA=19999        # Netdata monitoring dashboard
readonly PORT_PROMETHEUS_NODE=9100 # Prometheus node exporter

# Password settings
readonly DEFAULT_PASSWORD_LENGTH=16

# QEMU memory settings
readonly QEMU_MIN_RAM_RESERVE=2048

# DNS lookup timeout (seconds)
readonly DNS_LOOKUP_TIMEOUT=5

# Retry delays (seconds)
readonly DNS_RETRY_DELAY=10

# QEMU boot timeouts (seconds)
readonly QEMU_BOOT_TIMEOUT=300      # Max wait for QEMU to boot and expose SSH port
readonly QEMU_PORT_CHECK_INTERVAL=3 # Interval between port availability checks
readonly QEMU_SSH_READY_TIMEOUT=120 # Max wait for SSH to be fully ready

# Keyboard layouts supported by Proxmox installer (from official documentation)
# shellcheck disable=SC2034
readonly WIZ_KEYBOARD_LAYOUTS="de
de-ch
dk
en-gb
en-us
es
fi
fr
fr-be
fr-ca
fr-ch
hu
is
it
jp
lt
mk
nl
no
pl
pt
pt-br
se
si
tr"

# =============================================================================
# Wizard menu option lists (WIZ_ prefix to avoid conflicts)
# =============================================================================

# Proxmox repository types
# shellcheck disable=SC2034
readonly WIZ_REPO_TYPES="No-subscription (free)
Enterprise
Test/Development"

# Network bridge modes
# shellcheck disable=SC2034
readonly WIZ_BRIDGE_MODES="Internal NAT
External bridge
Both"

# Bridge MTU options
# shellcheck disable=SC2034
readonly WIZ_BRIDGE_MTU="9000 (jumbo frames)
1500 (standard)"

# IPv6 configuration modes
# shellcheck disable=SC2034
readonly WIZ_IPV6_MODES="Auto
Manual
Disabled"

# Private subnet presets
# shellcheck disable=SC2034
readonly WIZ_PRIVATE_SUBNETS="10.0.0.0/24
192.168.1.0/24
172.16.0.0/24
Custom"

# ZFS RAID levels (base options, raid5/raid10 added dynamically based on drive count)
# shellcheck disable=SC2034
readonly WIZ_ZFS_MODES="Single disk
RAID-1 (mirror)"

# ZFS ARC memory allocation strategies
# shellcheck disable=SC2034
readonly WIZ_ZFS_ARC_MODES="VM-focused (4GB fixed)
Balanced (25-40% of RAM)
Storage-focused (50% of RAM)"

# SSL certificate types
# shellcheck disable=SC2034
readonly WIZ_SSL_TYPES="Self-signed
Let's Encrypt"

# Shell options
# shellcheck disable=SC2034
readonly WIZ_SHELL_OPTIONS="ZSH
Bash"

# Firewall modes (nftables)
# shellcheck disable=SC2034
readonly WIZ_FIREWALL_MODES="Stealth (Tailscale only)
Strict (SSH only)
Standard (SSH + Web UI)
Disabled"

# =============================================================================
# Disk configuration
# =============================================================================

# Boot disk selection (empty = all disks in pool)
BOOT_DISK=""

# ZFS pool disks (array of paths like "/dev/nvme0n1")
ZFS_POOL_DISKS=()

# System utilities to install on Proxmox
SYSTEM_UTILITIES="btop iotop ncdu tmux pigz smartmontools jq bat fastfetch sysstat nethogs ethtool"
OPTIONAL_PACKAGES="libguestfs-tools" # prometheus-node-exporter moved to wizard features

# Log file
LOG_FILE="/root/pve-install-$(date +%Y%m%d-%H%M%S).log"

# Track if installation completed successfully
INSTALL_COMPLETED=false

# Cleans up temporary files created during installation.
# Removes ISO files, password files, logs, and other temporary artifacts.
# Behavior depends on INSTALL_COMPLETED flag - preserves files if installation succeeded.
# Uses secure deletion for files containing secrets.
cleanup_temp_files() {
  # Secure delete files containing secrets (API token, root password)
  # secure_delete_file is defined in 012-utils.sh, check if available
  if type secure_delete_file &>/dev/null; then
    secure_delete_file /tmp/pve-install-api-token.env
    secure_delete_file /root/answer.toml
    # Secure delete password files from /dev/shm and /tmp
    while IFS= read -r -d '' pfile; do
      secure_delete_file "$pfile"
    done < <(find /dev/shm /tmp -name "pve-passfile.*" -type f -print0 2>/dev/null || true)
    while IFS= read -r -d '' pfile; do
      secure_delete_file "$pfile"
    done < <(find /dev/shm /tmp -name "*passfile*" -type f -print0 2>/dev/null || true)
  else
    # Fallback if secure_delete_file not yet loaded (early exit)
    rm -f /tmp/pve-install-api-token.env 2>/dev/null || true
    rm -f /root/answer.toml 2>/dev/null || true
    find /dev/shm /tmp -name "pve-passfile.*" -type f -delete 2>/dev/null || true
    find /dev/shm /tmp -name "*passfile*" -type f -delete 2>/dev/null || true
  fi

  # Clean up standard temporary files (non-sensitive)
  rm -f /tmp/tailscale_*.txt /tmp/iso_checksum.txt /tmp/*.tmp 2>/dev/null || true

  # Clean up ISO and installation files (only if installation failed)
  if [[ $INSTALL_COMPLETED != "true" ]]; then
    rm -f /root/pve.iso /root/pve-autoinstall.iso /root/SHA256SUMS 2>/dev/null || true
    rm -f /root/qemu_*.log 2>/dev/null || true
  fi
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
  if [[ -n ${QEMU_PID:-} ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
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

  # Exit alternate screen buffer and restore cursor visibility
  tput rmcup 2>/dev/null || true
  tput cnorm 2>/dev/null || true

  # Show error message if installation failed
  if [[ $INSTALL_COMPLETED != "true" && $exit_code -ne 0 ]]; then
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

# =============================================================================
# Installation state variables
# =============================================================================
# These variables track the installation process and timing.
# Set during early initialization, used throughout the installation.

# Start time for total duration tracking (epoch seconds)
# Set: here on script load, used: metrics_finish() in 002-logging.sh
INSTALL_START_TIME=$(date +%s)

# =============================================================================
# Runtime configuration variables
# =============================================================================
# These variables are populated by:
#   1. CLI arguments (001-cli.sh) - parsed at startup
#   2. System detection (041-system-check.sh) - hardware detection
#   3. Wizard UI (100-wizard.sh) - user input
#   4. answer.toml (200-packages.sh) - passed to Proxmox installer
#
# Lifecycle:
#   CLI args → System detection → Wizard UI → answer.toml → Configuration
#
# Empty string = not set, will use default or prompt user

# --- QEMU Settings ---
# Set: CLI args (-r, -c) or auto-detected in 201-qemu.sh
QEMU_RAM_OVERRIDE=""   # Override RAM allocation (MB)
QEMU_CORES_OVERRIDE="" # Override CPU core count

# --- Proxmox Settings ---
# Set: CLI args (-v) or wizard (111-wizard-proxmox.sh)
PROXMOX_ISO_VERSION=""  # ISO version (empty = show menu)
PVE_REPO_TYPE=""        # no-subscription, enterprise, test
PVE_SUBSCRIPTION_KEY="" # Enterprise subscription key

# --- System Settings ---
# Set: Wizard (110-wizard-basic.sh, 114-wizard-services.sh)
SSL_TYPE=""   # self-signed, letsencrypt
SHELL_TYPE="" # zsh, bash

# --- Locale Settings ---
# Set: CLI args or wizard (110-wizard-basic.sh)
# Used: answer.toml generation, system configuration
KEYBOARD="en-us"     # Keyboard layout (see WIZ_KEYBOARD_LAYOUTS)
COUNTRY="us"         # ISO 3166-1 alpha-2 country code
LOCALE="en_US.UTF-8" # System locale (derived from country)
TIMEZONE="UTC"       # System timezone

# --- Performance Settings ---
# Set: Wizard (114-wizard-services.sh)
CPU_GOVERNOR="" # CPU frequency governor (performance, powersave, etc.)
ZFS_ARC_MODE="" # ZFS ARC strategy: vm-focused, balanced, storage-focused

# --- Security Features ---
# Set: Wizard (114-wizard-services.sh), default: "no"
# Used: batch_install_packages(), parallel config groups
INSTALL_AUDITD=""      # Kernel audit logging
INSTALL_AIDE=""        # File integrity monitoring (daily checks)
INSTALL_APPARMOR=""    # Mandatory access control
INSTALL_CHKROOTKIT=""  # Rootkit detection (weekly scans)
INSTALL_LYNIS=""       # Security auditing tool
INSTALL_NEEDRESTART="" # Auto-restart services after updates

# --- Monitoring Features ---
# Set: Wizard (114-wizard-services.sh), default: "no" except VNSTAT
INSTALL_NETDATA=""    # Real-time web dashboard (port 19999)
INSTALL_VNSTAT=""     # Bandwidth monitoring (default: yes)
INSTALL_PROMETHEUS="" # Node exporter for Prometheus (port 9100)
INSTALL_RINGBUFFER="" # Network ring buffer tuning for high throughput

# --- Optional Tools ---
# Set: Wizard (114-wizard-services.sh), default: "no"
INSTALL_YAZI="" # Terminal file manager
INSTALL_NVIM="" # Neovim editor with config

# --- System Maintenance ---
# Set: Wizard (114-wizard-services.sh), default: "yes"
INSTALL_UNATTENDED_UPGRADES="" # Automatic security updates

# --- Tailscale VPN ---
# Set: Wizard (114-wizard-services.sh)
INSTALL_TAILSCALE=""  # Enable Tailscale VPN
TAILSCALE_AUTH_KEY="" # Pre-auth key for automatic login
TAILSCALE_SSH=""      # Enable Tailscale SSH (yes/no)
TAILSCALE_WEBUI=""    # Expose Proxmox UI via Tailscale (yes/no)

# --- Network Settings ---
# Set: Wizard (112-wizard-network.sh)
BRIDGE_MTU="" # Bridge MTU: 9000 (jumbo) or 1500 (standard)

# --- API Token ---
# Set: Wizard (114-wizard-services.sh)
# Used: create_api_token() in 361-configure-api-token.sh
INSTALL_API_TOKEN=""        # Create automation API token
API_TOKEN_NAME="automation" # Token name (default: automation)
API_TOKEN_VALUE=""          # Generated token value (set post-install)
API_TOKEN_ID=""             # Full token ID (user@pam!tokenname)

# --- Firewall (nftables) ---
# Set: Wizard (114-wizard-services.sh)
# Modes:
#   stealth  - Blocks ALL incoming except Tailscale/bridges
#   strict   - SSH only (port 22)
#   standard - SSH + Proxmox Web UI (ports 22, 8006)
INSTALL_FIREWALL="" # Enable nftables firewall (yes/no)
FIREWALL_MODE=""    # stealth, strict, standard
