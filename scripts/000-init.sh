#!/usr/bin/env bash
# Proxmox VE Automated Installer for Hetzner Dedicated Servers
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
readonly CLR_HETZNER=$'\033[38;5;160m'
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
GITHUB_REPO="${GITHUB_REPO:-qoxi-cloud/proxmox-hetzner}"
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

# Password settings
readonly DEFAULT_PASSWORD_LENGTH=16

# QEMU memory settings
readonly QEMU_MIN_RAM_RESERVE=2048

# DNS lookup timeout (seconds)
readonly DNS_LOOKUP_TIMEOUT=5

# Retry delays (seconds)
readonly DNS_RETRY_DELAY=10

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
readonly WIZ_BRIDGE_MODES="External bridge
Internal NAT
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

# CPU governor / power profile options
# shellcheck disable=SC2034
readonly WIZ_CPU_GOVERNORS="Performance
Balanced
Power saving
Adaptive
Conservative"

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
# Uses secure deletion for password files when available.
cleanup_temp_files() {
  # Clean up standard temporary files (including API token file with secrets)
  rm -f /tmp/tailscale_*.txt /tmp/iso_checksum.txt /tmp/*.tmp /tmp/pve-install-api-token.env 2>/dev/null || true

  # Always clean up answer.toml (contains root password)
  rm -f /root/answer.toml 2>/dev/null || true

  # Clean up ISO and installation files (only if installation failed)
  if [[ $INSTALL_COMPLETED != "true" ]]; then
    rm -f /root/pve.iso /root/pve-autoinstall.iso /root/SHA256SUMS 2>/dev/null || true
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

  # Always restore cursor visibility
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

# Start time for total duration tracking
INSTALL_START_TIME=$(date +%s)

# QEMU resource overrides (empty = auto-detect)
QEMU_RAM_OVERRIDE=""
QEMU_CORES_OVERRIDE=""

# Proxmox ISO version (empty = show menu in interactive mode)
PROXMOX_ISO_VERSION=""

# Proxmox repository type (no-subscription, enterprise, test)
PVE_REPO_TYPE=""
PVE_SUBSCRIPTION_KEY=""

# SSL certificate (self-signed, letsencrypt)
SSL_TYPE=""

# Shell type selection (zsh, bash)
SHELL_TYPE=""

# Keyboard layout (default: en-us)
KEYBOARD="en-us"

# Country code (ISO 3166-1 alpha-2, default: us)
COUNTRY="us"

# Locale (derived from country, default: en_US.UTF-8)
LOCALE="en_US.UTF-8"

# Timezone (default: UTC)
TIMEZONE="UTC"

# Fail2Ban installation flag (set by configure_fail2ban)
# shellcheck disable=SC2034
FAIL2BAN_INSTALLED=""

# Auditd installation setting (yes/no, default: no)
INSTALL_AUDITD=""

# AIDE file integrity monitoring (yes/no, default: no)
INSTALL_AIDE=""

# AppArmor installation setting (yes/no, default: no)
INSTALL_APPARMOR=""

# CPU governor setting
CPU_GOVERNOR=""

# ZFS ARC memory allocation strategy (vm-focused, balanced, storage-focused)
ZFS_ARC_MODE=""

# Auditd installation flag (set by configure_auditd)
# shellcheck disable=SC2034
AUDITD_INSTALLED=""

# AIDE installation flag (set by configure_aide)
# shellcheck disable=SC2034
AIDE_INSTALLED=""

# chkrootkit scheduled scanning (yes/no, default: no)
INSTALL_CHKROOTKIT=""

# chkrootkit installation flag (set by configure_chkrootkit)
# shellcheck disable=SC2034
CHKROOTKIT_INSTALLED=""

# Lynis security auditing (yes/no, default: no)
INSTALL_LYNIS=""

# Lynis installation flag (set by configure_lynis)
# shellcheck disable=SC2034
LYNIS_INSTALLED=""

# needrestart automatic service restarts (yes/no, default: no)
INSTALL_NEEDRESTART=""

# needrestart installation flag (set by configure_needrestart)
# shellcheck disable=SC2034
NEEDRESTART_INSTALLED=""

# Netdata real-time monitoring (yes/no, default: no)
INSTALL_NETDATA=""

# Netdata installation flag (set by configure_netdata)
# shellcheck disable=SC2034
NETDATA_INSTALLED=""

# Network ring buffer tuning (yes/no, default: no)
INSTALL_RINGBUFFER=""

# Ring buffer installation flag (set by configure_ringbuffer)
# shellcheck disable=SC2034
RINGBUFFER_INSTALLED=""

# AppArmor installation flag (set by configure_apparmor)
# shellcheck disable=SC2034
APPARMOR_INSTALLED=""

# vnstat bandwidth monitoring setting (yes/no, default: yes)
INSTALL_VNSTAT=""

# vnstat installation flag (set by configure_vnstat)
# shellcheck disable=SC2034
VNSTAT_INSTALLED=""

# Prometheus node exporter installation setting (yes/no, default: no)
INSTALL_PROMETHEUS=""

# Prometheus installation flag (set by configure_prometheus)
# shellcheck disable=SC2034
PROMETHEUS_INSTALLED=""

# Yazi file manager installation setting (yes/no, default: no)
INSTALL_YAZI=""

# Yazi installation flag (set by configure_yazi)
# shellcheck disable=SC2034
YAZI_INSTALLED=""

# Neovim installation setting (yes/no, default: no)
INSTALL_NVIM=""

# Neovim installation flag (set by configure_nvim)
# shellcheck disable=SC2034
NVIM_INSTALLED=""

# Unattended upgrades setting (yes/no, default: yes)
INSTALL_UNATTENDED_UPGRADES=""

# Tailscale VPN settings
INSTALL_TAILSCALE=""
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH=""
TAILSCALE_WEBUI=""
TAILSCALE_DISABLE_SSH=""

# Bridge MTU for private network (default: 9000 jumbo frames)
BRIDGE_MTU=""

# API Token settings
INSTALL_API_TOKEN=""
API_TOKEN_NAME="automation"
API_TOKEN_VALUE=""
API_TOKEN_ID=""

# Firewall settings (nftables)
# INSTALL_FIREWALL: yes/no - whether to enable firewall
# FIREWALL_MODE: stealth/strict/standard
#   - stealth: blocks ALL incoming (only tailscale/bridges allowed)
#   - strict: allows only SSH
#   - standard: allows SSH + Proxmox Web UI (8006)
INSTALL_FIREWALL=""
FIREWALL_MODE=""

# Firewall installation flag (set by configure_firewall)
# shellcheck disable=SC2034
FIREWALL_INSTALLED=""
