# shellcheck shell=bash
# =============================================================================
# Configuration preview and edit functionality
# =============================================================================

# Display configuration summary box
# display_config_preview builds and prints a boxed, human-readable summary of the current configuration settings for review.
display_config_preview() {
  local inner_width=$((MENU_BOX_WIDTH - 6))
  local content=""

  # --- Basic Settings ---
  content+="|--- Basic Settings ---|"$'\n'
  content+="|Hostname|${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"$'\n'
  content+="|Email|${EMAIL}"$'\n'
  content+="|Password|$([ "$PASSWORD_GENERATED" == "yes" ] && echo "auto-generated" || echo "********")"$'\n'
  content+="|Timezone|${TIMEZONE}"$'\n'

  # --- Network ---
  content+="|--- Network ---"$'\n'
  content+="|Interface|${INTERFACE_NAME}"$'\n'
  content+="|IPv4|${MAIN_IPV4_CIDR}"$'\n'
  content+="|Gateway|${MAIN_IPV4_GW}"$'\n'
  case "$BRIDGE_MODE" in
    internal) content+="|Bridge|Internal NAT (vmbr0)" ;;
    external) content+="|Bridge|External bridged (vmbr0)" ;;
    both) content+="|Bridge|Both (vmbr0=ext, vmbr1=int)" ;;
  esac
  content+=$'\n'
  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    content+="|Private subnet|${PRIVATE_SUBNET}"$'\n'
  fi

  # --- IPv6 ---
  content+="|--- IPv6 ---"$'\n'
  case "$IPV6_MODE" in
    disabled)
      content+="|IPv6|Disabled"$'\n'
      ;;
    manual)
      content+="|IPv6|${MAIN_IPV6:-not set}"$'\n'
      content+="|IPv6 Gateway|${IPV6_GATEWAY}"$'\n'
      ;;
    auto | *)
      if [[ -n $MAIN_IPV6 ]]; then
        content+="|IPv6|${MAIN_IPV6} (auto)"$'\n'
        content+="|IPv6 Gateway|${IPV6_GATEWAY:-fe80::1}"$'\n'
      else
        content+="|IPv6|Not detected"$'\n'
      fi
      ;;
  esac

  # --- Storage ---
  content+="|--- Storage ---"$'\n'
  local zfs_desc
  case "$ZFS_RAID" in
    raid1) zfs_desc="RAID-1 (mirror)" ;;
    raid0) zfs_desc="RAID-0 (stripe)" ;;
    single) zfs_desc="Single drive" ;;
    *) zfs_desc="$ZFS_RAID" ;;
  esac
  content+="|ZFS Mode|${zfs_desc}"$'\n'
  content+="|Drives|${DRIVES[*]}"$'\n'

  # --- Proxmox ---
  content+="|--- Proxmox ---"$'\n'
  if [[ -n $PROXMOX_ISO_VERSION ]]; then
    local pve_version
    pve_version=$(get_iso_version "$PROXMOX_ISO_VERSION" 2>/dev/null || echo "$PROXMOX_ISO_VERSION")
    content+="|Version|${pve_version}"$'\n'
  else
    content+="|Version|Latest"$'\n'
  fi
  content+="|Repository|${PVE_REPO_TYPE:-no-subscription}"$'\n'

  # --- SSL ---
  content+="|--- SSL ---"$'\n'
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    content+="|SSL|Self-signed (Tailscale HTTPS)"$'\n'
  else
    content+="|SSL|${SSL_TYPE:-self-signed}"$'\n'
  fi

  # --- Tailscale ---
  content+="|--- VPN ---"$'\n'
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    if [[ -n $TAILSCALE_AUTH_KEY ]]; then
      content+="|Tailscale|Enabled (auto-connect)"$'\n'
    else
      content+="|Tailscale|Enabled (manual auth)"$'\n'
    fi
    if [[ $STEALTH_MODE == "yes" ]]; then
      content+="|Stealth mode|Enabled"$'\n'
    fi
    if [[ $TAILSCALE_DISABLE_SSH == "yes" ]]; then
      content+="|OpenSSH|Will be disabled"$'\n'
    fi
  else
    content+="|Tailscale|Not installed"$'\n'
  fi

  # --- Optional Features ---
  content+="|--- Optional ---"$'\n'
  content+="|Shell|${DEFAULT_SHELL:-bash}"$'\n'
  content+="|Power profile|${CPU_GOVERNOR:-performance}"$'\n'
  local features=""
  [[ $INSTALL_VNSTAT == "yes" ]] && features+="vnstat, "
  [[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]] && features+="auto-updates, "
  [[ $INSTALL_AUDITD == "yes" ]] && features+="auditd, "
  if [[ -n $features ]]; then
    content+="|Features|${features%, }"$'\n'
  else
    content+="|Features|None"$'\n'
  fi

  # --- SSH ---
  content+="|--- SSH ---"$'\n'
  if [[ -n $SSH_PUBLIC_KEY ]]; then
    parse_ssh_key "$SSH_PUBLIC_KEY"
    content+="|SSH Key|${SSH_KEY_TYPE}"
    if [[ -n $SSH_KEY_COMMENT ]]; then
      content+=" (${SSH_KEY_COMMENT})"
    fi
    content+=$'\n'
  else
    content+="|SSH Key|Not configured"$'\n'
  fi

  # Remove trailing newline
  content="${content%$'\n'}"

  # Display with boxes
  {
    echo "Configuration Review"
    echo "$content" | column -t -s '|' | while IFS= read -r line; do
      printf "%-${inner_width}s\n" "$line"
    done
    echo ""
    printf "%-${inner_width}s\n" "Press ENTER_KEY to start installation"
    printf "%-${inner_width}s\n" "Press E_KEY to edit configuration"
    printf "%-${inner_width}s\n" "Press Q_KEY to quit"
  } | boxes -d stone -p a1 -s "$MENU_BOX_WIDTH" | _colorize_preview
}

# _colorize_preview applies color styling to box-formatted preview lines read from stdin, highlighting borders, section headers, and the action key hints.
# It colors top/bottom box borders gray, wraps section header lines containing '---' in cyan, and transforms the bottom "Press" line by replacing ENTER_KEY/E_KEY/Q_KEY placeholders with colored key labels (Enter, e, q), padding the content to the box inner width so the hints align.
_colorize_preview() {
  local box_width=$MENU_BOX_WIDTH
  local inner_width=$((box_width - 1)) # Width between | borders (boxes adds padding)

  while IFS= read -r line; do
    # Top/bottom border
    if [[ $line =~ ^\+[-+]+\+$ ]]; then
      echo "${CLR_GRAY}${line}${CLR_RESET}"
    # Content line with | borders
    elif [[ $line =~ ^(\|)(.*)\|$ ]]; then
      local content="${BASH_REMATCH[2]}"
      local visible_content="$content"
      # Section headers (lines starting with ---)
      if [[ $content == *"---"* ]]; then
        content="${CLR_CYAN}${content}${CLR_RESET}"
      fi
      # Key bindings at the bottom - highlight keys in cyan
      if [[ $visible_content == *"Press"* ]]; then
        # Calculate visible length (without placeholders, with actual key names)
        visible_content="${visible_content//ENTER_KEY/Enter}"
        visible_content="${visible_content//E_KEY/e}"
        visible_content="${visible_content//Q_KEY/q}"
        local visible_len=${#visible_content}
        local padding=$((inner_width - visible_len))
        # Apply colors
        content="${content//ENTER_KEY/${CLR_CYAN}Enter${CLR_GRAY}}"
        content="${content//E_KEY/${CLR_CYAN}e${CLR_GRAY}}"
        content="${content//Q_KEY/${CLR_CYAN}q${CLR_GRAY}}"
        content="${CLR_GRAY}${content}"
        # Add padding spaces before reset
        printf -v content "%s%${padding}s${CLR_RESET}" "$content" ""
      fi
      echo "${CLR_GRAY}|${CLR_RESET}${content}${CLR_GRAY}|${CLR_RESET}"
    else
      echo "$line"
    fi
  done
}

# Edit configuration menu
# edit_configuration presents a dynamic, section-based editor allowing the user to choose and edit configuration sections (e.g., Basic Settings, Network, IPv6, Storage, Proxmox, SSL, Tailscale, Optional, SSH) and invokes the corresponding edit action for the selected section.
# Returns 0 to continue to installation, 1 to show the preview again.
edit_configuration() {
  # Build menu dynamically based on current configuration
  local -a edit_sections=()
  local -a edit_actions=()

  # Always available sections
  edit_sections+=("Basic Settings|Hostname, domain, email, password, timezone")
  edit_actions+=("_edit_basic_settings")

  edit_sections+=("Network|Bridge mode, private subnet")
  edit_actions+=("_edit_network_settings")

  edit_sections+=("IPv6|IPv6 mode and settings")
  edit_actions+=("_edit_ipv6_settings")

  # Storage - show RAID options only if multiple drives
  if [[ ${DRIVE_COUNT:-0} -ge 2 ]]; then
    edit_sections+=("Storage|ZFS RAID level (${DRIVE_COUNT} drives)")
  else
    edit_sections+=("Storage|Single drive mode")
  fi
  edit_actions+=("_edit_storage_settings")

  edit_sections+=("Proxmox|Version and repository")
  edit_actions+=("_edit_proxmox_settings")

  # SSL - only show if Tailscale is NOT enabled
  if [[ $INSTALL_TAILSCALE != "yes" ]]; then
    edit_sections+=("SSL|Certificate type")
    edit_actions+=("_edit_ssl_settings")
  fi

  edit_sections+=("Tailscale|VPN configuration")
  edit_actions+=("_edit_tailscale_settings")

  edit_sections+=("Optional|Shell, packages, power profile")
  edit_actions+=("_edit_optional_settings")

  edit_sections+=("SSH Key|Public key for authentication")
  edit_actions+=("_edit_ssh_settings")

  # Done option always last
  edit_sections+=("Done|Return to configuration review")
  edit_actions+=("return")

  radio_menu \
    "Edit Configuration (select section)" \
    "Select which section to edit"$'\n' \
    "${edit_sections[@]}"

  # Execute selected action
  local action="${edit_actions[$MENU_SELECTED]}"
  if [[ $action == "return" ]]; then
    return 0
  else
    $action
  fi

  return 0
}

# =============================================================================
# Section edit functions
# _edit_basic_settings prompts the user to configure core server settings: hostname, domain suffix, email, root password, and timezone.
# It validates inputs where applicable and updates the corresponding environment variables.
# - Prompts for hostname and validates format (letters, numbers, hyphens, 1-63 chars); updates `PVE_HOSTNAME`.
# - Prompts for domain suffix; updates `DOMAIN_SUFFIX`.
# - Prompts for notification email and validates format; updates `EMAIL`.
# - Prompts for a new root password (empty to keep current or to auto-generate); validates password strength and, on success, sets `NEW_ROOT_PASSWORD` and `PASSWORD_GENERATED="no"`.
# - Presents a timezone selection (predefined list or Custom); validates custom input and updates `TIMEZONE`.
# - Updates derived `FQDN` as `${PVE_HOSTNAME}.${DOMAIN_SUFFIX}` and prints success messages for each changed value.

_edit_basic_settings() {
  # Hostname
  local hostname_content="Enter the short hostname for your server."$'\n'
  hostname_content+="Example: pve, proxmox, server01"
  input_box "Hostname" "$hostname_content" "Hostname: " "$PVE_HOSTNAME"
  while [[ -n $INPUT_VALUE ]] && ! validate_hostname "$INPUT_VALUE"; do
    print_error "Invalid hostname. Use only letters, numbers, and hyphens (1-63 chars)."
    input_box "Hostname" "$hostname_content" "Hostname: " "$INPUT_VALUE"
  done
  [[ -n $INPUT_VALUE ]] && PVE_HOSTNAME="$INPUT_VALUE"
  print_success "Hostname:" "$PVE_HOSTNAME"

  # Domain
  local domain_content="Enter the domain suffix for your server."$'\n'
  domain_content+="Example: local, example.com"
  input_box "Domain" "$domain_content" "Domain: " "$DOMAIN_SUFFIX"
  [[ -n $INPUT_VALUE ]] && DOMAIN_SUFFIX="$INPUT_VALUE"
  print_success "Domain:" "$DOMAIN_SUFFIX"

  # Email
  local email_content="Enter your email address for notifications."
  input_box "Email" "$email_content" "Email: " "$EMAIL"
  while [[ -n $INPUT_VALUE ]] && ! validate_email "$INPUT_VALUE"; do
    print_error "Invalid email address format."
    input_box "Email" "$email_content" "Email: " "$INPUT_VALUE"
  done
  [[ -n $INPUT_VALUE ]] && EMAIL="$INPUT_VALUE"
  print_success "Email:" "$EMAIL"

  # Password
  local password_content="Enter new root password or leave empty to keep current."$'\n'
  password_content+="Leave empty to auto-generate a new password."
  input_box "Password" "$password_content" "Password: " ""
  if [[ -n $INPUT_VALUE ]]; then
    local password_error
    password_error=$(get_password_error "$INPUT_VALUE")
    while [[ -n $password_error ]]; do
      print_error "$password_error"
      input_box "Password" "$password_content" "Password: " ""
      [[ -z $INPUT_VALUE ]] && break
      password_error=$(get_password_error "$INPUT_VALUE")
    done
    if [[ -n $INPUT_VALUE ]]; then
      NEW_ROOT_PASSWORD="$INPUT_VALUE"
      PASSWORD_GENERATED="no"
      print_success "Password:" "********"
    fi
  fi

  # Timezone
  local tz_options=("Europe/Kyiv" "Europe/London" "Europe/Berlin" "America/New_York" "America/Los_Angeles" "Asia/Tokyo" "UTC" "custom")

  radio_menu \
    "Timezone (select or choose Custom)" \
    "Select your server timezone"$'\n' \
    "Europe/Kyiv|Ukraine" \
    "Europe/London|United Kingdom" \
    "Europe/Berlin|Germany" \
    "America/New_York|US Eastern" \
    "America/Los_Angeles|US Pacific" \
    "Asia/Tokyo|Japan" \
    "UTC|Coordinated Universal Time" \
    "Custom|Enter timezone manually"

  if [[ $MENU_SELECTED -eq 7 ]]; then
    local tz_content="Enter your timezone in Region/City format."$'\n'
    tz_content+="Example: Europe/London, America/New_York"
    input_box "Timezone" "$tz_content" "Timezone: " "$TIMEZONE"
    while [[ -n $INPUT_VALUE ]] && ! validate_timezone "$INPUT_VALUE"; do
      print_error "Invalid timezone format."
      input_box "Timezone" "$tz_content" "Timezone: " "$INPUT_VALUE"
    done
    [[ -n $INPUT_VALUE ]] && TIMEZONE="$INPUT_VALUE"
  else
    TIMEZONE="${tz_options[$MENU_SELECTED]}"
  fi
  print_success "Timezone:" "$TIMEZONE"

  # Update derived values
  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
}

# _edit_network_settings presents an interactive menu to select the network bridge mode and, when an internal bridge is chosen, configure the private subnet and update derived private network variables.
_edit_network_settings() {
  # Save previous mode to detect changes
  local prev_bridge_mode="$BRIDGE_MODE"

  # Bridge mode
  local bridge_options=("internal" "external" "both")
  local bridge_header="Configure network bridges for VMs"$'\n'
  bridge_header+="vmbr0 = external (bridged to NIC)"$'\n'
  bridge_header+="vmbr1 = internal (NAT)"

  radio_menu \
    "Network Bridge Mode" \
    "$bridge_header" \
    "Internal only (NAT)|VMs use private IPs" \
    "External only (Bridged)|VMs get IPs from router" \
    "Both bridges|Internal + External"

  BRIDGE_MODE="${bridge_options[$MENU_SELECTED]}"
  print_success "Bridge mode:" "$BRIDGE_MODE"

  # Private subnet (only for internal/both)
  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    # Show info if switching from external mode
    if [[ $prev_bridge_mode == "external" ]]; then
      echo ""
      print_info "Internal bridge enabled - configuring private subnet..."
      echo ""
    fi

    local subnet_options=("10.0.0.0/24" "192.168.1.0/24" "172.16.0.0/24" "custom")

    radio_menu \
      "Private Subnet" \
      "Select private subnet for internal bridge"$'\n' \
      "10.0.0.0/24|Class A private (recommended)" \
      "192.168.1.0/24|Class C private" \
      "172.16.0.0/24|Class B private" \
      "Custom|Enter subnet manually"

    if [[ $MENU_SELECTED -eq 3 ]]; then
      local subnet_content="Enter private subnet in CIDR notation."$'\n'
      subnet_content+="Example: 10.0.0.0/24, 192.168.100.0/24"
      input_box "Private Subnet" "$subnet_content" "Subnet: " "$PRIVATE_SUBNET"
      while [[ -n $INPUT_VALUE ]] && ! validate_subnet "$INPUT_VALUE"; do
        print_error "Invalid subnet format."
        input_box "Private Subnet" "$subnet_content" "Subnet: " "$INPUT_VALUE"
      done
      [[ -n $INPUT_VALUE ]] && PRIVATE_SUBNET="$INPUT_VALUE"
    else
      PRIVATE_SUBNET="${subnet_options[$MENU_SELECTED]}"
    fi
    print_success "Private subnet:" "$PRIVATE_SUBNET"

    # Recalculate private network values
    PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    PRIVATE_IP="${PRIVATE_CIDR}.1"
    SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
    PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
  else
    # External only - clear private network values
    PRIVATE_SUBNET=""
    PRIVATE_CIDR=""
    PRIVATE_IP=""
    PRIVATE_IP_CIDR=""
  fi
}

_edit_ipv6_settings() {
  local ipv6_options=("auto" "manual" "disabled")
  local ipv6_header="Configure IPv6 networking."$'\n'
  if [[ -n $MAIN_IPV6 ]]; then
    ipv6_header+="Current: ${MAIN_IPV6}"
  else
    ipv6_header+="No IPv6 detected on interface."
  fi

  radio_menu \
    "IPv6 Configuration" \
    "$ipv6_header" \
    "Auto|Use detected IPv6" \
    "Manual|Enter IPv6 manually" \
    "Disabled|IPv4-only"

  IPV6_MODE="${ipv6_options[$MENU_SELECTED]}"

  if [[ $IPV6_MODE == "disabled" ]]; then
    MAIN_IPV6=""
    IPV6_GATEWAY=""
    FIRST_IPV6_CIDR=""
    print_success "IPv6:" "disabled"
  elif [[ $IPV6_MODE == "manual" ]]; then
    local ipv6_content="Enter IPv6 address in CIDR notation."$'\n'
    ipv6_content+="Example: 2001:db8::1/64"
    input_box "IPv6 Address" "$ipv6_content" "IPv6: " "${MAIN_IPV6:+${MAIN_IPV6}/64}"
    while [[ -n $INPUT_VALUE ]] && ! validate_ipv6_cidr "$INPUT_VALUE"; do
      print_error "Invalid IPv6 CIDR notation."
      input_box "IPv6 Address" "$ipv6_content" "IPv6: " "$INPUT_VALUE"
    done
    if [[ -n $INPUT_VALUE ]]; then
      IPV6_ADDRESS="$INPUT_VALUE"
      MAIN_IPV6="${INPUT_VALUE%/*}"
    fi

    local gw_content="Enter IPv6 gateway address."$'\n'
    gw_content+="Default for Hetzner: fe80::1"
    input_box "IPv6 Gateway" "$gw_content" "Gateway: " "${IPV6_GATEWAY:-fe80::1}"
    while [[ -n $INPUT_VALUE ]] && ! validate_ipv6_gateway "$INPUT_VALUE"; do
      print_error "Invalid IPv6 gateway."
      input_box "IPv6 Gateway" "$gw_content" "Gateway: " "$INPUT_VALUE"
    done
    IPV6_GATEWAY="${INPUT_VALUE:-fe80::1}"
    print_success "IPv6:" "${MAIN_IPV6} (gateway: ${IPV6_GATEWAY})"
  else
    IPV6_GATEWAY="${IPV6_GATEWAY:-fe80::1}"
    if [[ -n $MAIN_IPV6 ]]; then
      print_success "IPv6:" "${MAIN_IPV6} (auto)"
    else
      print_warning "IPv6:" "not detected"
    fi
  fi
}

_edit_storage_settings() {
  if [[ ${DRIVE_COUNT:-0} -lt 2 ]]; then
    print_warning "Only one drive detected - RAID options not available"
    ZFS_RAID="single"
    return
  fi

  local zfs_options=("raid1" "raid0" "single")

  radio_menu \
    "ZFS Storage Mode" \
    "Select ZFS pool configuration"$'\n' \
    "RAID-1 (mirror)|Survives 1 disk failure" \
    "RAID-0 (stripe)|2x space, no redundancy" \
    "Single drive|Uses first drive only"

  ZFS_RAID="${zfs_options[$MENU_SELECTED]}"
  print_success "ZFS mode:" "$ZFS_RAID"
}

_edit_proxmox_settings() {
  # Repository
  local repo_options=("no-subscription" "enterprise" "test")

  radio_menu \
    "Proxmox Repository" \
    "Select repository for updates"$'\n' \
    "No-Subscription|Free community repository" \
    "Enterprise|Stable, requires subscription" \
    "Test|Latest, may be unstable"

  PVE_REPO_TYPE="${repo_options[$MENU_SELECTED]}"

  if [[ $PVE_REPO_TYPE == "enterprise" ]]; then
    local key_content="Enter Proxmox subscription key."$'\n'
    key_content+="Format: pve1c-XXXXXXXXXX"
    input_box "Subscription Key" "$key_content" "Key: " "$PVE_SUBSCRIPTION_KEY"
    PVE_SUBSCRIPTION_KEY="$INPUT_VALUE"
  else
    PVE_SUBSCRIPTION_KEY=""
  fi
  print_success "Repository:" "$PVE_REPO_TYPE"
}

_edit_ssl_settings() {
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    print_info "SSL is managed by Tailscale when VPN is enabled"
    SSL_TYPE="self-signed"
    return
  fi

  local ssl_options=("self-signed" "letsencrypt")

  radio_menu \
    "SSL Certificate" \
    "Select SSL certificate type"$'\n' \
    "Self-signed|Default Proxmox certificate" \
    "Let's Encrypt|Requires domain pointing to server"

  SSL_TYPE="${ssl_options[$MENU_SELECTED]}"

  if [[ $SSL_TYPE == "letsencrypt" ]]; then
    # DNS verification
    local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
    local expected_ip="${MAIN_IPV4_CIDR%/*}"

    print_info "Verifying DNS: ${le_fqdn} -> ${expected_ip}"

    local resolved_ip
    resolved_ip=$(dig +short A "$le_fqdn" @1.1.1.1 2>/dev/null | grep -E '^[0-9]+\.' | head -1)

    if [[ $resolved_ip == "$expected_ip" ]]; then
      print_success "SSL:" "Let's Encrypt (DNS verified)"
    else
      print_error "DNS mismatch: ${le_fqdn} -> ${resolved_ip:-not found} (expected: ${expected_ip})"
      print_warning "Let's Encrypt may fail. Falling back to self-signed."
      SSL_TYPE="self-signed"
    fi
  fi

  print_success "SSL:" "$SSL_TYPE"
}

# _edit_tailscale_settings configures Tailscale VPN installation and related flags, prompts for an optional auth key to enable auto-connect and stealth mode, and if disabling a previously enabled Tailscale instance, invokes SSL configuration.
_edit_tailscale_settings() {
  local ts_header="Tailscale provides secure remote access."

  radio_menu \
    "Tailscale VPN" \
    "$ts_header" \
    "Install Tailscale|Recommended for secure access" \
    "Skip|Do not install Tailscale"

  if [[ $MENU_SELECTED -eq 0 ]]; then
    INSTALL_TAILSCALE="yes"
    TAILSCALE_SSH="yes"
    TAILSCALE_WEBUI="yes"

    local auth_content="Auth key enables automatic setup."$'\n'
    auth_content+="Leave empty for manual auth after reboot."
    input_box "Tailscale Auth Key (optional)" "$auth_content" "Auth Key: " "$TAILSCALE_AUTH_KEY"
    TAILSCALE_AUTH_KEY="$INPUT_VALUE"

    if [[ -n $TAILSCALE_AUTH_KEY ]]; then
      TAILSCALE_DISABLE_SSH="yes"
      STEALTH_MODE="yes"
      print_success "Tailscale:" "enabled (auto-connect)"
      print_success "Stealth mode:" "enabled"
    else
      TAILSCALE_DISABLE_SSH="no"
      STEALTH_MODE="no"
      print_warning "Tailscale:" "enabled (manual auth required)"
    fi
  else
    # Check if Tailscale was previously enabled - need to configure SSL
    local was_tailscale_enabled="$INSTALL_TAILSCALE"

    INSTALL_TAILSCALE="no"
    TAILSCALE_AUTH_KEY=""
    TAILSCALE_SSH="no"
    TAILSCALE_WEBUI="no"
    TAILSCALE_DISABLE_SSH="no"
    STEALTH_MODE="no"
    print_success "Tailscale:" "not installed"

    # If Tailscale was enabled before, now need to configure SSL
    if [[ $was_tailscale_enabled == "yes" ]]; then
      echo ""
      print_info "Tailscale disabled - configuring SSL certificate..."
      echo ""
      _edit_ssl_settings
    fi
  fi
}

_edit_optional_settings() {
  # Shell selection
  radio_menu \
    "Default Shell" \
    "Select default shell for root user"$'\n' \
    "ZSH|Modern shell with plugins" \
    "Bash|Standard shell"

  DEFAULT_SHELL=$([ $MENU_SELECTED -eq 0 ] && echo "zsh" || echo "bash")
  print_success "Shell:" "$DEFAULT_SHELL"

  # Power profile
  local governor_options=("performance" "ondemand" "powersave" "schedutil" "conservative")

  radio_menu \
    "Power Profile" \
    "Select CPU frequency scaling"$'\n' \
    "Performance|Max speed" \
    "On-demand|Scale based on load" \
    "Powersave|Min speed" \
    "Schedutil|Kernel scheduler-driven" \
    "Conservative|Gradual scaling"

  CPU_GOVERNOR="${governor_options[$MENU_SELECTED]}"
  print_success "Power profile:" "$CPU_GOVERNOR"

  # Optional packages
  local vnstat_default
  local unattended_default
  local auditd_default
  vnstat_default=$([[ $INSTALL_VNSTAT == "yes" ]] && echo "1" || echo "0")
  unattended_default=$([[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]] && echo "1" || echo "0")
  auditd_default=$([[ $INSTALL_AUDITD == "yes" ]] && echo "1" || echo "0")

  checkbox_menu \
    "Optional Packages" \
    "Select additional packages to install"$'\n' \
    "vnstat|Bandwidth monitoring|${vnstat_default}" \
    "Unattended upgrades|Automatic security updates|${unattended_default}" \
    "auditd|Audit logging|${auditd_default}"

  INSTALL_VNSTAT=$([[ ${CHECKBOX_RESULTS[0]} == "1" ]] && echo "yes" || echo "no")
  INSTALL_UNATTENDED_UPGRADES=$([[ ${CHECKBOX_RESULTS[1]} == "1" ]] && echo "yes" || echo "no")
  INSTALL_AUDITD=$([[ ${CHECKBOX_RESULTS[2]} == "1" ]] && echo "yes" || echo "no")

  print_success "vnstat:" "$INSTALL_VNSTAT"
  print_success "Auto-updates:" "$INSTALL_UNATTENDED_UPGRADES"
  print_success "auditd:" "$INSTALL_AUDITD"
}

_edit_ssh_settings() {
  local ssh_content="Enter your SSH public key."$'\n'
  ssh_content+="Usually from ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub"

  local current_key=""
  if [[ -n $SSH_PUBLIC_KEY ]]; then
    current_key="$SSH_PUBLIC_KEY"
  fi

  input_box "SSH Public Key" "$ssh_content" "SSH Key: " "$current_key"

  if [[ -n $INPUT_VALUE ]]; then
    if validate_ssh_key "$INPUT_VALUE"; then
      SSH_PUBLIC_KEY="$INPUT_VALUE"
      parse_ssh_key "$SSH_PUBLIC_KEY"
      print_success "SSH key:" "${SSH_KEY_TYPE}"
    else
      print_warning "SSH key format may be invalid"
      echo -n "Use anyway? (y/n): "
      read -rsn1 confirm
      echo ""
      if [[ $confirm =~ ^[Yy]$ ]]; then
        SSH_PUBLIC_KEY="$INPUT_VALUE"
        parse_ssh_key "$SSH_PUBLIC_KEY"
        print_success "SSH key:" "${SSH_KEY_TYPE}"
      fi
    fi
  fi
}

# =============================================================================
# Main configuration review loop
# =============================================================================

# Show configuration preview and handle edit/confirm
# show_configuration_review displays the configuration preview and reads a single key to either proceed with installation, open the editor, or cancel the process.
show_configuration_review() {
  while true; do
    # Clear screen for clean display
    clear
    show_banner --no-info

    # Display configuration preview
    display_config_preview

    # Read user action
    local action
    IFS= read -rsn1 action

    case "$action" in
      "" | " ")
        # Enter or Space - proceed with installation
        return 0
        ;;
      e | E)
        # Edit configuration - clear screen first
        clear
        show_banner --no-info
        edit_configuration
        ;;
      q | Q)
        # Quit
        print_info "Installation cancelled by user"
        exit 0
        ;;
      *)
        # Ignore other keys
        ;;
    esac
  done
}
