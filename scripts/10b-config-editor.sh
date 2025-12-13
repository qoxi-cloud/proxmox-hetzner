# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Step-by-step configuration with manual UI rendering
# =============================================================================
# Uses manual rendering + key capture instead of gum choose for main menu.
# Edit screens use gum input/choose for actual input.

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
      auto) ipv6_display="Auto" ;;
      manual) ipv6_display="Manual" ;;
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

  local features_display=""
  if [[ -n $INSTALL_VNSTAT || -n $INSTALL_AUDITD ]]; then
    [[ $INSTALL_VNSTAT == "yes" ]] && features_display+="vnstat"
    [[ $INSTALL_AUDITD == "yes" ]] && features_display+="${features_display:+, }auditd"
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
  output+="${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] edit  [${CLR_ORANGE}Q${CLR_GRAY}] quit${CLR_RESET}"

  # Output everything at once
  echo -e "$output"
}

# =============================================================================
# Main wizard loop
# =============================================================================

_wizard_main() {
  local selection=0

  while true; do
    _wiz_render_menu "$selection"
    _wiz_read_key

    case "$WIZ_KEY" in
      up)
        if [[ $selection -gt 0 ]]; then
          ((selection--))
        fi
        ;;
      down)
        if [[ $selection -lt $((_WIZ_FIELD_COUNT - 1)) ]]; then
          ((selection++))
        fi
        ;;
      enter)
        # Show cursor for edit screens
        _wiz_show_cursor
        # Edit selected field based on field map
        local field_name="${_WIZ_FIELD_MAP[$selection]}"
        case "$field_name" in
          hostname) _edit_hostname ;;
          email) _edit_email ;;
          password) _edit_password ;;
          timezone) _edit_timezone ;;
          iso_version) _edit_iso_version ;;
          repository) _edit_repository ;;
          interface) _edit_interface ;;
          bridge_mode) _edit_bridge_mode ;;
          private_subnet) _edit_private_subnet ;;
          ipv6) _edit_ipv6 ;;
          zfs_mode) _edit_zfs_mode ;;
          tailscale) _edit_tailscale ;;
          ssl) _edit_ssl ;;
          shell) _edit_shell ;;
          power_profile) _edit_power_profile ;;
          features) _edit_features ;;
          ssh_key) _edit_ssh_key ;;
        esac
        # Hide cursor again
        _wiz_hide_cursor
        ;;
      quit | esc)
        _wiz_show_cursor
        if gum confirm "Quit installation?" --default=false \
          --prompt.foreground "$HEX_ORANGE" \
          --selected.background "$HEX_ORANGE"; then
          exit 0
        fi
        # Hide cursor again
        _wiz_hide_cursor
        ;;
    esac
  done
}

# =============================================================================
# Edit screen helpers
# =============================================================================

# Display footer with key hints below current cursor position
# Parameters:
#   $1 - type: "input" (default), "filter", or "checkbox"
#   $2 - lines for component (default: 1 for input, used for filter/checkbox height)
_show_input_footer() {
  local type="${1:-input}"
  local component_lines="${2:-1}"

  # Print empty lines for component space
  local i
  for ((i = 0; i < component_lines; i++)); do
    echo ""
  done

  # Blank line + footer
  echo ""
  case "$type" in
    filter)
      echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
    checkbox)
      echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Space${CLR_GRAY}] toggle  [${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
    *)
      echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
  esac

  # Move cursor back up: component_lines + 1 blank + 1 footer
  tput cuu $((component_lines + 2))
}

# =============================================================================
# Edit functions - each clears screen, shows banner, then input field
# =============================================================================

_edit_hostname() {
  clear
  show_banner
  echo ""
  _show_input_footer

  local new_hostname
  new_hostname=$(gum input \
    --placeholder "e.g., pve, proxmox, node1" \
    --value "$PVE_HOSTNAME" \
    --prompt "Hostname: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40 \
    --no-show-help)

  if [[ -n $new_hostname ]]; then
    if validate_hostname "$new_hostname"; then
      PVE_HOSTNAME="$new_hostname"
    else
      echo ""
      gum style --foreground "$HEX_RED" "Invalid hostname format"
      sleep 1
      return
    fi
  fi

  # Edit domain
  clear
  show_banner
  echo ""
  _show_input_footer

  local new_domain
  new_domain=$(gum input \
    --placeholder "e.g., local, example.com" \
    --value "$DOMAIN_SUFFIX" \
    --prompt "Domain: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40 \
    --no-show-help)

  if [[ -n $new_domain ]]; then
    DOMAIN_SUFFIX="$new_domain"
  fi

  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
}

_edit_email() {
  clear
  show_banner
  echo ""
  _show_input_footer

  local new_email
  new_email=$(gum input \
    --placeholder "admin@example.com" \
    --value "$EMAIL" \
    --prompt "Email: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 50 \
    --no-show-help)

  if [[ -n $new_email ]]; then
    if validate_email "$new_email"; then
      EMAIL="$new_email"
    else
      echo ""
      echo ""
      gum style --foreground "$HEX_RED" "Invalid email format"
      sleep 1
    fi
  fi
}

_edit_password() {
  clear
  show_banner
  echo ""
  gum style --foreground "$HEX_GRAY" "Leave empty to auto-generate a secure password"
  echo ""
  _show_input_footer

  local new_password
  new_password=$(gum input \
    --password \
    --placeholder "Enter password or leave empty" \
    --prompt "Password: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40 \
    --no-show-help)

  if [[ -z $new_password ]]; then
    NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
    PASSWORD_GENERATED="yes"
    echo ""
    echo ""
    gum style --foreground "$HEX_GREEN" "Password auto-generated"
    sleep 1
  else
    local password_error
    password_error=$(get_password_error "$new_password")
    if [[ -n $password_error ]]; then
      echo ""
      echo ""
      gum style --foreground "$HEX_RED" "$password_error"
      sleep 2
    else
      NEW_ROOT_PASSWORD="$new_password"
      PASSWORD_GENERATED="no"
    fi
  fi
}

_edit_timezone() {
  clear
  show_banner
  echo ""

  # Footer for filter: height=5 items + 1 input line = 6 lines for component
  _show_input_footer "filter" 6

  local selected
  selected=$(echo "$WIZ_TIMEZONES" | gum filter \
    --placeholder "Type to search..." \
    --indicator "›" \
    --height 5 \
    --no-show-help \
    --prompt "Timezone: " \
    --prompt.foreground "$HEX_CYAN" \
    --indicator.foreground "$HEX_ORANGE" \
    --match.foreground "$HEX_ORANGE")

  if [[ -n $selected ]]; then
    TIMEZONE="$selected"
  fi
}

_edit_iso_version() {
  clear
  show_banner
  echo ""

  # Get available ISO versions (last 5, uses cached data from prefetch)
  local iso_list
  iso_list=$(get_available_proxmox_isos 5)

  if [[ -z $iso_list ]]; then
    gum style --foreground "$HEX_RED" "Failed to fetch ISO list"
    sleep 2
    return
  fi

  # 1 header + 5 items for gum choose
  _show_input_footer "filter" 6

  local selected
  selected=$(echo "$iso_list" | gum choose \
    --header="Proxmox Version:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && PROXMOX_ISO_VERSION="$selected"
}

_edit_repository() {
  clear
  show_banner
  echo ""

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  local selected
  selected=$(echo "$WIZ_REPO_TYPES" | gum choose \
    --header="Repository:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  if [[ -n $selected ]]; then
    PVE_REPO_TYPE="$selected"

    # If enterprise selected, optionally ask for subscription key
    if [[ $selected == "enterprise" ]]; then
      clear
      show_banner
      echo ""
      gum style --foreground "$HEX_GRAY" "Enter Proxmox subscription key (optional)"
      echo ""
      _show_input_footer

      local sub_key
      sub_key=$(gum input \
        --placeholder "pve2c-..." \
        --value "$PVE_SUBSCRIPTION_KEY" \
        --prompt "Subscription Key: " \
        --prompt.foreground "$HEX_CYAN" \
        --cursor.foreground "$HEX_ORANGE" \
        --width 60 \
        --no-show-help)

      PVE_SUBSCRIPTION_KEY="$sub_key"
    else
      # Clear subscription key if not enterprise
      PVE_SUBSCRIPTION_KEY=""
    fi
  fi
}

_edit_interface() {
  clear
  show_banner
  echo ""

  # Get available interfaces (use cached value)
  local interface_count=${INTERFACE_COUNT:-1}
  local available_interfaces=${AVAILABLE_INTERFACES:-$INTERFACE_NAME}

  # Calculate footer size: 1 header + number of interfaces
  local footer_size=$((interface_count + 1))
  _show_input_footer "filter" "$footer_size"

  local selected
  selected=$(echo "$available_interfaces" | gum choose \
    --header="Network Interface:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && INTERFACE_NAME="$selected"
}

_edit_bridge_mode() {
  clear
  show_banner
  echo ""

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  local selected
  selected=$(echo "$WIZ_BRIDGE_MODES" | gum choose \
    --header="Bridge mode:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && BRIDGE_MODE="$selected"
}

_edit_private_subnet() {
  clear
  show_banner
  echo ""
  _show_input_footer

  local new_subnet
  new_subnet=$(gum input \
    --placeholder "e.g., 10.10.10.0/24" \
    --value "$PRIVATE_SUBNET" \
    --prompt "Private subnet: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40 \
    --no-show-help)

  if [[ -n $new_subnet ]]; then
    if validate_subnet "$new_subnet"; then
      PRIVATE_SUBNET="$new_subnet"
    else
      echo ""
      echo ""
      gum style --foreground "$HEX_RED" "Invalid subnet format"
      sleep 1
    fi
  fi
}

_edit_ipv6() {
  clear
  show_banner
  echo ""

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  local selected
  selected=$(echo "$WIZ_IPV6_MODES" | gum choose \
    --header="IPv6:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && IPV6_MODE="$selected"
}

_edit_zfs_mode() {
  clear
  show_banner
  echo ""

  # Start with base ZFS modes, add more based on drive count
  local options="$WIZ_ZFS_MODES"
  if [[ ${DRIVE_COUNT:-0} -ge 3 ]]; then
    options+="\nraid5"
  fi
  if [[ ${DRIVE_COUNT:-0} -ge 4 ]]; then
    options+="\nraid10"
  fi

  # Count options (2-4 items depending on drives) + 1 header
  local item_count=3
  [[ ${DRIVE_COUNT:-0} -ge 3 ]] && item_count=4
  [[ ${DRIVE_COUNT:-0} -ge 4 ]] && item_count=5
  _show_input_footer "filter" "$item_count"

  local selected
  selected=$(echo -e "$options" | gum choose \
    --header="ZFS mode:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && ZFS_RAID="$selected"
}

_edit_tailscale() {
  clear
  show_banner
  echo ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(echo -e "Disabled\nEnabled" | gum choose \
    --header="Tailscale:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  case "$selected" in
    Enabled)
      # Request auth key (required for Tailscale)
      clear
      show_banner
      echo ""
      gum style --foreground "$HEX_GRAY" "Enter Tailscale authentication key"
      echo ""
      _show_input_footer

      local auth_key
      auth_key=$(gum input \
        --placeholder "tskey-auth-..." \
        --prompt "Auth Key: " \
        --prompt.foreground "$HEX_CYAN" \
        --cursor.foreground "$HEX_ORANGE" \
        --width 60 \
        --no-show-help)

      # If auth key provided, enable Tailscale with stealth mode
      if [[ -n $auth_key ]]; then
        INSTALL_TAILSCALE="yes"
        TAILSCALE_AUTH_KEY="$auth_key"
        TAILSCALE_SSH="yes"
        TAILSCALE_WEBUI="yes"
        TAILSCALE_DISABLE_SSH="yes"
        STEALTH_MODE="yes"
        SSL_TYPE="self-signed"  # Tailscale uses its own certs
      else
        # Auth key required - disable Tailscale if not provided
        INSTALL_TAILSCALE="no"
        TAILSCALE_AUTH_KEY=""
        TAILSCALE_SSH=""
        TAILSCALE_WEBUI=""
        TAILSCALE_DISABLE_SSH=""
        STEALTH_MODE=""
        SSL_TYPE=""  # Let user choose
      fi
      ;;
    Disabled)
      INSTALL_TAILSCALE="no"
      TAILSCALE_AUTH_KEY=""
      TAILSCALE_SSH=""
      TAILSCALE_WEBUI=""
      TAILSCALE_DISABLE_SSH=""
      STEALTH_MODE=""
      SSL_TYPE=""  # Let user choose
      ;;
  esac
}

_edit_ssl() {
  clear
  show_banner
  echo ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(echo "$WIZ_SSL_TYPES" | gum choose \
    --header="SSL Certificate:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && SSL_TYPE="$selected"
}

_edit_shell() {
  clear
  show_banner
  echo ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(echo "$WIZ_SHELL_OPTIONS" | gum choose \
    --header="Shell:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && SHELL_TYPE="$selected"
}

_edit_power_profile() {
  clear
  show_banner
  echo ""

  # 1 header + 5 items for gum choose
  _show_input_footer "filter" 6

  local selected
  selected=$(echo "$WIZ_CPU_GOVERNORS" | gum choose \
    --header="Power profile:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && CPU_GOVERNOR="$selected"
}

_edit_features() {
  clear
  show_banner
  echo ""

  # 1 header + 2 items for multi-select checkbox
  _show_input_footer "checkbox" 3

  # Use gum choose with --no-limit for multi-select
  local selected
  selected=$(echo "$WIZ_OPTIONAL_FEATURES" | gum choose \
    --no-limit \
    --header="Features:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  # Parse selection
  INSTALL_VNSTAT="no"
  INSTALL_AUDITD="no"
  if echo "$selected" | grep -q "vnstat"; then
    INSTALL_VNSTAT="yes"
  fi
  if echo "$selected" | grep -q "auditd"; then
    INSTALL_AUDITD="yes"
  fi
}

_edit_ssh_key() {
  clear
  show_banner
  echo ""
  gum style --foreground "$HEX_GRAY" "Paste your SSH public key (ssh-rsa, ssh-ed25519, etc.)"
  echo ""
  _show_input_footer

  local new_key
  new_key=$(gum input \
    --placeholder "ssh-ed25519 AAAA... user@host" \
    --value "$SSH_PUBLIC_KEY" \
    --prompt "SSH Key: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 60 \
    --no-show-help)

  if [[ -n $new_key ]]; then
    if validate_ssh_public_key "$new_key"; then
      SSH_PUBLIC_KEY="$new_key"
    else
      echo ""
      echo ""
      gum style --foreground "$HEX_RED" "Invalid SSH key format"
      sleep 1
    fi
  fi
}

# =============================================================================
# Main wizard entry point
# =============================================================================

show_gum_config_editor() {
  # Initialize network detection silently (output suppressed)
  detect_network_interface >/dev/null 2>&1
  collect_network_info >/dev/null 2>&1

  # Hide cursor during wizard, restore on exit
  _wiz_hide_cursor
  trap '_wiz_show_cursor' EXIT

  # Run wizard
  _wizard_main
}
