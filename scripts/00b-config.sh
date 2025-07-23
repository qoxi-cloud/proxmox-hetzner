# shellcheck shell=bash
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
PASSWORD_GENERATED="no"  # Track if password was auto-generated

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
