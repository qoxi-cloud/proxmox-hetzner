# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Step-by-step configuration with manual UI rendering
# =============================================================================
# Uses manual rendering + key capture instead of gum choose for main menu.
# This allows footer at bottom and arrow key navigation for Back/Continue.

# Current wizard step
WIZARD_CURRENT_STEP=1
WIZARD_TOTAL_STEPS=1 # Will increase as we add more steps

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

# Render the main menu with current selection highlighted
# Parameters:
#   $1 - Current selection index (0-based)
#   $2 - Nav button focus: "fields" or "back" or "continue"
_wiz_render_menu() {
  local selection="$1"
  local nav_focus="$2"

  clear
  show_banner
  echo ""

  # Step title
  gum style --foreground "$HEX_CYAN" --bold "Basic Settings"
  echo ""

  # Build field values
  local pass_display
  pass_display=$([[ $PASSWORD_GENERATED == "yes" ]] && echo "(auto-generated)" || echo "********")

  local fields=(
    "Hostname         ${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
    "Email            ${EMAIL}"
    "Password         ${pass_display}"
    "Timezone         ${TIMEZONE}"
  )

  # Render fields
  local i
  for i in "${!fields[@]}"; do
    if [[ $nav_focus == "fields" && $i -eq $selection ]]; then
      echo -e "  ${CLR_ORANGE}›${CLR_RESET} ${fields[$i]}"
    else
      echo -e "    ${fields[$i]}"
    fi
  done

  echo ""

  # Navigation buttons
  local back_style="${CLR_GRAY}"
  local continue_style="${CLR_WHITE}"

  if [[ $WIZARD_CURRENT_STEP -gt 1 ]]; then
    if [[ $nav_focus == "back" ]]; then
      back_style="${CLR_ORANGE}"
    else
      back_style="${CLR_WHITE}"
    fi
  fi

  if [[ $nav_focus == "continue" ]]; then
    continue_style="${CLR_ORANGE}"
  fi

  echo -e "  ${back_style}← Back${CLR_RESET}           ${continue_style}Continue →${CLR_RESET}"

  echo ""
  # Footer
  echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}←→${CLR_GRAY}] back/continue  [${CLR_ORANGE}Enter${CLR_GRAY}] select  [${CLR_ORANGE}Q${CLR_GRAY}] quit${CLR_RESET}"
}

# =============================================================================
# Step 1: Basic Settings
# =============================================================================

_wizard_step_basic() {
  local selection=0
  local nav_focus="fields" # "fields", "back", or "continue"
  local max_fields=3       # 0-3 for 4 fields

  while true; do
    _wiz_render_menu "$selection" "$nav_focus"
    _wiz_read_key

    case "$WIZ_KEY" in
      up)
        if [[ $nav_focus == "fields" ]]; then
          if [[ $selection -gt 0 ]]; then
            ((selection--))
          fi
        elif [[ $nav_focus == "back" || $nav_focus == "continue" ]]; then
          # Move from nav buttons to last field
          nav_focus="fields"
          selection=$max_fields
        fi
        ;;
      down)
        if [[ $nav_focus == "fields" ]]; then
          if [[ $selection -lt $max_fields ]]; then
            ((selection++))
          else
            # Move to nav buttons
            nav_focus="continue"
          fi
        fi
        ;;
      left)
        if [[ $nav_focus == "continue" ]]; then
          if [[ $WIZARD_CURRENT_STEP -gt 1 ]]; then
            nav_focus="back"
          fi
        elif [[ $nav_focus == "fields" ]]; then
          # Move to back button if allowed
          if [[ $WIZARD_CURRENT_STEP -gt 1 ]]; then
            nav_focus="back"
          fi
        fi
        ;;
      right)
        if [[ $nav_focus == "back" ]]; then
          nav_focus="continue"
        elif [[ $nav_focus == "fields" ]]; then
          nav_focus="continue"
        fi
        ;;
      enter)
        if [[ $nav_focus == "continue" ]]; then
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
          return 0 # Success, go to next step
        elif [[ $nav_focus == "back" && $WIZARD_CURRENT_STEP -gt 1 ]]; then
          return 1 # Go back
        elif [[ $nav_focus == "fields" ]]; then
          # Edit selected field
          case $selection in
            0) _edit_hostname ;;
            1) _edit_email ;;
            2) _edit_password ;;
            3) _edit_timezone ;;
          esac
        fi
        ;;
      quit | esc)
        if gum confirm "Quit installation?" --default=false \
          --prompt.foreground "$HEX_ORANGE" \
          --selected.background "$HEX_ORANGE"; then
          exit 0
        fi
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
