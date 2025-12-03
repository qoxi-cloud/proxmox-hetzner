# shellcheck shell=bash
# =============================================================================
# Interactive input collection
# =============================================================================

# Collects all inputs through interactive prompts and menus.
# Handles: hostname, domain, email, password, timezone, network, storage,
# Proxmox options, SSL, Tailscale, SSH.
# Validates inputs and provides user-friendly error messages.
# Side effects: Sets all configuration global variables
get_inputs_interactive() {
  # =========================================================================
  # SECTION 1: Text inputs
  # =========================================================================

  # Network interface
  print_warning "Use the predictable name (enp*, eno*) for bare metal, not eth0"
  local iface_prompt="Interface name (options: ${AVAILABLE_ALTNAMES}): "
  read -r -e -p "$iface_prompt" -i "$INTERFACE_NAME" INTERFACE_NAME
  # Clear detection message, warning, and input line (4 lines up), then show success
  printf "\033[4A\033[J"
  print_success "Interface:" "${INTERFACE_NAME}"

  # Hostname
  if [[ -n $PVE_HOSTNAME ]]; then
    print_success "Hostname:" "${PVE_HOSTNAME} (from env)"
  else
    prompt_with_validation \
      "Enter your hostname (e.g., pve, proxmox): " \
      "pve" \
      "validate_hostname" \
      "Invalid hostname. Use only letters, numbers, and hyphens (1-63 chars)." \
      "PVE_HOSTNAME" \
      "Hostname: "
  fi

  # Domain
  if [[ -n $DOMAIN_SUFFIX ]]; then
    print_success "Domain:" "${DOMAIN_SUFFIX} (from env)"
  else
    local domain_prompt="Enter domain suffix: "
    read -r -e -p "$domain_prompt" -i "local" DOMAIN_SUFFIX
    printf "\033[A\033[2K"
    print_success "Domain:" "${DOMAIN_SUFFIX}"
  fi

  # Email
  if [[ -n $EMAIL ]]; then
    print_success "Email:" "${EMAIL} (from env)"
  else
    prompt_with_validation \
      "Enter your email address: " \
      "admin@qoxi.cloud" \
      "validate_email" \
      "Invalid email address format." \
      "EMAIL" \
      "Email: "
  fi

  # Password
  if [[ -n $NEW_ROOT_PASSWORD ]]; then
    if ! validate_password_with_error "$NEW_ROOT_PASSWORD"; then
      exit 1
    fi
    print_success "Password:" "******** (from env)"
  else
    echo -n "Enter root password (or press Enter to auto-generate): "
    local input_password
    local password_error
    input_password=$(read_password "")
    # Move cursor up twice (read_password adds a newline) and clear
    printf "\033[A\033[A\r\033[K"
    if [[ -z $input_password ]]; then
      NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
      PASSWORD_GENERATED="yes"
      print_success "Password:" "auto-generated (will be shown at the end)"
    else
      password_error=$(get_password_error "$input_password")
      while [[ -n $password_error ]]; do
        print_error "$password_error"
        input_password=$(read_password "Enter root password: ")
        password_error=$(get_password_error "$input_password")
      done
      NEW_ROOT_PASSWORD="$input_password"
      # Clear the password input line
      printf "\033[A\r\033[K"
      print_success "Password:" "********"
    fi
  fi

  # =========================================================================
  # SECTION 2: Interactive menus
  # =========================================================================

  # --- Proxmox ISO Version ---
  if [[ -n $PROXMOX_ISO_VERSION ]]; then
    print_success "Proxmox ISO:" "${PROXMOX_ISO_VERSION} (from env/cli)"
  else
    # Fetch available ISO versions
    local iso_list
    get_available_proxmox_isos 5 >/tmp/iso_list.tmp &
    show_progress $! "Fetching available Proxmox versions" --silent
    iso_list=$(cat /tmp/iso_list.tmp 2>/dev/null)
    rm -f /tmp/iso_list.tmp

    if [[ -z $iso_list ]]; then
      print_warning "Could not fetch ISO list, will use latest"
      PROXMOX_ISO_VERSION=""
    else
      # Convert to array
      local -a iso_array
      local -a iso_menu_items
      local first=true
      while IFS= read -r iso; do
        iso_array+=("$iso")
        local version
        version=$(get_iso_version "$iso")
        if [[ $first == true ]]; then
          iso_menu_items+=("Proxmox VE ${version}|Latest version (recommended)")
          first=false
        else
          iso_menu_items+=("Proxmox VE ${version}|")
        fi
      done <<<"$iso_list"

      radio_menu \
        "Proxmox VE Version (↑/↓ select, Enter confirm)" \
        "Select which Proxmox VE version to install"$'\n' \
        "${iso_menu_items[@]}"

      PROXMOX_ISO_VERSION="${iso_array[$MENU_SELECTED]}"
      local selected_version
      selected_version=$(get_iso_version "$PROXMOX_ISO_VERSION")
      if [[ $MENU_SELECTED -eq 0 ]]; then
        print_success "Proxmox VE:" "${selected_version} (latest)"
      else
        print_success "Proxmox VE:" "${selected_version}"
      fi
    fi
  fi

  # --- Timezone ---
  if [[ -n $TIMEZONE ]]; then
    print_success "Timezone:" "${TIMEZONE} (from env)"
  else
    local tz_options=("Europe/Kyiv" "Europe/London" "Europe/Berlin" "America/New_York" "America/Los_Angeles" "Asia/Tokyo" "UTC" "custom")

    radio_menu \
      "Timezone (↑/↓ select, Enter confirm)" \
      "Select your server timezone"$'\n' \
      "Europe/Kyiv|Ukraine" \
      "Europe/London|United Kingdom (GMT/BST)" \
      "Europe/Berlin|Germany, Central Europe (CET/CEST)" \
      "America/New_York|US Eastern Time (EST/EDT)" \
      "America/Los_Angeles|US Pacific Time (PST/PDT)" \
      "Asia/Tokyo|Japan Standard Time (JST)" \
      "UTC|Coordinated Universal Time" \
      "Custom|Enter timezone manually"

    if [[ $MENU_SELECTED -eq 7 ]]; then
      prompt_with_validation \
        "Enter your timezone: " \
        "Europe/Kyiv" \
        "validate_timezone" \
        "Invalid timezone. Use format like: Europe/London, America/New_York" \
        "TIMEZONE" \
        "Timezone: "
    else
      TIMEZONE="${tz_options[$MENU_SELECTED]}"
      print_success "Timezone:" "${TIMEZONE}"
    fi
  fi

  # --- Bridge mode ---
  if [[ -n $BRIDGE_MODE ]]; then
    print_success "Bridge mode:" "${BRIDGE_MODE} (from env)"
  else
    local bridge_options=("internal" "external" "both")
    local bridge_header="Configure network bridges for VMs and containers"$'\n'
    bridge_header+="vmbr0 = external (bridged to physical NIC)"$'\n'
    bridge_header+="vmbr1 = internal (NAT with private subnet)"$'\n'

    radio_menu \
      "Network Bridge Mode (↑/↓ select, Enter confirm)" \
      "$bridge_header" \
      "Internal only (NAT)|VMs use private IPs with NAT" \
      "External only (Bridged)|VMs get IPs from router/DHCP" \
      "Both bridges|Internal NAT + External bridged"

    BRIDGE_MODE="${bridge_options[$MENU_SELECTED]}"
    case "$BRIDGE_MODE" in
      internal) print_success "Bridge mode:" "Internal NAT only (vmbr0)" ;;
      external) print_success "Bridge mode:" "External bridged only (vmbr0)" ;;
      both) print_success "Bridge mode:" "Both (vmbr0=external, vmbr1=internal)" ;;
    esac
  fi

  # --- Private subnet ---
  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    if [[ -n $PRIVATE_SUBNET ]]; then
      print_success "Private subnet:" "${PRIVATE_SUBNET} (from env)"
    else
      local subnet_options=("10.0.0.0/24" "192.168.1.0/24" "172.16.0.0/24" "custom")

      radio_menu \
        "Private Subnet (↑/↓ select, Enter confirm)" \
        "Internal network for VMs and containers"$'\n' \
        "10.0.0.0/24|Class A private (recommended)" \
        "192.168.1.0/24|Class C private (common home network)" \
        "172.16.0.0/24|Class B private" \
        "Custom|Enter subnet manually"

      if [[ $MENU_SELECTED -eq 3 ]]; then
        prompt_with_validation \
          "Enter your private subnet: " \
          "10.0.0.0/24" \
          "validate_subnet" \
          "Invalid subnet. Use CIDR format like: 10.0.0.0/24" \
          "PRIVATE_SUBNET" \
          "Private subnet: "
      else
        PRIVATE_SUBNET="${subnet_options[$MENU_SELECTED]}"
        print_success "Private subnet:" "${PRIVATE_SUBNET}"
      fi
    fi
  fi

  # --- IPv6 Configuration ---
  if [[ -n $IPV6_MODE ]]; then
    # Apply IPv6 settings from environment
    if [[ $IPV6_MODE == "disabled" ]]; then
      MAIN_IPV6=""
      IPV6_GATEWAY=""
      FIRST_IPV6_CIDR=""
      print_success "IPv6:" "disabled (from env)"
    elif [[ $IPV6_MODE == "manual" ]]; then
      IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
      if [[ -n $IPV6_ADDRESS ]]; then
        MAIN_IPV6="${IPV6_ADDRESS%/*}"
      fi
      print_success "IPv6:" "${MAIN_IPV6:-auto} (gateway: ${IPV6_GATEWAY}, from env)"
    else
      IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
      if [[ -n $MAIN_IPV6 ]]; then
        print_success "IPv6:" "${MAIN_IPV6} (gateway: ${IPV6_GATEWAY}, from env)"
      else
        print_warning "IPv6: not detected"
      fi
    fi
  else
    # Interactive IPv6 configuration
    local ipv6_options=("auto" "manual" "disabled")
    local ipv6_header="Configure IPv6 networking for dual-stack support."$'\n'
    if [[ -n $MAIN_IPV6 ]]; then
      ipv6_header+="Detected: ${MAIN_IPV6}"$'\n'
    else
      ipv6_header+="No IPv6 address detected on interface."$'\n'
    fi

    radio_menu \
      "IPv6 Configuration (↑/↓ select, Enter confirm)" \
      "$ipv6_header" \
      "Auto|Use detected IPv6 address (recommended)" \
      "Manual|Enter IPv6 address and gateway manually" \
      "Disabled|IPv4-only configuration"

    IPV6_MODE="${ipv6_options[$MENU_SELECTED]}"

    if [[ $IPV6_MODE == "disabled" ]]; then
      MAIN_IPV6=""
      IPV6_GATEWAY=""
      FIRST_IPV6_CIDR=""
      print_success "IPv6:" "disabled"
    elif [[ $IPV6_MODE == "manual" ]]; then
      # Manual IPv6 address entry
      local ipv6_content="Enter your IPv6 address in CIDR notation."$'\n'
      ipv6_content+="Example: 2001:db8::1/64"

      input_box "IPv6 Address" "$ipv6_content" "IPv6 Address: " "${MAIN_IPV6:+${MAIN_IPV6}/64}"

      while [[ -n $INPUT_VALUE ]] && ! validate_ipv6_cidr "$INPUT_VALUE"; do
        print_error "Invalid IPv6 CIDR notation. Use format like: 2001:db8::1/64"
        input_box "IPv6 Address" "$ipv6_content" "IPv6 Address: " "$INPUT_VALUE"
      done

      if [[ -n $INPUT_VALUE ]]; then
        IPV6_ADDRESS="$INPUT_VALUE"
        MAIN_IPV6="${INPUT_VALUE%/*}"
      fi

      # Manual IPv6 gateway entry
      local gw_content="Enter your IPv6 gateway address."$'\n'
      gw_content+="Default for Hetzner: fe80::1 (link-local)"

      input_box "IPv6 Gateway" "$gw_content" "Gateway: " "${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"

      while [[ -n $INPUT_VALUE ]] && ! validate_ipv6_gateway "$INPUT_VALUE"; do
        print_error "Invalid IPv6 gateway address."
        input_box "IPv6 Gateway" "$gw_content" "Gateway: " "$INPUT_VALUE"
      done

      IPV6_GATEWAY="${INPUT_VALUE:-$DEFAULT_IPV6_GATEWAY}"
      print_success "IPv6:" "${MAIN_IPV6:-none} (gateway: ${IPV6_GATEWAY})"
    else
      # Auto mode
      IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
      if [[ -n $MAIN_IPV6 ]]; then
        print_success "IPv6:" "${MAIN_IPV6} (gateway: ${IPV6_GATEWAY})"
      else
        print_warning "IPv6: not detected (will be IPv4-only)"
      fi
    fi
  fi

  # --- ZFS RAID mode ---
  if [[ ${DRIVE_COUNT:-0} -ge 2 ]]; then
    if [[ -n $ZFS_RAID ]]; then
      print_success "ZFS mode:" "${ZFS_RAID} (from env)"
    else
      local zfs_options=("raid1" "raid0" "single")
      local zfs_labels=("RAID-1 (mirror) - Recommended" "RAID-0 (stripe) - No redundancy" "Single drive - No redundancy")

      radio_menu \
        "ZFS Storage Mode (↑/↓ select, Enter confirm)" \
        "Select ZFS pool configuration for your drives"$'\n' \
        "${zfs_labels[0]}|Survives 1 disk failure" \
        "${zfs_labels[1]}|2x space & speed, no redundancy" \
        "${zfs_labels[2]}|Uses first drive only"

      ZFS_RAID="${zfs_options[$MENU_SELECTED]}"
      print_success "ZFS mode:" "${zfs_labels[$MENU_SELECTED]}"
    fi
  else
    # Single drive - no RAID options available
    if [[ -n $ZFS_RAID ]]; then
      print_success "ZFS mode:" "${ZFS_RAID} (from env)"
    else
      ZFS_RAID="single"
      print_success "ZFS mode:" "single (1 drive detected)"
    fi
  fi

  # --- Proxmox Repository ---
  if [[ -n $PVE_REPO_TYPE ]]; then
    print_success "Repository:" "${PVE_REPO_TYPE} (from env)"
    if [[ $PVE_REPO_TYPE == "enterprise" && -n $PVE_SUBSCRIPTION_KEY ]]; then
      print_success "Subscription key:" "configured"
    fi
  else
    local repo_options=("no-subscription" "enterprise" "test")

    radio_menu \
      "Proxmox Repository (↑/↓ select, Enter confirm)" \
      "Select which repository to use for updates"$'\n' \
      "No-Subscription|Free community repository (default)" \
      "Enterprise|Stable, requires subscription key" \
      "Test|Latest packages, may be unstable"

    PVE_REPO_TYPE="${repo_options[$MENU_SELECTED]}"

    if [[ $PVE_REPO_TYPE == "enterprise" ]]; then
      local key_content="Enterprise repository requires a subscription key."$'\n'
      key_content+="Get your key from:"$'\n'
      key_content+="https://www.proxmox.com/proxmox-ve/pricing"$'\n'
      key_content+=$'\n'
      key_content+="Format: pve1c-XXXXXXXXXX or pve2c-XXXXXXXXXX"

      input_box "Proxmox Subscription Key" "$key_content" "Key: " ""
      PVE_SUBSCRIPTION_KEY="$INPUT_VALUE"

      if [[ -n $PVE_SUBSCRIPTION_KEY ]]; then
        print_success "Repository:" "enterprise (key configured)"
      else
        print_warning "Repository:" "enterprise (no key - will show warning in UI)"
      fi
    else
      PVE_SUBSCRIPTION_KEY=""
      print_success "Repository:" "${PVE_REPO_TYPE}"
    fi
  fi

  # --- Optional Features (checkbox menu) ---
  # Check if any of the optional features are already set from env
  local all_features_from_env=true
  [[ -z $DEFAULT_SHELL ]] && all_features_from_env=false
  [[ -z $INSTALL_VNSTAT ]] && all_features_from_env=false
  [[ -z $INSTALL_AUDITD ]] && all_features_from_env=false
  [[ -z $INSTALL_UNATTENDED_UPGRADES ]] && all_features_from_env=false

  if [[ $all_features_from_env == true ]]; then
    # All set from environment, just display them
    print_success "Default shell:" "${DEFAULT_SHELL} (from env)"
    if [[ $INSTALL_VNSTAT == "yes" ]]; then
      print_success "Bandwidth monitoring:" "enabled (from env)"
    else
      print_success "Bandwidth monitoring:" "disabled (from env)"
    fi
    if [[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]]; then
      print_success "Auto security updates:" "enabled (from env)"
    else
      print_success "Auto security updates:" "disabled (from env)"
    fi
    if [[ $INSTALL_AUDITD == "yes" ]]; then
      print_success "Audit logging:" "enabled (from env)"
    else
      print_success "Audit logging:" "disabled (from env)"
    fi
  else
    # Show checkbox menu for optional features
    local features_header="Select optional features to install."$'\n'
    features_header+="Use ↑/↓ to navigate, Space to toggle, Enter to confirm."$'\n'

    # Determine default states (1=checked, 0=unchecked)
    local zsh_default=1
    local vnstat_default=1
    local unattended_default=1
    local auditd_default=0

    # Override with env values if set
    [[ $DEFAULT_SHELL == "bash" ]] && zsh_default=0
    [[ $INSTALL_VNSTAT == "no" ]] && vnstat_default=0
    [[ $INSTALL_UNATTENDED_UPGRADES == "no" ]] && unattended_default=0
    [[ $INSTALL_AUDITD == "yes" ]] && auditd_default=1

    checkbox_menu \
      "Optional Features (↑/↓ navigate, Space toggle, Enter confirm)" \
      "$features_header" \
      "ZSH shell|Modern shell with autosuggestions and syntax highlighting|${zsh_default}" \
      "vnstat|Bandwidth monitoring for tracking Hetzner transfer usage|${vnstat_default}" \
      "Unattended upgrades|Automatic security updates|${unattended_default}" \
      "auditd|Audit logging for administrative action tracking|${auditd_default}"

    # Process results
    if [[ ${CHECKBOX_RESULTS[0]} == "1" ]]; then
      DEFAULT_SHELL="zsh"
      print_success "Default shell:" "zsh"
    else
      DEFAULT_SHELL="bash"
      print_success "Default shell:" "bash"
    fi

    if [[ ${CHECKBOX_RESULTS[1]} == "1" ]]; then
      INSTALL_VNSTAT="yes"
      print_success "Bandwidth monitoring:" "enabled (vnstat)"
    else
      INSTALL_VNSTAT="no"
      print_success "Bandwidth monitoring:" "disabled"
    fi

    if [[ ${CHECKBOX_RESULTS[2]} == "1" ]]; then
      INSTALL_UNATTENDED_UPGRADES="yes"
      print_success "Auto security updates:" "enabled"
    else
      INSTALL_UNATTENDED_UPGRADES="no"
      print_success "Auto security updates:" "disabled"
    fi

    if [[ ${CHECKBOX_RESULTS[3]} == "1" ]]; then
      INSTALL_AUDITD="yes"
      print_success "Audit logging:" "enabled (auditd)"
    else
      INSTALL_AUDITD="no"
      print_success "Audit logging:" "disabled"
    fi
  fi

  # --- CPU Governor / Power Profile ---
  if [[ -n $CPU_GOVERNOR ]]; then
    print_success "Power profile:" "${CPU_GOVERNOR} (from env)"
  else
    local governor_options=("performance" "ondemand" "powersave" "schedutil" "conservative")
    local governor_header="Select CPU frequency scaling governor (power profile)."$'\n'
    governor_header+="Affects power consumption, heat, and performance."$'\n'

    radio_menu \
      "Power Profile (↑/↓ select, Enter confirm)" \
      "$governor_header" \
      "Performance|Max speed, highest power (recommended)" \
      "On-demand|Scales frequency based on load" \
      "Powersave|Min speed, lowest power consumption" \
      "Schedutil|Kernel scheduler-driven scaling" \
      "Conservative|Gradual frequency scaling"

    CPU_GOVERNOR="${governor_options[$MENU_SELECTED]}"
    print_success "Power profile:" "${CPU_GOVERNOR}"
  fi

  # --- SSH Public Key ---
  if [[ -n $SSH_PUBLIC_KEY ]]; then
    parse_ssh_key "$SSH_PUBLIC_KEY"
    print_success "SSH key:" "${SSH_KEY_TYPE} (from env)"
  else
    local DETECTED_SSH_KEY
    DETECTED_SSH_KEY=$(get_rescue_ssh_key)

    if [[ -n $DETECTED_SSH_KEY ]]; then
      parse_ssh_key "$DETECTED_SSH_KEY"

      local ssh_header="! Password authentication will be DISABLED"$'\n'
      ssh_header+=$'\n'
      ssh_header+="  Detected key from Rescue System:"$'\n'
      ssh_header+="  Type:    ${SSH_KEY_TYPE}"$'\n'
      ssh_header+="  Key:     ${SSH_KEY_SHORT}"
      if [[ -n $SSH_KEY_COMMENT ]]; then
        ssh_header+=$'\n'"  Comment: ${SSH_KEY_COMMENT}"
      fi
      ssh_header+=$'\n'

      radio_menu \
        "SSH Public Key (↑/↓ select, Enter confirm)" \
        "$ssh_header" \
        "Use detected key|Already configured in Hetzner" \
        "Enter different key|Paste your own SSH public key"

      if [[ $MENU_SELECTED -eq 0 ]]; then
        SSH_PUBLIC_KEY="$DETECTED_SSH_KEY"
        print_success "SSH key:" "configured (${SSH_KEY_TYPE})"
      else
        SSH_PUBLIC_KEY=""
      fi
    fi

    # Manual entry if no key yet
    if [[ -z $SSH_PUBLIC_KEY ]]; then
      local ssh_content="! Password authentication will be DISABLED"$'\n'
      if [[ -z $DETECTED_SSH_KEY ]]; then
        ssh_content+=$'\n'"No SSH key detected in Rescue System."
      fi
      ssh_content+=$'\n'$'\n'"Paste your SSH public key below:"$'\n'
      ssh_content+="(Usually from ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)"

      input_box "SSH Public Key Configuration" "$ssh_content" "SSH Public Key: " ""

      while [[ -z $INPUT_VALUE ]] || ! validate_ssh_key "$INPUT_VALUE"; do
        if [[ -z $INPUT_VALUE ]]; then
          print_error "SSH public key is required for secure access!"
        else
          print_warning "SSH key format may be invalid. Continue anyway? (y/n): "
          read -rsn1 confirm
          echo ""
          if [[ $confirm =~ ^[Yy]$ ]]; then
            break
          fi
        fi
        input_box "SSH Public Key Configuration" "$ssh_content" "SSH Public Key: " ""
      done

      SSH_PUBLIC_KEY="$INPUT_VALUE"
      parse_ssh_key "$SSH_PUBLIC_KEY"
      print_success "SSH key:" "configured (${SSH_KEY_TYPE})"
    fi
  fi

  # --- Tailscale ---
  if [[ -n $INSTALL_TAILSCALE ]]; then
    if [[ $INSTALL_TAILSCALE == "yes" ]]; then
      TAILSCALE_SSH="${TAILSCALE_SSH:-yes}"
      TAILSCALE_WEBUI="${TAILSCALE_WEBUI:-yes}"
      if [[ -n $TAILSCALE_AUTH_KEY ]]; then
        print_success "Tailscale:" "yes (auto-connect, from env)"
      else
        print_success "Tailscale:" "yes (manual auth, from env)"
      fi
    else
      TAILSCALE_AUTH_KEY=""
      TAILSCALE_SSH="no"
      TAILSCALE_WEBUI="no"
      print_success "Tailscale:" "skipped (from env)"
    fi
  else
    local ts_header="Tailscale provides secure remote access to your server."$'\n'
    ts_header+="Auth key: https://login.tailscale.com/admin/settings/keys"$'\n'

    radio_menu \
      "Tailscale VPN - Optional (↑/↓ select, Enter confirm)" \
      "$ts_header" \
      "Install Tailscale|Recommended for secure remote access" \
      "Skip installation|Install Tailscale later if needed"

    if [[ $MENU_SELECTED -eq 0 ]]; then
      INSTALL_TAILSCALE="yes"
      TAILSCALE_SSH="yes"
      TAILSCALE_WEBUI="yes"
      TAILSCALE_DISABLE_SSH="no"

      if [[ -z $TAILSCALE_AUTH_KEY ]]; then
        local auth_content="Auth key enables automatic configuration."$'\n'
        auth_content+="Leave empty for manual auth after reboot."$'\n'
        auth_content+=$'\n'
        auth_content+="For unattended setup, use a reusable auth key"$'\n'
        auth_content+="with tags and expiry for better security."

        input_box "Tailscale Auth Key (optional)" "$auth_content" "Auth Key: " ""
        TAILSCALE_AUTH_KEY="$INPUT_VALUE"
      fi

      if [[ -n $TAILSCALE_AUTH_KEY ]]; then
        # Auto-enable security features when auth key is provided
        TAILSCALE_DISABLE_SSH="yes"
        STEALTH_MODE="yes"
        print_success "Tailscale:" "will be installed (auto-connect)"
        print_success "OpenSSH:" "will be disabled on first boot"
        print_success "Stealth firewall:" "enabled (server hidden from internet)"
      else
        print_warning "Tailscale:" "enabled (no key - manual auth required)"
        STEALTH_MODE="no"
      fi
    else
      INSTALL_TAILSCALE="no"
      TAILSCALE_AUTH_KEY=""
      TAILSCALE_SSH="no"
      TAILSCALE_WEBUI="no"
      TAILSCALE_DISABLE_SSH="no"
      STEALTH_MODE="no"
      print_success "Tailscale:" "installation skipped"
    fi
  fi

  # --- SSL Certificate (only if Tailscale is not installed) ---
  if [[ $INSTALL_TAILSCALE != "yes" ]]; then
    if [[ -n $SSL_TYPE ]]; then
      print_success "SSL certificate:" "${SSL_TYPE} (from env)"
    else
      local ssl_options=("self-signed" "letsencrypt")
      local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
      local ssl_header="Configure SSL certificate for Proxmox Web UI."$'\n'
      ssl_header+=$'\n'
      ssl_header+="! For Let's Encrypt, before continuing ensure:"$'\n'
      ssl_header+="  - Domain ${le_fqdn} is registered"$'\n'
      ssl_header+="  - DNS A record points to ${MAIN_IPV4_CIDR%/*}"$'\n'
      ssl_header+="  - Port 80 is accessible from the internet"

      radio_menu \
        "SSL Certificate (↑/↓ select, Enter confirm)" \
        "$ssl_header" \
        "Self-signed|Default Proxmox certificate (recommended)" \
        "Let's Encrypt|Requires domain pointing to this server"

      SSL_TYPE="${ssl_options[$MENU_SELECTED]}"

      if [[ $SSL_TYPE == "letsencrypt" ]]; then
        local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
        local expected_ip="${MAIN_IPV4_CIDR%/*}"
        local max_attempts=3
        local attempt=1
        local dns_result=1
        local dns_tmp="/tmp/dns_check_$$"

        while [[ $attempt -le $max_attempts ]]; do
          # Run DNS check in background using dig directly (functions not available in subshell)
          (
            resolved_ip=$(dig +short A "$le_fqdn" @1.1.1.1 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
            if [[ -z $resolved_ip ]]; then
              resolved_ip=$(dig +short A "$le_fqdn" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
            fi
            if [[ -z $resolved_ip ]]; then
              echo "1:" >"$dns_tmp"
            elif [[ $resolved_ip == "$expected_ip" ]]; then
              echo "0:$resolved_ip" >"$dns_tmp"
            else
              echo "2:$resolved_ip" >"$dns_tmp"
            fi
          ) &
          local check_pid=$!
          show_progress $check_pid "Checking DNS: ${le_fqdn} → ${expected_ip} (attempt ${attempt}/${max_attempts})" --silent

          # Read result from temp file
          if [[ -f $dns_tmp ]]; then
            dns_result=$(cut -d: -f1 <"$dns_tmp")
            DNS_RESOLVED_IP=$(cut -d: -f2 <"$dns_tmp")
            rm -f "$dns_tmp"
          else
            dns_result=1
          fi

          if [[ $dns_result -eq 0 ]]; then
            print_success "SSL:" "Let's Encrypt (DNS verified: ${le_fqdn} → ${expected_ip})"
            break
          fi

          # Show error for this attempt
          if [[ $dns_result -eq 1 ]]; then
            print_error "DNS check failed: ${le_fqdn} does not resolve"
          else
            print_error "DNS mismatch: ${le_fqdn} → ${DNS_RESOLVED_IP} (expected: ${expected_ip})"
          fi

          if [[ $attempt -lt $max_attempts ]]; then
            print_info "Retrying in ${DNS_RETRY_DELAY} seconds... (Press Ctrl+C to cancel)"
            sleep "$DNS_RETRY_DELAY"
          fi
          ((attempt++))
        done

        rm -f "$dns_tmp" 2>/dev/null

        if [[ $dns_result -ne 0 ]]; then
          echo ""
          print_error "DNS validation failed after ${max_attempts} attempts"
          echo ""
          print_info "To fix this:"
          print_info "  1. Go to your DNS provider"
          print_info "  2. Create/update A record: ${le_fqdn} → ${expected_ip}"
          print_info "  3. Wait for DNS propagation (usually 1-5 minutes)"
          print_info "  4. Run this installer again"
          echo ""
          exit 1
        fi
      else
        print_success "SSL:" "Self-signed certificate"
      fi
    fi
  else
    # Tailscale provides its own HTTPS via serve
    SSL_TYPE="self-signed"
  fi
}
