# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - UI Rendering Helpers
# =============================================================================

# =============================================================================
# Key reading helper
# =============================================================================

# Read a single key press (handles arrow keys as escape sequences)
# Returns: Key name in WIZ_KEY variable
_wiz_read_key() {
  local key
  IFS= read -rsn1 key

  # Handle escape sequences (arrow keys)
  if [[ $key == $'\x1b' ]]; then
    read -rsn2 -t 0.1 key
    case "$key" in
      '[A') WIZ_KEY="up" ;;
      '[B') WIZ_KEY="down" ;;
      '[C') WIZ_KEY="right" ;;
      '[D') WIZ_KEY="left" ;;
      *) WIZ_KEY="esc" ;;
    esac
  elif [[ $key == "" ]]; then
    WIZ_KEY="enter"
  elif [[ $key == "q" || $key == "Q" ]]; then
    WIZ_KEY="quit"
  elif [[ $key == "s" || $key == "S" ]]; then
    WIZ_KEY="start"
  else
    WIZ_KEY="$key"
  fi
}

# =============================================================================
# UI rendering helpers
# =============================================================================

# Hide/show cursor
_wiz_hide_cursor() { printf '\033[?25l'; }
_wiz_show_cursor() { printf '\033[?25h'; }

# Format value for display - shows placeholder if empty
# Parameters:
#   $1 - value to display
#   $2 - placeholder text (default: "→ set value")
_wiz_fmt() {
  local value="$1"
  local placeholder="${2:-→ set value}"
  if [[ -n $value ]]; then
    echo "$value"
  else
    echo "${CLR_GRAY}${placeholder}${CLR_RESET}"
  fi
}

# Menu item indices (for mapping selection to edit functions)
# These track which items are selectable fields vs section headers
_WIZ_FIELD_COUNT=0
_WIZ_FIELD_MAP=()

# Render the main menu with current selection highlighted
# Parameters:
#   $1 - Current selection index (0-based, only counts selectable fields)
_wiz_render_menu() {
  local selection="$1"
  local output=""

  # Always clear and redraw (simple approach for maximum compatibility)
  clear
  show_banner
  echo ""

  # Build display values
  local pass_display=""
  if [[ -n $NEW_ROOT_PASSWORD ]]; then
    pass_display=$([[ $PASSWORD_GENERATED == "yes" ]] && echo "(auto-generated)" || echo "********")
  fi

  local ipv6_display=""
  if [[ -n $IPV6_MODE ]]; then
    case "$IPV6_MODE" in
      auto)
        ipv6_display="Auto"
        if [[ -n $MAIN_IPV6 ]]; then
          ipv6_display+=" (${MAIN_IPV6})"
        fi
        ;;
      manual)
        ipv6_display="Manual"
        if [[ -n $MAIN_IPV6 ]]; then
          ipv6_display+=" (${MAIN_IPV6}, gw: ${IPV6_GATEWAY})"
        fi
        ;;
      disabled) ipv6_display="Disabled" ;;
      *) ipv6_display="$IPV6_MODE" ;;
    esac
  fi

  local tailscale_display=""
  if [[ -n $INSTALL_TAILSCALE ]]; then
    if [[ $INSTALL_TAILSCALE == "yes" ]]; then
      tailscale_display="Enabled + Stealth"
    else
      tailscale_display="Disabled"
    fi
  fi

  local features_display="none"
  if [[ -n $INSTALL_VNSTAT || -n $INSTALL_AUDITD || -n $INSTALL_YAZI || -n $INSTALL_NVIM ]]; then
    features_display=""
    [[ $INSTALL_VNSTAT == "yes" ]] && features_display+="vnstat"
    [[ $INSTALL_AUDITD == "yes" ]] && features_display+="${features_display:+, }auditd"
    [[ $INSTALL_YAZI == "yes" ]] && features_display+="${features_display:+, }yazi"
    [[ $INSTALL_NVIM == "yes" ]] && features_display+="${features_display:+, }nvim"
    [[ -z $features_display ]] && features_display="none"
  fi

  local ssh_display=""
  if [[ -n $SSH_PUBLIC_KEY ]]; then
    # Show first 20 chars of key type and fingerprint hint
    ssh_display="${SSH_PUBLIC_KEY:0:20}..."
  fi

  local iso_version_display=""
  if [[ -n $PROXMOX_ISO_VERSION ]]; then
    iso_version_display=$(get_iso_version "$PROXMOX_ISO_VERSION")
  fi

  local hostname_display=""
  if [[ -n $PVE_HOSTNAME && -n $DOMAIN_SUFFIX ]]; then
    hostname_display="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
  fi

  # Reset field map
  _WIZ_FIELD_MAP=()
  local field_idx=0

  # Helper to add section header
  _add_section() {
    output+="${CLR_CYAN}--- $1 ---${CLR_RESET}\n"
  }

  # Helper to add field
  _add_field() {
    local label="$1"
    local value="$2"
    local field_name="$3"
    _WIZ_FIELD_MAP+=("$field_name")
    if [[ $field_idx -eq $selection ]]; then
      output+="${CLR_ORANGE}›${CLR_RESET} ${CLR_GRAY}${label}${CLR_RESET}${value}\n"
    else
      output+="  ${CLR_GRAY}${label}${CLR_RESET}${value}\n"
    fi
    ((field_idx++))
  }

  # --- Basic Settings ---
  _add_section "Basic Settings"
  _add_field "Hostname         " "$(_wiz_fmt "$hostname_display")" "hostname"
  _add_field "Email            " "$(_wiz_fmt "$EMAIL")" "email"
  _add_field "Password         " "$(_wiz_fmt "$pass_display")" "password"
  _add_field "Timezone         " "$(_wiz_fmt "$TIMEZONE")" "timezone"
  _add_field "Keyboard         " "$(_wiz_fmt "$KEYBOARD")" "keyboard"
  _add_field "Country          " "$(_wiz_fmt "$COUNTRY")" "country"

  # --- Proxmox ---
  _add_section "Proxmox"
  _add_field "Version          " "$(_wiz_fmt "$iso_version_display")" "iso_version"
  _add_field "Repository       " "$(_wiz_fmt "$PVE_REPO_TYPE")" "repository"

  # --- Network ---
  _add_section "Network"
  # Show interface selector only if multiple interfaces available
  if [[ ${INTERFACE_COUNT:-1} -gt 1 ]]; then
    _add_field "Interface        " "$(_wiz_fmt "$INTERFACE_NAME")" "interface"
  fi
  _add_field "Bridge mode      " "$(_wiz_fmt "$BRIDGE_MODE")" "bridge_mode"
  _add_field "Private subnet   " "$(_wiz_fmt "$PRIVATE_SUBNET")" "private_subnet"
  _add_field "IPv6             " "$(_wiz_fmt "$ipv6_display")" "ipv6"

  # --- Storage ---
  _add_section "Storage"
  _add_field "ZFS mode         " "$(_wiz_fmt "$ZFS_RAID")" "zfs_mode"

  # --- VPN ---
  _add_section "VPN"
  _add_field "Tailscale        " "$(_wiz_fmt "$tailscale_display")" "tailscale"

  # --- SSL --- (hidden when Tailscale enabled - uses Tailscale certs)
  if [[ $INSTALL_TAILSCALE != "yes" ]]; then
    _add_section "SSL"
    _add_field "Certificate      " "$(_wiz_fmt "$SSL_TYPE")" "ssl"
  fi

  # --- Optional ---
  _add_section "Optional"
  _add_field "Shell            " "$(_wiz_fmt "$SHELL_TYPE")" "shell"
  _add_field "Power profile    " "$(_wiz_fmt "$CPU_GOVERNOR")" "power_profile"
  _add_field "Features         " "$(_wiz_fmt "$features_display")" "features"

  # --- SSH ---
  _add_section "SSH"
  _add_field "SSH Key          " "$(_wiz_fmt "$ssh_display")" "ssh_key"

  # Store total field count
  _WIZ_FIELD_COUNT=$field_idx

  output+="\n"

  # Footer
  output+="${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] edit  [${CLR_ORANGE}S${CLR_GRAY}] start  [${CLR_ORANGE}Q${CLR_GRAY}] quit${CLR_RESET}"

  # Output everything at once
  echo -e "$output"
}
