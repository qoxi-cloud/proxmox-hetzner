# shellcheck shell=bash
# =============================================================================
# Config file functions
# =============================================================================

# Validates configuration variables for correctness and completeness.
# Checks format and allowed values for bridge mode, ZFS RAID, repository type, etc.
# In non-interactive mode, ensures all required variables are set.
# Returns: 0 if valid, 1 if validation errors found
validate_config() {
  local has_errors=false

  # Required for non-interactive mode
  if [[ $NON_INTERACTIVE == true ]]; then
    # SSH key is critical - must be set
    if [[ -z $SSH_PUBLIC_KEY ]]; then
      # Will try to detect from rescue system later, but warn here
      log "WARNING: SSH_PUBLIC_KEY not set in config, will attempt auto-detection"
    fi
  fi

  # Validate values if set
  if [[ -n $BRIDGE_MODE ]] && [[ ! $BRIDGE_MODE =~ ^(internal|external|both)$ ]]; then
    echo -e "${CLR_RED}Invalid BRIDGE_MODE: $BRIDGE_MODE (must be: internal, external, or both)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $ZFS_RAID ]] && [[ ! $ZFS_RAID =~ ^(single|raid0|raid1)$ ]]; then
    echo -e "${CLR_RED}Invalid ZFS_RAID: $ZFS_RAID (must be: single, raid0, or raid1)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $PVE_REPO_TYPE ]] && [[ ! $PVE_REPO_TYPE =~ ^(no-subscription|enterprise|test)$ ]]; then
    echo -e "${CLR_RED}Invalid PVE_REPO_TYPE: $PVE_REPO_TYPE (must be: no-subscription, enterprise, or test)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $SSL_TYPE ]] && [[ ! $SSL_TYPE =~ ^(self-signed|letsencrypt)$ ]]; then
    echo -e "${CLR_RED}Invalid SSL_TYPE: $SSL_TYPE (must be: self-signed or letsencrypt)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $DEFAULT_SHELL ]] && [[ ! $DEFAULT_SHELL =~ ^(bash|zsh)$ ]]; then
    echo -e "${CLR_RED}Invalid DEFAULT_SHELL: $DEFAULT_SHELL (must be: bash or zsh)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $INSTALL_AUDITD ]] && [[ ! $INSTALL_AUDITD =~ ^(yes|no)$ ]]; then
    echo -e "${CLR_RED}Invalid INSTALL_AUDITD: $INSTALL_AUDITD (must be: yes or no)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $INSTALL_VNSTAT ]] && [[ ! $INSTALL_VNSTAT =~ ^(yes|no)$ ]]; then
    echo -e "${CLR_RED}Invalid INSTALL_VNSTAT: $INSTALL_VNSTAT (must be: yes or no)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $INSTALL_UNATTENDED_UPGRADES ]] && [[ ! $INSTALL_UNATTENDED_UPGRADES =~ ^(yes|no)$ ]]; then
    echo -e "${CLR_RED}Invalid INSTALL_UNATTENDED_UPGRADES: $INSTALL_UNATTENDED_UPGRADES (must be: yes or no)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $CPU_GOVERNOR ]] && [[ ! $CPU_GOVERNOR =~ ^(performance|ondemand|powersave|schedutil|conservative)$ ]]; then
    echo -e "${CLR_RED}Invalid CPU_GOVERNOR: $CPU_GOVERNOR (must be: performance, ondemand, powersave, schedutil, or conservative)${CLR_RESET}"
    has_errors=true
  fi

  # IPv6 configuration validation
  if [[ -n $IPV6_MODE ]] && [[ ! $IPV6_MODE =~ ^(auto|manual|disabled)$ ]]; then
    echo -e "${CLR_RED}Invalid IPV6_MODE: $IPV6_MODE (must be: auto, manual, or disabled)${CLR_RESET}"
    has_errors=true
  fi

  if [[ -n $IPV6_GATEWAY ]] && [[ $IPV6_GATEWAY != "auto" ]]; then
    if ! validate_ipv6_gateway "$IPV6_GATEWAY"; then
      echo -e "${CLR_RED}Invalid IPV6_GATEWAY: $IPV6_GATEWAY (must be a valid IPv6 address or 'auto')${CLR_RESET}"
      has_errors=true
    fi
  fi

  if [[ -n $IPV6_ADDRESS ]] && ! validate_ipv6_cidr "$IPV6_ADDRESS"; then
    echo -e "${CLR_RED}Invalid IPV6_ADDRESS: $IPV6_ADDRESS (must be valid IPv6 CIDR notation)${CLR_RESET}"
    has_errors=true
  fi

  if [[ $has_errors == true ]]; then
    return 1
  fi

  return 0
}

# Loads configuration from specified file and validates it.
# Sources the config file and runs validation checks.
# Parameters:
#   $1 - Path to configuration file
# Returns: 0 on success, 1 on failure
# Side effects: Sets global configuration variables
load_config() {
  local file="$1"
  if [[ -f $file ]]; then
    echo -e "${CLR_CYAN}✓ Loading configuration from: $file${CLR_RESET}"
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

# Saves current configuration to specified file.
# Writes all configuration variables to file in bash-compatible format.
# Sets file permissions to 600 for security.
# Parameters:
#   $1 - Path to output configuration file
# Side effects: Creates/overwrites configuration file
save_config() {
  local file="$1"
  cat >"$file" <<EOF
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

# Bandwidth monitoring with vnstat (yes, no)
INSTALL_VNSTAT="${INSTALL_VNSTAT}"

# Unattended upgrades for automatic security updates (yes, no)
INSTALL_UNATTENDED_UPGRADES="${INSTALL_UNATTENDED_UPGRADES}"

# CPU governor / power profile (performance, ondemand, powersave, schedutil, conservative)
CPU_GOVERNOR="${CPU_GOVERNOR:-performance}"

# IPv6 configuration (auto, manual, disabled)
IPV6_MODE="${IPV6_MODE:-auto}"
IPV6_GATEWAY="${IPV6_GATEWAY}"
IPV6_ADDRESS="${IPV6_ADDRESS}"
EOF
  chmod 600 "$file"
  echo -e "${CLR_CYAN}✓ Configuration saved to: $file${CLR_RESET}"
}

# Load config if specified
if [[ -n $CONFIG_FILE ]]; then
  load_config "$CONFIG_FILE" || exit 1
fi
