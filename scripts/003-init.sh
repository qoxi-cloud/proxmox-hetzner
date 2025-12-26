# shellcheck shell=bash
# Initialization - disk config, log file, runtime variables

# Installation directory (rescue system home, can be overridden)
INSTALL_DIR="${INSTALL_DIR:-${HOME:-/root}}"

# Disk configuration

# Boot disk selection (empty = all disks in pool)
BOOT_DISK=""

# ZFS pool disks (array of paths like "/dev/nvme0n1")
ZFS_POOL_DISKS=()

# Use existing ZFS pool instead of creating new one
# When "yes": import existing pool, preserve all data
# When empty/"no": create new pool (default behavior)
USE_EXISTING_POOL=""
EXISTING_POOL_NAME=""  # Pool name to import (e.g., "tank", "rpool", "data")
EXISTING_POOL_DISKS=() # Disks containing the existing pool (detected or manual)

# System utilities to install on Proxmox
SYSTEM_UTILITIES="btop iotop ncdu tmux pigz smartmontools jq bat fastfetch sysstat nethogs ethtool curl gnupg"
OPTIONAL_PACKAGES="libguestfs-tools"

# Log file
LOG_FILE="${INSTALL_DIR}/pve-install-$(date +%Y%m%d-%H%M%S).log"

# Track if installation completed successfully
INSTALL_COMPLETED=false

# Installation state variables
# These variables track the installation process and timing.
# Set during early initialization, used throughout the installation.

# Start time for total duration tracking (epoch seconds)
# Set: here on script load, used: metrics_finish() in 005-logging.sh
INSTALL_START_TIME=$(date +%s)

# Runtime configuration variables
# These variables are populated by:
#   1. CLI arguments (004-cli.sh) - parsed at startup
#   2. System detection (050-059 scripts) - hardware detection
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
INSTALL_PROMTAIL=""   # Log collector for Loki
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
TAILSCALE_WEBUI=""    # Expose Proxmox UI via Tailscale Serve (yes/no)

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

# --- Proxmox Root Password ---
# Set: Wizard (110-wizard-basic.sh)
# Used: SSH passfile for QEMU VM access, answer.toml for Proxmox installer
NEW_ROOT_PASSWORD="" # Proxmox root password (required, auto-generated if empty)

# --- Admin User ---
# Set: Wizard (115-wizard-ssh.sh)
# Used: 302-configure-admin.sh, sshd_config, API token
# Note: Root SSH is disabled, all access via admin user
ADMIN_USERNAME="" # Non-root admin username (required)
ADMIN_PASSWORD="" # Admin password for sudo/Proxmox UI (required)

# --- Firewall (nftables) ---
# Set: Wizard (114-wizard-services.sh)
# Modes:
#   stealth  - Blocks ALL incoming except Tailscale/bridges
#   strict   - SSH only (port 22)
#   standard - SSH + Proxmox Web UI (ports 22, 8006)
INSTALL_FIREWALL="" # Enable nftables firewall (yes/no)
FIREWALL_MODE=""    # stealth, strict, standard
