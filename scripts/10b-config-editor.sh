# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Step-by-step configuration using gum
# =============================================================================

# Current wizard step
WIZARD_CURRENT_STEP=1
WIZARD_TOTAL_STEPS=1 # Will increase as we add more steps

# =============================================================================
# Helper functions
# =============================================================================

# Display footer for main step screen
_wiz_footer_main() {
  echo ""
  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select  [${CLR_ORANGE}Q${CLR_GRAY}] quit${CLR_RESET}"
}

# Display footer for edit screen
_wiz_footer_edit() {
  echo ""
  echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
}

# =============================================================================
# Step 1: Basic Settings
# =============================================================================

_wizard_step_basic() {
  while true; do
    clear
    show_banner
    echo ""

    # Step title in cyan/blue
    gum style --foreground "$HEX_CYAN" --bold "Basic Settings"
    echo ""

    # Build menu items with current values
    local pass_display
    pass_display=$([[ $PASSWORD_GENERATED == "yes" ]] && echo "(auto-generated)" || echo "********")

    local hostname_line="Hostname         ${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
    local email_line="Email            ${EMAIL}"
    local password_line="Password         ${pass_display}"
    local timezone_line="Timezone         ${TIMEZONE}"

    # Navigation buttons (gray if disabled)
    local back_btn
    local next_btn="Continue →"

    if [[ $WIZARD_CURRENT_STEP -gt 1 ]]; then
      back_btn="← Back"
    else
      back_btn="${CLR_GRAY}← Back${CLR_RESET}"
    fi

    # Show selectable menu with field values and navigation
    local selected
    selected=$(gum choose \
      "$hostname_line" \
      "$email_line" \
      "$password_line" \
      "$timezone_line" \
      "" \
      "$back_btn           $next_btn" \
      --header="" \
      --cursor "› " \
      --cursor.foreground "$HEX_ORANGE" \
      --selected.foreground "$HEX_WHITE" \
      --item.foreground "$HEX_WHITE")

    # Footer after menu
    _wiz_footer_main

    # Handle empty selection (Esc/Ctrl+C)
    if [[ -z $selected ]]; then
      if gum confirm "Quit installation?" --default=false \
        --prompt.foreground "$HEX_ORANGE" \
        --selected.background "$HEX_ORANGE"; then
        exit 0
      fi
      continue
    fi

    # Handle navigation buttons
    if [[ $selected == *"Continue →"* ]]; then
      # Validate before continuing
      if [[ -z $PVE_HOSTNAME ]]; then
        gum style --foreground "$HEX_RED" "Hostname is required!"
        sleep 1
        continue
      fi
      if [[ -z $EMAIL ]] || ! validate_email "$EMAIL"; then
        gum style --foreground "$HEX_RED" "Valid email is required!"
        sleep 1
        continue
      fi
      break
    fi

    if [[ $selected == *"← Back"* && $WIZARD_CURRENT_STEP -gt 1 ]]; then
      # Go back to previous step
      return 1
    fi

    # Skip empty line selection
    if [[ -z $selected || $selected =~ ^[[:space:]]*$ ]]; then
      continue
    fi

    case "$selected" in
      "$hostname_line")
        _edit_hostname
        ;;
      "$email_line")
        _edit_email
        ;;
      "$password_line")
        _edit_password
        ;;
      "$timezone_line")
        _edit_timezone
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

  _wiz_footer_edit

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

  _wiz_footer_edit

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

  _wiz_footer_edit

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

  _wiz_footer_edit

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

    _wiz_footer_edit

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

  # Run wizard steps
  _wizard_step_basic

  # TODO: Add more steps here
  # _wizard_step_network
  # _wizard_step_storage
  # etc.
}
