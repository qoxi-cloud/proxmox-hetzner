# shellcheck shell=bash
# =============================================================================
# Non-interactive input collection
# =============================================================================

# Helper to return existing value or default based on interactive mode.
# Parameters:
#   $1 - Prompt text (unused in non-interactive mode)
#   $2 - Default value
#   $3 - Variable name to check
# Returns: Current value or default via stdout
prompt_or_default() {
  local prompt="$1"
  local default="$2"
  local var_name="$3"
  local current_value="${!var_name}"

  if [[ $NON_INTERACTIVE == true ]]; then
    if [[ -n $current_value ]]; then
      echo "$current_value"
    else
      echo "$default"
    fi
  else
    local result
    read -r -e -p "$prompt" -i "${current_value:-$default}" result
    echo "$result"
  fi
}

# =============================================================================
# Input collection - Non-interactive mode
# =============================================================================

# Collects all inputs from environment/config in non-interactive mode.
# Uses default values where config values are not provided.
# Validates required fields (SSH key).
# Side effects: Sets all configuration global variables
get_inputs_non_interactive() {
  # Use defaults or config values (referencing global constants)
  PVE_HOSTNAME="${PVE_HOSTNAME:-$DEFAULT_HOSTNAME}"
  DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-$DEFAULT_DOMAIN}"
  TIMEZONE="${TIMEZONE:-$DEFAULT_TIMEZONE}"
  EMAIL="${EMAIL:-$DEFAULT_EMAIL}"
  BRIDGE_MODE="${BRIDGE_MODE:-$DEFAULT_BRIDGE_MODE}"
  PRIVATE_SUBNET="${PRIVATE_SUBNET:-$DEFAULT_SUBNET}"
  DEFAULT_SHELL="${DEFAULT_SHELL:-zsh}"
  CPU_GOVERNOR="${CPU_GOVERNOR:-$DEFAULT_CPU_GOVERNOR}"

  # IPv6 configuration
  IPV6_MODE="${IPV6_MODE:-$DEFAULT_IPV6_MODE}"
  if [[ $IPV6_MODE == "disabled" ]]; then
    # Clear IPv6 settings when disabled
    MAIN_IPV6=""
    IPV6_GATEWAY=""
    FIRST_IPV6_CIDR=""
  elif [[ $IPV6_MODE == "manual" ]]; then
    # Use manually specified values
    IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
    if [[ -n $IPV6_ADDRESS ]]; then
      MAIN_IPV6="${IPV6_ADDRESS%/*}"
    fi
  else
    # auto mode: use detected values, set gateway to default if not specified
    IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
  fi

  # Display configuration
  print_success "Network interface:" "${INTERFACE_NAME}"
  print_success "Hostname:" "${PVE_HOSTNAME}"
  print_success "Domain:" "${DOMAIN_SUFFIX}"
  print_success "Timezone:" "${TIMEZONE}"
  print_success "Email:" "${EMAIL}"
  print_success "Bridge mode:" "${BRIDGE_MODE}"

  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    print_success "Private subnet:" "${PRIVATE_SUBNET}"
  fi
  print_success "Default shell:" "${DEFAULT_SHELL}"
  print_success "Power profile:" "${CPU_GOVERNOR}"

  # Display IPv6 configuration
  if [[ $IPV6_MODE == "disabled" ]]; then
    print_success "IPv6:" "disabled"
  elif [[ -n $MAIN_IPV6 ]]; then
    print_success "IPv6:" "${MAIN_IPV6} (gateway: ${IPV6_GATEWAY})"
  else
    print_warning "IPv6: not detected"
  fi

  # ZFS RAID mode
  if [[ -z $ZFS_RAID ]]; then
    if [[ ${DRIVE_COUNT:-0} -ge 2 ]]; then
      ZFS_RAID="raid1"
    else
      ZFS_RAID="single"
    fi
  fi
  print_success "ZFS mode:" "${ZFS_RAID}"

  # Password - generate if not provided
  if [[ -z $NEW_ROOT_PASSWORD ]]; then
    NEW_ROOT_PASSWORD=$(generate_password 16)
    PASSWORD_GENERATED="yes"
    print_success "Password:" "auto-generated (will be shown at the end)"
  else
    if ! validate_password_with_error "$NEW_ROOT_PASSWORD"; then
      exit 1
    fi
    print_success "Password:" "******** (from env)"
  fi

  # SSH Public Key
  if [[ -z $SSH_PUBLIC_KEY ]]; then
    SSH_PUBLIC_KEY=$(get_rescue_ssh_key)
  fi
  if [[ -z $SSH_PUBLIC_KEY ]]; then
    print_error "SSH_PUBLIC_KEY required in non-interactive mode"
    exit 1
  fi
  parse_ssh_key "$SSH_PUBLIC_KEY"
  print_success "SSH key:" "configured (${SSH_KEY_TYPE})"

  # Proxmox repository
  PVE_REPO_TYPE="${PVE_REPO_TYPE:-no-subscription}"
  print_success "Repository:" "${PVE_REPO_TYPE}"
  if [[ $PVE_REPO_TYPE == "enterprise" && -n $PVE_SUBSCRIPTION_KEY ]]; then
    print_success "Subscription key:" "configured"
  fi

  # SSL certificate
  SSL_TYPE="${SSL_TYPE:-self-signed}"
  if [[ $SSL_TYPE == "letsencrypt" ]]; then
    local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
    local expected_ip="${MAIN_IPV4_CIDR%/*}"

    validate_dns_resolution "$le_fqdn" "$expected_ip"
    local dns_result=$?

    case $dns_result in
      0)
        print_success "SSL certificate:" "letsencrypt (DNS verified: ${le_fqdn} → ${expected_ip})"
        ;;
      1)
        log "ERROR: DNS validation failed - ${le_fqdn} does not resolve"
        print_error "SSL certificate: letsencrypt (DNS FAILED)"
        print_error "${le_fqdn} does not resolve"
        echo ""
        print_info "Let's Encrypt requires valid DNS configuration."
        print_info "Create DNS A record: ${le_fqdn} → ${expected_ip}"
        exit 1
        ;;
      2)
        log "ERROR: DNS validation failed - ${le_fqdn} resolves to ${DNS_RESOLVED_IP}, expected ${expected_ip}"
        print_error "SSL certificate: letsencrypt (DNS MISMATCH)"
        print_error "${le_fqdn} resolves to ${DNS_RESOLVED_IP}, expected ${expected_ip}"
        echo ""
        print_info "Update DNS A record: ${le_fqdn} → ${expected_ip}"
        exit 1
        ;;
    esac
  else
    print_success "SSL certificate:" "${SSL_TYPE}"
  fi

  # Audit logging (auditd)
  INSTALL_AUDITD="${INSTALL_AUDITD:-no}"
  if [[ $INSTALL_AUDITD == "yes" ]]; then
    print_success "Audit logging:" "enabled"
  else
    print_success "Audit logging:" "disabled"
  fi

  # Bandwidth monitoring (vnstat)
  INSTALL_VNSTAT="${INSTALL_VNSTAT:-yes}"
  if [[ $INSTALL_VNSTAT == "yes" ]]; then
    print_success "Bandwidth monitoring:" "enabled (vnstat)"
  else
    print_success "Bandwidth monitoring:" "disabled"
  fi

  # Unattended upgrades
  INSTALL_UNATTENDED_UPGRADES="${INSTALL_UNATTENDED_UPGRADES:-yes}"
  if [[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]]; then
    print_success "Auto security updates:" "enabled"
  else
    print_success "Auto security updates:" "disabled"
  fi

  # Tailscale
  INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-no}"
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    TAILSCALE_SSH="${TAILSCALE_SSH:-yes}"
    TAILSCALE_WEBUI="${TAILSCALE_WEBUI:-yes}"
    TAILSCALE_DISABLE_SSH="${TAILSCALE_DISABLE_SSH:-no}"
    if [[ -n $TAILSCALE_AUTH_KEY ]]; then
      print_success "Tailscale:" "will be installed (auto-connect)"
    else
      print_success "Tailscale:" "will be installed (manual auth required)"
    fi
    print_success "Tailscale SSH:" "${TAILSCALE_SSH}"
    print_success "Tailscale WebUI:" "${TAILSCALE_WEBUI}"
    if [[ $TAILSCALE_SSH == "yes" && $TAILSCALE_DISABLE_SSH == "yes" ]]; then
      print_success "OpenSSH:" "will be disabled on first boot"
      # Enable stealth mode when OpenSSH is disabled
      STEALTH_MODE="${STEALTH_MODE:-yes}"
      if [[ $STEALTH_MODE == "yes" ]]; then
        print_success "Stealth firewall:" "enabled"
      fi
    else
      STEALTH_MODE="${STEALTH_MODE:-no}"
    fi
  else
    STEALTH_MODE="${STEALTH_MODE:-no}"
    print_success "Tailscale:" "skipped"
  fi
}
