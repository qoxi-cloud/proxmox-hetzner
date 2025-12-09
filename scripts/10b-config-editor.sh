# shellcheck shell=bash
# =============================================================================
# Interactive configuration editor using gum
# =============================================================================

# Configuration items array for gum choose
# Format: "section|label|value|edit_function"
declare -a CONFIG_ITEMS=()

# Initialize default configuration values
# _init_default_config sets sensible defaults for all configuration options
_init_default_config() {
  # Basic settings
  [[ -z $PVE_HOSTNAME ]] && PVE_HOSTNAME="$DEFAULT_HOSTNAME"
  [[ -z $DOMAIN_SUFFIX ]] && DOMAIN_SUFFIX="$DEFAULT_DOMAIN"
  [[ -z $EMAIL ]] && EMAIL="$DEFAULT_EMAIL"
  [[ -z $TIMEZONE ]] && TIMEZONE="$DEFAULT_TIMEZONE"

  # Password - auto-generate if not set
  if [[ -z $NEW_ROOT_PASSWORD ]]; then
    NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
    PASSWORD_GENERATED="yes"
  fi

  # Network
  [[ -z $BRIDGE_MODE ]] && BRIDGE_MODE="$DEFAULT_BRIDGE_MODE"
  [[ -z $PRIVATE_SUBNET ]] && PRIVATE_SUBNET="$DEFAULT_SUBNET"
  [[ -z $IPV6_MODE ]] && IPV6_MODE="$DEFAULT_IPV6_MODE"
  [[ -z $IPV6_GATEWAY ]] && IPV6_GATEWAY="$DEFAULT_IPV6_GATEWAY"

  # Calculate private network values
  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    PRIVATE_IP="${PRIVATE_CIDR}.1"
    SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
    PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
  fi

  # Storage - set default based on drive count
  if [[ -z $ZFS_RAID ]]; then
    if [[ ${DRIVE_COUNT:-0} -ge 2 ]]; then
      ZFS_RAID="raid1"
    else
      ZFS_RAID="single"
    fi
  fi

  # Proxmox
  [[ -z $PVE_REPO_TYPE ]] && PVE_REPO_TYPE="$DEFAULT_REPO_TYPE"

  # SSL
  [[ -z $SSL_TYPE ]] && SSL_TYPE="$DEFAULT_SSL_TYPE"

  # Tailscale - default to not installed
  [[ -z $INSTALL_TAILSCALE ]] && INSTALL_TAILSCALE="no"

  # Optional features
  [[ -z $DEFAULT_SHELL ]] && DEFAULT_SHELL="zsh"
  [[ -z $CPU_GOVERNOR ]] && CPU_GOVERNOR="$DEFAULT_CPU_GOVERNOR"
  [[ -z $INSTALL_VNSTAT ]] && INSTALL_VNSTAT="yes"
  [[ -z $INSTALL_UNATTENDED_UPGRADES ]] && INSTALL_UNATTENDED_UPGRADES="yes"
  [[ -z $INSTALL_AUDITD ]] && INSTALL_AUDITD="no"

  # SSH key - try to detect from rescue system
  if [[ -z $SSH_PUBLIC_KEY ]]; then
    SSH_PUBLIC_KEY=$(get_rescue_ssh_key 2>/dev/null || true)
  fi

  # Calculate FQDN
  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
}

# Build configuration items list
# _build_config_items populates CONFIG_ITEMS array with current configuration values
_build_config_items() {
  CONFIG_ITEMS=()

  # --- Basic Settings ---
  CONFIG_ITEMS+=("Basic Settings|Hostname|${PVE_HOSTNAME}.${DOMAIN_SUFFIX}|_gum_edit_hostname")
  CONFIG_ITEMS+=("Basic Settings|Email|${EMAIL}|_gum_edit_email")
  local pass_display
  pass_display=$([ "$PASSWORD_GENERATED" == "yes" ] && echo "auto-generated" || echo "********")
  CONFIG_ITEMS+=("Basic Settings|Password|${pass_display}|_gum_edit_password")
  CONFIG_ITEMS+=("Basic Settings|Timezone|${TIMEZONE}|_gum_edit_timezone")

  # --- Network ---
  CONFIG_ITEMS+=("Network|Interface|${INTERFACE_NAME}|_gum_edit_interface")
  CONFIG_ITEMS+=("Network|IPv4|${MAIN_IPV4_CIDR}|")
  CONFIG_ITEMS+=("Network|Gateway|${MAIN_IPV4_GW}|")

  local bridge_desc
  case "$BRIDGE_MODE" in
    internal) bridge_desc="Internal NAT (vmbr0)" ;;
    external) bridge_desc="External bridged (vmbr0)" ;;
    both) bridge_desc="Both (vmbr0=ext, vmbr1=int)" ;;
  esac
  CONFIG_ITEMS+=("Network|Bridge|${bridge_desc}|_gum_edit_bridge")

  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    CONFIG_ITEMS+=("Network|Private subnet|${PRIVATE_SUBNET}|_gum_edit_subnet")
  fi

  # --- IPv6 ---
  local ipv6_display
  case "$IPV6_MODE" in
    disabled)
      ipv6_display="Disabled"
      ;;
    manual)
      ipv6_display="${MAIN_IPV6:-not set}"
      ;;
    auto | *)
      if [[ -n $MAIN_IPV6 ]]; then
        ipv6_display="${MAIN_IPV6} (auto)"
      else
        ipv6_display="Not detected"
      fi
      ;;
  esac
  CONFIG_ITEMS+=("IPv6|IPv6|${ipv6_display}|_gum_edit_ipv6")

  if [[ $IPV6_MODE != "disabled" && -n $MAIN_IPV6 ]]; then
    CONFIG_ITEMS+=("IPv6|IPv6 Gateway|${IPV6_GATEWAY:-fe80::1}|_gum_edit_ipv6_gateway")
  fi

  # --- Storage ---
  local zfs_desc
  case "$ZFS_RAID" in
    raid1) zfs_desc="RAID-1 (mirror)" ;;
    raid0) zfs_desc="RAID-0 (stripe)" ;;
    single) zfs_desc="Single drive" ;;
    *) zfs_desc="$ZFS_RAID" ;;
  esac
  CONFIG_ITEMS+=("Storage|ZFS Mode|${zfs_desc}|_gum_edit_zfs")
  CONFIG_ITEMS+=("Storage|Drives|${DRIVES[*]}|")

  # --- Proxmox ---
  local pve_version
  if [[ -n $PROXMOX_ISO_VERSION ]]; then
    pve_version=$(get_iso_version "$PROXMOX_ISO_VERSION" 2>/dev/null || echo "$PROXMOX_ISO_VERSION")
  else
    pve_version="Latest"
  fi
  CONFIG_ITEMS+=("Proxmox|Version|${pve_version}|_gum_edit_pve_version")
  CONFIG_ITEMS+=("Proxmox|Repository|${PVE_REPO_TYPE:-no-subscription}|_gum_edit_repo")

  # --- SSL ---
  local ssl_display
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    ssl_display="Self-signed (Tailscale HTTPS)"
  else
    ssl_display="${SSL_TYPE:-self-signed}"
  fi
  CONFIG_ITEMS+=("SSL|SSL|${ssl_display}|_gum_edit_ssl")

  # --- VPN ---
  local ts_display
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    if [[ -n $TAILSCALE_AUTH_KEY ]]; then
      ts_display="Enabled (auto-connect)"
    else
      ts_display="Enabled (manual auth)"
    fi
  else
    ts_display="Not installed"
  fi
  CONFIG_ITEMS+=("VPN|Tailscale|${ts_display}|_gum_edit_tailscale")

  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    if [[ $STEALTH_MODE == "yes" ]]; then
      CONFIG_ITEMS+=("VPN|Stealth mode|Enabled|")
    fi
    if [[ $TAILSCALE_DISABLE_SSH == "yes" ]]; then
      CONFIG_ITEMS+=("VPN|OpenSSH|Will be disabled|")
    fi
  fi

  # --- Optional ---
  CONFIG_ITEMS+=("Optional|Shell|${DEFAULT_SHELL:-bash}|_gum_edit_shell")
  CONFIG_ITEMS+=("Optional|Power profile|${CPU_GOVERNOR:-performance}|_gum_edit_governor")

  local features=""
  [[ $INSTALL_VNSTAT == "yes" ]] && features+="vnstat, "
  [[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]] && features+="auto-updates, "
  [[ $INSTALL_AUDITD == "yes" ]] && features+="auditd, "
  features="${features%, }"
  [[ -z $features ]] && features="None"
  CONFIG_ITEMS+=("Optional|Features|${features}|_gum_edit_features")

  # --- SSH ---
  local ssh_display
  if [[ -n $SSH_PUBLIC_KEY ]]; then
    parse_ssh_key "$SSH_PUBLIC_KEY"
    ssh_display="${SSH_KEY_TYPE}"
    if [[ -n $SSH_KEY_COMMENT ]]; then
      ssh_display+=" (${SSH_KEY_COMMENT})"
    fi
  else
    ssh_display="Not configured"
  fi
  CONFIG_ITEMS+=("SSH|SSH Key|${ssh_display}|_gum_edit_ssh")
}

# Build interactive menu with section headers and config items
# Returns formatted strings for gum choose selection
# Section headers are separate lines with --- Section --- format
_build_interactive_menu() {
  _build_config_items

  local prev_section=""

  for item in "${CONFIG_ITEMS[@]}"; do
    local section="${item%%|*}"
    local rest="${item#*|}"
    local label="${rest%%|*}"
    rest="${rest#*|}"
    local value="${rest%%|*}"
    local edit_fn="${rest#*|}"

    # Add section header when section changes
    if [[ $section != "$prev_section" ]]; then
      # Section header line
      printf "${CLR_CYAN}    --- %s ---${CLR_RESET}\n" "$section"
      prev_section="$section"
    fi

    # Build the item line with proper alignment
    local display_line
    if [[ -z $edit_fn ]]; then
      # Non-editable item - gray
      display_line=$(printf "${CLR_GRAY}    %-20s %s${CLR_RESET}" "${label}" "$value")
    else
      # Editable item - white
      display_line=$(printf "    %-20s %s" "${label}" "$value")
    fi

    echo "$display_line"
  done

  echo ""
  echo "${CLR_GREEN}    >>> Start Installation <<<${CLR_RESET}"
}

# Strip ANSI escape codes from string
# Parameters:
#   $1 - String with ANSI codes
# Returns: Clean string without ANSI codes
_strip_ansi() {
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Get edit function for selected menu line
# Parameters:
#   $1 - Selected line from menu (e.g., "    Hostname             pve.local")
# Returns: edit function name (empty if section header or non-editable)
_get_edit_function_from_line() {
  local selected_line="$1"

  # Strip ANSI codes first
  selected_line=$(_strip_ansi "$selected_line")

  # Skip section headers (lines containing "---")
  if [[ $selected_line == *"---"* ]]; then
    return
  fi

  # Extract label from the line
  # Format: "    Label                Value"
  # Trim leading spaces and get first word (the label)
  local selected_label
  selected_label=$(echo "$selected_line" | sed 's/^[[:space:]]*//' | awk '{print $1}')

  for item in "${CONFIG_ITEMS[@]}"; do
    local rest="${item#*|}"
    local label="${rest%%|*}"
    rest="${rest#*|}"
    local edit_fn="${rest#*|}"

    if [[ $label == "$selected_label" ]]; then
      echo "$edit_fn"
      return
    fi
  done
}

# =============================================================================
# Edit functions using gum
# =============================================================================

_gum_edit_hostname() {
  local new_hostname
  new_hostname=$(gum input \
    --placeholder "Enter hostname (e.g., pve, proxmox)" \
    --value "$PVE_HOSTNAME" \
    --prompt "Hostname: " \
    --prompt.foreground "$HEX_ORANGE" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40)

  if [[ -n $new_hostname ]] && validate_hostname "$new_hostname"; then
    PVE_HOSTNAME="$new_hostname"
    FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
  elif [[ -n $new_hostname ]]; then
    gum style --foreground "$HEX_RED" "Invalid hostname format"
    sleep 1
  fi

  # Domain
  local new_domain
  new_domain=$(gum input \
    --placeholder "Enter domain (e.g., local, example.com)" \
    --value "$DOMAIN_SUFFIX" \
    --prompt "Domain: " \
    --prompt.foreground "$HEX_ORANGE" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40)

  if [[ -n $new_domain ]]; then
    DOMAIN_SUFFIX="$new_domain"
    FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
  fi
}

_gum_edit_email() {
  local new_email
  new_email=$(gum input \
    --placeholder "Enter email address" \
    --value "$EMAIL" \
    --prompt "Email: " \
    --prompt.foreground "$HEX_ORANGE" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 50)

  if [[ -n $new_email ]] && validate_email "$new_email"; then
    EMAIL="$new_email"
  elif [[ -n $new_email ]]; then
    gum style --foreground "$HEX_RED" "Invalid email format"
    sleep 1
  fi
}

_gum_edit_password() {
  local new_password
  new_password=$(gum input \
    --password \
    --placeholder "Enter new password (empty to auto-generate)" \
    --prompt "Password: " \
    --prompt.foreground "$HEX_ORANGE" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40)

  if [[ -z $new_password ]]; then
    NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
    PASSWORD_GENERATED="yes"
  else
    local password_error
    password_error=$(get_password_error "$new_password")
    if [[ -n $password_error ]]; then
      gum style --foreground "$HEX_RED" "$password_error"
      sleep 2
    else
      NEW_ROOT_PASSWORD="$new_password"
      PASSWORD_GENERATED="no"
    fi
  fi
}

_gum_edit_timezone() {
  local tz_options="Europe/Kyiv
Europe/London
Europe/Berlin
America/New_York
America/Los_Angeles
Asia/Tokyo
UTC
Custom..."

  local selected
  selected=$(echo "$tz_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select timezone:" \
    --header.foreground "$HEX_GRAY")

  if [[ $selected == "Custom..." ]]; then
    local custom_tz
    custom_tz=$(gum input \
      --placeholder "Enter timezone (e.g., Europe/Paris)" \
      --value "$TIMEZONE" \
      --prompt "Timezone: " \
      --prompt.foreground "$HEX_ORANGE" \
      --cursor.foreground "$HEX_ORANGE" \
      --width 40)

    if [[ -n $custom_tz ]] && validate_timezone "$custom_tz"; then
      TIMEZONE="$custom_tz"
    elif [[ -n $custom_tz ]]; then
      gum style --foreground "$HEX_RED" "Invalid timezone format"
      sleep 1
    fi
  elif [[ -n $selected ]]; then
    TIMEZONE="$selected"
  fi
}

_gum_edit_interface() {
  local new_iface
  new_iface=$(gum input \
    --placeholder "Enter interface name (e.g., enp0s31f6)" \
    --value "$INTERFACE_NAME" \
    --prompt "Interface: " \
    --prompt.foreground "$HEX_ORANGE" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40)

  if [[ -n $new_iface ]]; then
    INTERFACE_NAME="$new_iface"
  fi
}

_gum_edit_bridge() {
  local bridge_options="Internal only (NAT)
External only (Bridged)
Both bridges"

  local selected
  selected=$(echo "$bridge_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select bridge mode:" \
    --header.foreground "$HEX_GRAY")

  case "$selected" in
    "Internal only (NAT)") BRIDGE_MODE="internal" ;;
    "External only (Bridged)") BRIDGE_MODE="external" ;;
    "Both bridges") BRIDGE_MODE="both" ;;
  esac

  # If switching to internal/both, ensure subnet is set
  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    if [[ -z $PRIVATE_SUBNET ]]; then
      PRIVATE_SUBNET="$DEFAULT_SUBNET"
    fi
    # Recalculate private network values
    PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    PRIVATE_IP="${PRIVATE_CIDR}.1"
    SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
    PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
  fi
}

_gum_edit_subnet() {
  local subnet_options="10.0.0.0/24
192.168.1.0/24
172.16.0.0/24
Custom..."

  local selected
  selected=$(echo "$subnet_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select private subnet:" \
    --header.foreground "$HEX_GRAY")

  if [[ $selected == "Custom..." ]]; then
    local custom_subnet
    custom_subnet=$(gum input \
      --placeholder "Enter subnet (e.g., 10.0.0.0/24)" \
      --value "$PRIVATE_SUBNET" \
      --prompt "Subnet: " \
      --prompt.foreground "$HEX_ORANGE" \
      --cursor.foreground "$HEX_ORANGE" \
      --width 40)

    if [[ -n $custom_subnet ]] && validate_subnet "$custom_subnet"; then
      PRIVATE_SUBNET="$custom_subnet"
    elif [[ -n $custom_subnet ]]; then
      gum style --foreground "$HEX_RED" "Invalid subnet format"
      sleep 1
      return
    fi
  elif [[ -n $selected ]]; then
    PRIVATE_SUBNET="$selected"
  fi

  # Recalculate private network values
  if [[ -n $PRIVATE_SUBNET ]]; then
    PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    PRIVATE_IP="${PRIVATE_CIDR}.1"
    SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
    PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
  fi
}

_gum_edit_ipv6() {
  local ipv6_options="Auto (use detected)
Manual
Disabled"

  local selected
  selected=$(echo "$ipv6_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select IPv6 mode:" \
    --header.foreground "$HEX_GRAY")

  case "$selected" in
    "Auto (use detected)")
      IPV6_MODE="auto"
      IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
      ;;
    "Manual")
      IPV6_MODE="manual"
      local new_ipv6
      new_ipv6=$(gum input \
        --placeholder "Enter IPv6 address with CIDR (e.g., 2001:db8::1/64)" \
        --value "${MAIN_IPV6:+${MAIN_IPV6}/64}" \
        --prompt "IPv6: " \
        --prompt.foreground "$HEX_ORANGE" \
        --cursor.foreground "$HEX_ORANGE" \
        --width 50)

      if [[ -n $new_ipv6 ]] && validate_ipv6_cidr "$new_ipv6"; then
        IPV6_ADDRESS="$new_ipv6"
        MAIN_IPV6="${new_ipv6%/*}"
      elif [[ -n $new_ipv6 ]]; then
        gum style --foreground "$HEX_RED" "Invalid IPv6 CIDR format"
        sleep 1
      fi

      local new_gw
      new_gw=$(gum input \
        --placeholder "Enter IPv6 gateway (e.g., fe80::1)" \
        --value "${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}" \
        --prompt "Gateway: " \
        --prompt.foreground "$HEX_ORANGE" \
        --cursor.foreground "$HEX_ORANGE" \
        --width 50)

      if [[ -n $new_gw ]] && validate_ipv6_gateway "$new_gw"; then
        IPV6_GATEWAY="$new_gw"
      elif [[ -n $new_gw ]]; then
        gum style --foreground "$HEX_RED" "Invalid IPv6 gateway"
        sleep 1
      fi
      ;;
    "Disabled")
      IPV6_MODE="disabled"
      MAIN_IPV6=""
      IPV6_GATEWAY=""
      FIRST_IPV6_CIDR=""
      ;;
  esac
}

_gum_edit_ipv6_gateway() {
  local new_gw
  new_gw=$(gum input \
    --placeholder "Enter IPv6 gateway (e.g., fe80::1)" \
    --value "${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}" \
    --prompt "IPv6 Gateway: " \
    --prompt.foreground "$HEX_ORANGE" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 50)

  if [[ -n $new_gw ]] && validate_ipv6_gateway "$new_gw"; then
    IPV6_GATEWAY="$new_gw"
  elif [[ -n $new_gw ]]; then
    gum style --foreground "$HEX_RED" "Invalid IPv6 gateway"
    sleep 1
  fi
}

_gum_edit_zfs() {
  if [[ ${DRIVE_COUNT:-0} -lt 2 ]]; then
    gum style --foreground "$HEX_YELLOW" "Only one drive detected - RAID options not available"
    sleep 2
    return
  fi

  local zfs_options="RAID-1 (mirror)
RAID-0 (stripe)
Single drive"

  local selected
  selected=$(echo "$zfs_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select ZFS mode:" \
    --header.foreground "$HEX_GRAY")

  case "$selected" in
    "RAID-1 (mirror)") ZFS_RAID="raid1" ;;
    "RAID-0 (stripe)") ZFS_RAID="raid0" ;;
    "Single drive") ZFS_RAID="single" ;;
  esac
}

_gum_edit_pve_version() {
  # Fetch available versions if not already cached
  if [[ -z $PROXMOX_ISO_LIST ]]; then
    local iso_list
    get_available_proxmox_isos 5 >/tmp/iso_list.tmp &
    gum spin --spinner dot --title "Fetching available Proxmox versions..." -- wait $!
    iso_list=$(cat /tmp/iso_list.tmp 2>/dev/null)
    rm -f /tmp/iso_list.tmp
    PROXMOX_ISO_LIST="$iso_list"
  fi

  if [[ -z $PROXMOX_ISO_LIST ]]; then
    gum style --foreground "$HEX_YELLOW" "Could not fetch ISO list"
    sleep 1
    return
  fi

  # Build options from ISO list
  local options=""
  local first=true
  while IFS= read -r iso; do
    local version
    version=$(get_iso_version "$iso")
    if [[ $first == true ]]; then
      options+="${version} (Latest)\n"
      first=false
    else
      options+="${version}\n"
    fi
  done <<<"$PROXMOX_ISO_LIST"

  local selected
  selected=$(echo -e "$options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select Proxmox version:" \
    --header.foreground "$HEX_GRAY")

  if [[ -n $selected ]]; then
    # Extract version number and find matching ISO
    local selected_version="${selected%% *}"
    while IFS= read -r iso; do
      local version
      version=$(get_iso_version "$iso")
      if [[ $version == "$selected_version" ]]; then
        PROXMOX_ISO_VERSION="$iso"
        break
      fi
    done <<<"$PROXMOX_ISO_LIST"
  fi
}

_gum_edit_repo() {
  local repo_options="no-subscription
enterprise
test"

  local selected
  selected=$(echo "$repo_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select repository:" \
    --header.foreground "$HEX_GRAY")

  if [[ -n $selected ]]; then
    PVE_REPO_TYPE="$selected"

    if [[ $PVE_REPO_TYPE == "enterprise" ]]; then
      local new_key
      new_key=$(gum input \
        --placeholder "Enter subscription key (pve1c-XXXXXXXXXX)" \
        --value "$PVE_SUBSCRIPTION_KEY" \
        --prompt "Key: " \
        --prompt.foreground "$HEX_ORANGE" \
        --cursor.foreground "$HEX_ORANGE" \
        --width 50)

      PVE_SUBSCRIPTION_KEY="$new_key"
    else
      PVE_SUBSCRIPTION_KEY=""
    fi
  fi
}

_gum_edit_ssl() {
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    gum style --foreground "$HEX_GRAY" "SSL is managed by Tailscale when VPN is enabled"
    sleep 1
    return
  fi

  local ssl_options="self-signed
letsencrypt"

  local selected
  selected=$(echo "$ssl_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select SSL type:" \
    --header.foreground "$HEX_GRAY")

  if [[ -n $selected ]]; then
    SSL_TYPE="$selected"

    if [[ $SSL_TYPE == "letsencrypt" ]]; then
      gum style --foreground "$HEX_YELLOW" "Note: DNS must be configured for Let's Encrypt to work"
      sleep 2
    fi
  fi
}

_gum_edit_tailscale() {
  local ts_options="Install Tailscale
Skip installation"

  local selected
  selected=$(echo "$ts_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Tailscale VPN:" \
    --header.foreground "$HEX_GRAY")

  if [[ $selected == "Install Tailscale" ]]; then
    INSTALL_TAILSCALE="yes"
    TAILSCALE_SSH="yes"
    TAILSCALE_WEBUI="yes"

    local auth_key
    auth_key=$(gum input \
      --placeholder "Enter auth key (optional, for auto-connect)" \
      --value "$TAILSCALE_AUTH_KEY" \
      --prompt "Auth Key: " \
      --prompt.foreground "$HEX_ORANGE" \
      --cursor.foreground "$HEX_ORANGE" \
      --width 60)

    TAILSCALE_AUTH_KEY="$auth_key"

    if [[ -n $TAILSCALE_AUTH_KEY ]]; then
      TAILSCALE_DISABLE_SSH="yes"
      STEALTH_MODE="yes"
    else
      TAILSCALE_DISABLE_SSH="no"
      STEALTH_MODE="no"
    fi
  else
    # If disabling Tailscale, need to configure SSL
    local was_enabled="$INSTALL_TAILSCALE"

    INSTALL_TAILSCALE="no"
    TAILSCALE_AUTH_KEY=""
    TAILSCALE_SSH="no"
    TAILSCALE_WEBUI="no"
    TAILSCALE_DISABLE_SSH="no"
    STEALTH_MODE="no"

    if [[ $was_enabled == "yes" ]]; then
      _gum_edit_ssl
    fi
  fi
}

_gum_edit_shell() {
  local shell_options="zsh
bash"

  local selected
  selected=$(echo "$shell_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select default shell:" \
    --header.foreground "$HEX_GRAY")

  if [[ -n $selected ]]; then
    DEFAULT_SHELL="$selected"
  fi
}

_gum_edit_governor() {
  local gov_options="performance
ondemand
powersave
schedutil
conservative"

  local selected
  selected=$(echo "$gov_options" | gum choose \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_ORANGE" \
    --header "Select power profile:" \
    --header.foreground "$HEX_GRAY")

  if [[ -n $selected ]]; then
    CPU_GOVERNOR="$selected"
  fi
}

_gum_edit_features() {
  local features_list="vnstat (bandwidth monitoring)
auto-updates (unattended upgrades)
auditd (audit logging)"

  # Build selected flags for gum choose
  local -a gum_args=()
  gum_args+=(--no-limit)
  gum_args+=(--cursor.foreground "$HEX_ORANGE")
  gum_args+=(--selected.foreground "$HEX_GREEN")
  gum_args+=(--header "Select features (Space to toggle):")
  gum_args+=(--header.foreground "$HEX_GRAY")

  # Add --selected for each currently enabled feature
  [[ $INSTALL_VNSTAT == "yes" ]] && gum_args+=(--selected "vnstat (bandwidth monitoring)")
  [[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]] && gum_args+=(--selected "auto-updates (unattended upgrades)")
  [[ $INSTALL_AUDITD == "yes" ]] && gum_args+=(--selected "auditd (audit logging)")

  local selected
  selected=$(echo "$features_list" | gum choose "${gum_args[@]}")

  # Parse results
  INSTALL_VNSTAT="no"
  INSTALL_UNATTENDED_UPGRADES="no"
  INSTALL_AUDITD="no"

  while IFS= read -r line; do
    case "$line" in
      *vnstat*) INSTALL_VNSTAT="yes" ;;
      *auto-updates*) INSTALL_UNATTENDED_UPGRADES="yes" ;;
      *auditd*) INSTALL_AUDITD="yes" ;;
    esac
  done <<<"$selected"
}

_gum_edit_ssh() {
  local new_key
  new_key=$(gum input \
    --placeholder "Paste SSH public key" \
    --value "$SSH_PUBLIC_KEY" \
    --prompt "SSH Key: " \
    --prompt.foreground "$HEX_ORANGE" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 80)

  if [[ -n $new_key ]]; then
    if validate_ssh_key "$new_key"; then
      SSH_PUBLIC_KEY="$new_key"
      parse_ssh_key "$SSH_PUBLIC_KEY"
    else
      if gum confirm "SSH key format may be invalid. Use anyway?" \
        --affirmative "Yes" \
        --negative "No" \
        --prompt.foreground "$HEX_YELLOW"; then
        SSH_PUBLIC_KEY="$new_key"
        parse_ssh_key "$SSH_PUBLIC_KEY"
      fi
    fi
  fi
}

# =============================================================================
# Main interactive configuration loop
# =============================================================================

# show_gum_config_editor displays interactive configuration editor using gum
# Clears screen, shows logo, then presents editable configuration table
# Replaces the old get_system_inputs flow
show_gum_config_editor() {
  # Initialize network detection first
  detect_network_interface
  collect_network_info

  # Initialize default configuration values
  _init_default_config

  while true; do
    # Clear screen and show logo
    clear
    show_banner

    echo ""
    gum style --foreground "$HEX_ORANGE" --bold -- "Configuration"
    echo ""

    # Build interactive menu content
    local menu_content
    menu_content=$(_build_interactive_menu)

    # Use gum choose with the menu content
    local selected
    selected=$(echo "$menu_content" | gum choose \
      --cursor "› " \
      --cursor.foreground "$HEX_ORANGE" \
      --selected.foreground "$HEX_WHITE" \
      --header.foreground "$HEX_GRAY" \
      --height 35)

    # Skip if empty line or section header selected
    local selected_clean
    selected_clean=$(_strip_ansi "$selected")
    if [[ -z $selected_clean || $selected_clean =~ ^[[:space:]]*$ || $selected_clean == *"---"* ]]; then
      continue
    fi

    # Check if done
    if [[ $selected_clean == *"Start Installation"* ]]; then
      # Validate required fields before proceeding
      if [[ -z $SSH_PUBLIC_KEY ]]; then
        gum style --foreground "$HEX_RED" -- "SSH key is required for secure access!"
        sleep 2
        continue
      fi
      return 0
    fi

    # Get and execute edit function
    local edit_fn
    edit_fn=$(_get_edit_function_from_line "$selected")

    if [[ -n $edit_fn ]]; then
      clear
      show_banner
      echo ""
      $edit_fn
    fi
  done
}
