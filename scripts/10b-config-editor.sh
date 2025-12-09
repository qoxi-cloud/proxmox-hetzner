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

# Track if initial render has been done
_WIZ_INITIAL_RENDER_DONE=""

# Menu item indices (for mapping selection to edit functions)
# These track which items are selectable fields vs section headers
_WIZ_FIELD_COUNT=0
_WIZ_FIELD_MAP=()

# Render the main menu with current selection highlighted (flicker-free)
# Parameters:
#   $1 - Current selection index (0-based, only counts selectable fields)
_wiz_render_menu() {
  local selection="$1"
  local output=""

  # First render: clear screen and show banner
  if [[ -z $_WIZ_INITIAL_RENDER_DONE ]]; then
    clear
    show_banner
    echo ""
    _WIZ_INITIAL_RENDER_DONE=1
    # Save cursor position after banner
    printf '\033[s'
  else
    # Subsequent renders: restore cursor position and clear menu area
    printf '\033[u\033[J'
  fi

  # Build display values
  local pass_display
  pass_display=$([[ $PASSWORD_GENERATED == "yes" ]] && echo "(auto-generated)" || echo "********")

  local ipv6_display
  case "$IPV6_MODE" in
    auto) ipv6_display="Auto" ;;
    manual) ipv6_display="Manual" ;;
    disabled) ipv6_display="Disabled" ;;
    *) ipv6_display="$IPV6_MODE" ;;
  esac

  local tailscale_display
  tailscale_display=$([[ $INSTALL_TAILSCALE == "yes" ]] && echo "Enabled" || echo "Disabled")

  local features_display=""
  [[ $INSTALL_VNSTAT == "yes" ]] && features_display+="vnstat"
  [[ $INSTALL_AUDITD == "yes" ]] && features_display+="${features_display:+, }auditd"
  [[ -z $features_display ]] && features_display="none"

  local ssh_display
  if [[ -n $SSH_PUBLIC_KEY ]]; then
    # Show first 20 chars of key type and fingerprint hint
    ssh_display="${SSH_PUBLIC_KEY:0:20}..."
  else
    ssh_display="(not set)"
  fi

  # Reset field map
  _WIZ_FIELD_MAP=()
  local field_idx=0

  # Helper to add section header
  _add_section() {
    output+="\n${CLR_CYAN}--- $1 ---${CLR_RESET}\n"
  }

  # Helper to add field
  _add_field() {
    local label="$1"
    local value="$2"
    local field_name="$3"
    _WIZ_FIELD_MAP+=("$field_name")
    if [[ $field_idx -eq $selection ]]; then
      output+="  ${CLR_ORANGE}›${CLR_RESET} ${CLR_GRAY}${label}${CLR_RESET}${value}\n"
    else
      output+="    ${CLR_GRAY}${label}${CLR_RESET}${value}\n"
    fi
    ((field_idx++))
  }

  # --- Basic Settings ---
  _add_section "Basic Settings"
  _add_field "Hostname         " "${PVE_HOSTNAME}.${DOMAIN_SUFFIX}" "hostname"
  _add_field "Email            " "${EMAIL}" "email"
  _add_field "Password         " "${pass_display}" "password"
  _add_field "Timezone         " "${TIMEZONE}" "timezone"

  # --- Proxmox ---
  _add_section "Proxmox"
  _add_field "Repository       " "${PVE_REPO_TYPE}" "repository"

  # --- Network ---
  _add_section "Network"
  _add_field "Interface        " "${INTERFACE_NAME:-auto}" "interface"
  _add_field "Bridge mode      " "${BRIDGE_MODE}" "bridge_mode"
  _add_field "Private subnet   " "${PRIVATE_SUBNET}" "private_subnet"
  _add_field "IPv6             " "${ipv6_display}" "ipv6"

  # --- Storage ---
  _add_section "Storage"
  _add_field "ZFS mode         " "${ZFS_RAID}" "zfs_mode"

  # --- VPN ---
  _add_section "VPN"
  _add_field "Tailscale        " "${tailscale_display}" "tailscale"

  # --- SSL ---
  _add_section "SSL"
  _add_field "Certificate      " "${SSL_TYPE}" "ssl"

  # --- Optional ---
  _add_section "Optional"
  _add_field "Shell            " "${DEFAULT_SHELL}" "shell"
  _add_field "Power profile    " "${CPU_GOVERNOR}" "power_profile"
  _add_field "Features         " "${features_display}" "features"

  # --- SSH ---
  _add_section "SSH"
  _add_field "SSH Key          " "${ssh_display}" "ssh_key"

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

  # Initial render to populate _WIZ_FIELD_COUNT
  _wiz_render_menu "$selection"

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
        # Hide cursor again and reset render state
        _wiz_hide_cursor
        _WIZ_INITIAL_RENDER_DONE=""
        ;;
      quit | esc)
        _wiz_show_cursor
        if gum confirm "Quit installation?" --default=false \
          --prompt.foreground "$HEX_ORANGE" \
          --selected.background "$HEX_ORANGE"; then
          exit 0
        fi
        # Hide cursor again and reset render state
        _wiz_hide_cursor
        _WIZ_INITIAL_RENDER_DONE=""
        ;;
    esac
  done
}

# =============================================================================
# Edit functions - each clears screen, shows banner, then input field
# =============================================================================

_edit_hostname() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
  echo ""

  local new_hostname
  new_hostname=$(gum input \
    --placeholder "e.g., pve, proxmox, node1" \
    --value "$PVE_HOSTNAME" \
    --prompt "Hostname: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40)

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

  echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
  echo ""

  local new_domain
  new_domain=$(gum input \
    --placeholder "e.g., local, example.com" \
    --value "$DOMAIN_SUFFIX" \
    --prompt "Domain: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40)

  if [[ -n $new_domain ]]; then
    DOMAIN_SUFFIX="$new_domain"
  fi

  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
}

_edit_email() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
  echo ""

  local new_email
  new_email=$(gum input \
    --placeholder "admin@example.com" \
    --value "$EMAIL" \
    --prompt "Email: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 50)

  if [[ -n $new_email ]]; then
    if validate_email "$new_email"; then
      EMAIL="$new_email"
    else
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

  echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
  echo ""

  local new_password
  new_password=$(gum input \
    --password \
    --placeholder "Enter password or leave empty" \
    --prompt "Password: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40)

  if [[ -z $new_password ]]; then
    NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
    PASSWORD_GENERATED="yes"
    echo ""
    gum style --foreground "$HEX_GREEN" "✓ Password auto-generated"
    sleep 1
  else
    local password_error
    password_error=$(get_password_error "$new_password")
    if [[ -n $password_error ]]; then
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

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

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
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  if [[ $selected == "Custom..." ]]; then
    clear
    show_banner
    echo ""

    echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
    echo ""

    local custom_tz
    custom_tz=$(gum input \
      --placeholder "e.g., Europe/Paris, Asia/Singapore" \
      --value "$TIMEZONE" \
      --prompt "Timezone: " \
      --prompt.foreground "$HEX_CYAN" \
      --cursor.foreground "$HEX_ORANGE" \
      --width 40)

    if [[ -n $custom_tz ]]; then
      if validate_timezone "$custom_tz"; then
        TIMEZONE="$custom_tz"
      else
        echo ""
        gum style --foreground "$HEX_RED" "Invalid timezone"
        sleep 1
      fi
    fi
  elif [[ -n $selected ]]; then
    TIMEZONE="$selected"
  fi
}

_edit_repository() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

  local options="no-subscription
enterprise
test"

  local selected
  selected=$(echo "$options" | gum choose \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  [[ -n $selected ]] && PVE_REPO_TYPE="$selected"
}

_edit_interface() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}Interface is auto-detected. Current: ${INTERFACE_NAME:-auto}${CLR_RESET}"
  echo ""
  sleep 1
}

_edit_bridge_mode() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

  local options="external
internal
both"

  local selected
  selected=$(echo "$options" | gum choose \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  [[ -n $selected ]] && BRIDGE_MODE="$selected"
}

_edit_private_subnet() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
  echo ""

  local new_subnet
  new_subnet=$(gum input \
    --placeholder "e.g., 10.10.10.0/24" \
    --value "$PRIVATE_SUBNET" \
    --prompt "Private subnet: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 40)

  if [[ -n $new_subnet ]]; then
    if validate_subnet "$new_subnet"; then
      PRIVATE_SUBNET="$new_subnet"
    else
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

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

  local options="auto
manual
disabled"

  local selected
  selected=$(echo "$options" | gum choose \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  [[ -n $selected ]] && IPV6_MODE="$selected"
}

_edit_zfs_mode() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

  local options="single
raid1"

  # Add more options if multiple drives detected
  if [[ ${DRIVE_COUNT:-0} -ge 3 ]]; then
    options+="\nraid5"
  fi
  if [[ ${DRIVE_COUNT:-0} -ge 4 ]]; then
    options+="\nraid10"
  fi

  local selected
  selected=$(echo -e "$options" | gum choose \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  [[ -n $selected ]] && ZFS_RAID="$selected"
}

_edit_tailscale() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

  local options="Disabled
Enabled"

  local selected
  selected=$(echo "$options" | gum choose \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  case "$selected" in
    Enabled) INSTALL_TAILSCALE="yes" ;;
    Disabled) INSTALL_TAILSCALE="no" ;;
  esac
}

_edit_ssl() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

  local options="self-signed
letsencrypt"

  local selected
  selected=$(echo "$options" | gum choose \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  [[ -n $selected ]] && SSL_TYPE="$selected"
}

_edit_shell() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

  local options="zsh
bash"

  local selected
  selected=$(echo "$options" | gum choose \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  [[ -n $selected ]] && DEFAULT_SHELL="$selected"
}

_edit_power_profile() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select${CLR_RESET}"
  echo ""

  local options="performance
ondemand
powersave
schedutil
conservative"

  local selected
  selected=$(echo "$options" | gum choose \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

  [[ -n $selected ]] && CPU_GOVERNOR="$selected"
}

_edit_features() {
  clear
  show_banner
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}Space${CLR_GRAY}] toggle  [${CLR_ORANGE}Enter${CLR_GRAY}] confirm${CLR_RESET}"
  echo ""

  # Build options with current state
  local options=""
  [[ $INSTALL_VNSTAT == "yes" ]] && options+="vnstat (network stats)\n" || options+="vnstat (network stats)\n"
  [[ $INSTALL_AUDITD == "yes" ]] && options+="auditd (audit logging)\n" || options+="auditd (audit logging)\n"

  # Use gum choose with --no-limit for multi-select
  local selected
  selected=$(echo -e "vnstat (network stats)\nauditd (audit logging)" | gum choose \
    --no-limit \
    --header="" \
    --cursor "› " \
    --cursor.foreground "$HEX_ORANGE" \
    --selected.foreground "$HEX_WHITE" \
    --item.foreground "$HEX_WHITE")

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

  echo -e "${CLR_GRAY}Paste your SSH public key (ssh-rsa, ssh-ed25519, etc.)${CLR_RESET}"
  echo ""

  echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
  echo ""

  local new_key
  new_key=$(gum input \
    --placeholder "ssh-ed25519 AAAA... user@host" \
    --value "$SSH_PUBLIC_KEY" \
    --prompt "SSH Key: " \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --width 60)

  if [[ -n $new_key ]]; then
    if validate_ssh_public_key "$new_key"; then
      SSH_PUBLIC_KEY="$new_key"
    else
      echo ""
      gum style --foreground "$HEX_RED" "Invalid SSH key format"
      sleep 1
    fi
  fi
}

# =============================================================================
# Initialize defaults
# =============================================================================

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

# =============================================================================
# Main wizard entry point
# =============================================================================

show_gum_config_editor() {
  # Initialize network detection silently (output suppressed)
  detect_network_interface >/dev/null 2>&1
  collect_network_info >/dev/null 2>&1

  # Initialize default configuration values
  _init_default_config

  # Hide cursor during wizard, restore on exit
  _wiz_hide_cursor
  trap '_wiz_show_cursor' EXIT

  # Run wizard
  _wizard_main
}
