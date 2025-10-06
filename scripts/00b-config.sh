# shellcheck shell=bash
# =============================================================================
# Config file functions
# =============================================================================

# Validate required configuration variables for non-interactive mode
# Returns: 0 if valid, 1 if missing required variables
validate_config() {
    local has_errors=false

    # Required for non-interactive mode
    if [[ "$NON_INTERACTIVE" == true ]]; then
        # SSH key is critical - must be set
        if [[ -z "$SSH_PUBLIC_KEY" ]]; then
            # Will try to detect from rescue system later, but warn here
            log "WARNING: SSH_PUBLIC_KEY not set in config, will attempt auto-detection"
        fi
    fi

    # Validate values if set
    if [[ -n "$BRIDGE_MODE" ]] && [[ ! "$BRIDGE_MODE" =~ ^(internal|external|both)$ ]]; then
        echo -e "${CLR_RED}Invalid BRIDGE_MODE: $BRIDGE_MODE (must be: internal, external, or both)${CLR_RESET}"
        has_errors=true
    fi

    if [[ -n "$ZFS_RAID" ]] && [[ ! "$ZFS_RAID" =~ ^(single|raid0|raid1)$ ]]; then
        echo -e "${CLR_RED}Invalid ZFS_RAID: $ZFS_RAID (must be: single, raid0, or raid1)${CLR_RESET}"
        has_errors=true
    fi

    if [[ -n "$PVE_REPO_TYPE" ]] && [[ ! "$PVE_REPO_TYPE" =~ ^(no-subscription|enterprise|test)$ ]]; then
        echo -e "${CLR_RED}Invalid PVE_REPO_TYPE: $PVE_REPO_TYPE (must be: no-subscription, enterprise, or test)${CLR_RESET}"
        has_errors=true
    fi

    if [[ -n "$SSL_TYPE" ]] && [[ ! "$SSL_TYPE" =~ ^(self-signed|letsencrypt)$ ]]; then
        echo -e "${CLR_RED}Invalid SSL_TYPE: $SSL_TYPE (must be: self-signed or letsencrypt)${CLR_RESET}"
        has_errors=true
    fi

    if [[ -n "$DEFAULT_SHELL" ]] && [[ ! "$DEFAULT_SHELL" =~ ^(bash|zsh)$ ]]; then
        echo -e "${CLR_RED}Invalid DEFAULT_SHELL: $DEFAULT_SHELL (must be: bash or zsh)${CLR_RESET}"
        has_errors=true
    fi

    if [[ -n "$INSTALL_AUDITD" ]] && [[ ! "$INSTALL_AUDITD" =~ ^(yes|no)$ ]]; then
        echo -e "${CLR_RED}Invalid INSTALL_AUDITD: $INSTALL_AUDITD (must be: yes or no)${CLR_RESET}"
        has_errors=true
    fi

    if [[ "$has_errors" == true ]]; then
        return 1
    fi

    return 0
}

load_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        echo -e "${CLR_GREEN}✓ Loading configuration from: $file${CLR_RESET}"
        # shellcheck source=/dev/null
        source "$file"

        # Validate loaded config
        if ! validate_config; then
            echo -e "${CLR_RED}Configuration validation failed${CLR_RESET}"
            return 1
        fi

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

# Proxmox repository (no-subscription, enterprise, test)
PVE_REPO_TYPE="${PVE_REPO_TYPE}"
PVE_SUBSCRIPTION_KEY="${PVE_SUBSCRIPTION_KEY}"

# SSL certificate (self-signed, letsencrypt)
SSL_TYPE="${SSL_TYPE}"

# Audit logging (yes, no)
INSTALL_AUDITD="${INSTALL_AUDITD}"
EOF
    chmod 600 "$file"
    echo -e "${CLR_GREEN}✓ Configuration saved to: $file${CLR_RESET}"
}

# Load config if specified
if [[ -n "$CONFIG_FILE" ]]; then
    load_config "$CONFIG_FILE" || exit 1
fi
