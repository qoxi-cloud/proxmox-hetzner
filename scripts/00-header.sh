#!/usr/bin/env bash
set -e
cd /root

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
VERSION="1.2.0"

# Log file
LOG_FILE="/root/pve-install-$(date +%Y%m%d-%H%M%S).log"

# Start time for total duration tracking
INSTALL_START_TIME=$(date +%s)

# Default values
NON_INTERACTIVE=false
CONFIG_FILE=""
SAVE_CONFIG=""
TEST_MODE=false

# =============================================================================
# Command line argument parsing
# =============================================================================
show_help() {
    cat << EOF
Proxmox VE Automated Installer for Hetzner v${VERSION}

Usage: $0 [OPTIONS]

Options:
  -h, --help              Show this help message
  -c, --config FILE       Load configuration from file
  -s, --save-config FILE  Save configuration to file after input
  -n, --non-interactive   Run without prompts (requires --config)
  -t, --test              Test mode (use TCG emulation, no KVM required)
  -v, --version           Show version

Examples:
  $0                           # Interactive installation
  $0 -s proxmox.conf           # Interactive, save config for later
  $0 -c proxmox.conf           # Load config, prompt for missing values
  $0 -c proxmox.conf -n        # Fully automated installation

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--version)
            echo "Proxmox Installer v${VERSION}"
            exit 0
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -s|--save-config)
            SAVE_CONFIG="$2"
            shift 2
            ;;
        -n|--non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        -t|--test)
            TEST_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate non-interactive mode requires config
if [[ "$NON_INTERACTIVE" == true && -z "$CONFIG_FILE" ]]; then
    echo -e "${CLR_RED}Error: --non-interactive requires --config FILE${CLR_RESET}"
    exit 1
fi

# =============================================================================
# Config file functions
# =============================================================================
load_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        echo -e "${CLR_GREEN}✓ Loading configuration from: $file${CLR_RESET}"
        # shellcheck source=/dev/null
        source "$file"
        return 0
    else
        echo -e "${CLR_RED}Config file not found: $file${CLR_RESET}"
        return 1
    fi
}

save_config() {
    local file="$1"
    cat > "$file" << EOF
# Proxmox Installer Configuration
# Generated: $(date)

# Network
INTERFACE_NAME="${INTERFACE_NAME}"

# System
PVE_HOSTNAME="${PVE_HOSTNAME}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX}"
TIMEZONE="${TIMEZONE}"
EMAIL="${EMAIL}"
BRIDGE_MODE="${BRIDGE_MODE}"
PRIVATE_SUBNET="${PRIVATE_SUBNET}"

# Password (consider using environment variable instead)
NEW_ROOT_PASSWORD="${NEW_ROOT_PASSWORD}"

# SSH
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY}"

# Tailscale
INSTALL_TAILSCALE="${INSTALL_TAILSCALE}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY}"
TAILSCALE_SSH="${TAILSCALE_SSH}"
TAILSCALE_WEBUI="${TAILSCALE_WEBUI}"

# ZFS RAID mode (single, raid0, raid1)
ZFS_RAID="${ZFS_RAID}"
EOF
    chmod 600 "$file"
    echo -e "${CLR_GREEN}✓ Configuration saved to: $file${CLR_RESET}"
}

# Load config if specified
if [[ -n "$CONFIG_FILE" ]]; then
    load_config "$CONFIG_FILE" || exit 1
fi

# =============================================================================
# Logging setup
# =============================================================================

# Log silently to file only (not shown to user)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Log debug info (only to file)
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >> "$LOG_FILE"
}

# Log command output to file
log_cmd() {
    local cmd="$1"
    log_debug "Running: $cmd"
    eval "$cmd" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    log_debug "Exit code: $exit_code"
    return $exit_code
}

# Run command silently, log output to file, return exit code
run_logged() {
    log_debug "Executing: $*"
    "$@" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    log_debug "Exit code: $exit_code"
    return $exit_code
}

# =============================================================================
# Cursor management - ensure cursor is always visible on exit
# =============================================================================
cleanup_cursor() {
    tput cnorm 2>/dev/null || true
}
trap cleanup_cursor EXIT INT TERM

clear

# =============================================================================
# ASCII Banner
# =============================================================================
echo -e "${CLR_CYAN}"
cat << 'BANNER'
  ____
 |  _ \ _ __ _____  ___ __ ___   _____  __
 | |_) | '__/ _ \ \/ / '_ ` _ \ / _ \ \/ /
 |  __/| | | (_) >  <| | | | | | (_) >  <
 |_|   |_|  \___/_/\_\_| |_| |_|\___/_/\_\

    Hetzner Automated Installer
BANNER
echo -e "${CLR_RESET}"
echo -e "${CLR_YELLOW}Version: ${VERSION}${CLR_RESET}"
echo -e "${CLR_YELLOW}Log file: ${LOG_FILE}${CLR_RESET}"
if [[ -n "$CONFIG_FILE" ]]; then
    echo -e "${CLR_YELLOW}Config: ${CONFIG_FILE}${CLR_RESET}"
fi
if [[ "$NON_INTERACTIVE" == true ]]; then
    echo -e "${CLR_YELLOW}Mode: Non-interactive${CLR_RESET}"
fi
if [[ "$TEST_MODE" == true ]]; then
    echo -e "${CLR_YELLOW}Mode: Test (TCG emulation, no KVM)${CLR_RESET}"
fi
echo ""
