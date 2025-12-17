# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Basic Settings Editors
# hostname, email, password, timezone, keyboard, country
# =============================================================================

_edit_hostname() {
  _wiz_start_edit
  _show_input_footer

  local new_hostname
  new_hostname=$(
    _wiz_input \
      --placeholder "e.g., pve, proxmox, node1" \
      --value "$PVE_HOSTNAME" \
      --prompt "Hostname: " \  --width 40
  )

  if [[ -n $new_hostname ]]; then
    if validate_hostname "$new_hostname"; then
      PVE_HOSTNAME="$new_hostname"
    else
      show_validation_error "Invalid hostname format"
      return
    fi
  fi

  # Edit domain
  _wiz_start_edit
  _show_input_footer

  local new_domain
  new_domain=$(
    _wiz_input \
      --placeholder "e.g., local, example.com" \
      --value "$DOMAIN_SUFFIX" \
      --prompt "Domain: " \  --width 40
  )

  if [[ -n $new_domain ]]; then
    DOMAIN_SUFFIX="$new_domain"
  fi

  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
}

_edit_email() {
  _wiz_start_edit
  _show_input_footer

  local new_email
  new_email=$(
    _wiz_input \
      --placeholder "admin@example.com" \
      --value "$EMAIL" \
      --prompt "Email: " \  --width 50
  )

  if [[ -n $new_email ]]; then
    if validate_email "$new_email"; then
      EMAIL="$new_email"
    else
      show_validation_error "Invalid email format"
    fi
  fi
}

_edit_password() {
  while true; do
    _wiz_start_edit

    # 1 header + 2 options (Manual/Generate)
    _show_input_footer "filter" 3

    local choice
    choice=$(
      echo -e "Manual entry\nGenerate password" | _wiz_choose \
        --header="Password:"
    )

    # If user cancelled (Esc)
    if [[ -z $choice ]]; then
      return
    fi

    case "$choice" in
      "Generate password")
        NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
        PASSWORD_GENERATED="yes"

        _wiz_start_edit
        _wiz_warn "Please save this password - it will be required for login"
        _wiz_blank_line
        echo -e "${CLR_CYAN}Generated password:${CLR_RESET} ${CLR_ORANGE}${NEW_ROOT_PASSWORD}${CLR_RESET}"
        _wiz_blank_line
        echo -e "${CLR_GRAY}Press any key to continue...${CLR_RESET}"
        read -n 1 -s -r
        break
        ;;
      "Manual entry")
        _wiz_start_edit
        _show_input_footer

        local new_password
        new_password=$(
          _wiz_input \
            --password \
            --placeholder "Enter password" \
            --prompt "Password: " \  --width 40
        )

        # If empty or cancelled, return to menu
        if [[ -z $new_password ]]; then
          continue
        fi

        # Validate password
        local password_error
        password_error=$(get_password_error "$new_password")
        if [[ -n $password_error ]]; then
          show_validation_error "$password_error"
          continue
        fi

        # Password is valid
        NEW_ROOT_PASSWORD="$new_password"
        PASSWORD_GENERATED="no"
        break
        ;;
    esac
  done
}

_edit_timezone() {
  _wiz_start_edit

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

_edit_keyboard() {
  _wiz_start_edit

  # Footer for filter: height=5 items + 1 input line = 6 lines for component
  _show_input_footer "filter" 6

  local selected
  selected=$(echo "$WIZ_KEYBOARD_LAYOUTS" | gum filter \
    --placeholder "Type to search..." \
    --indicator "›" \
    --height 5 \
    --no-show-help \
    --prompt "Keyboard: " \
    --prompt.foreground "$HEX_CYAN" \
    --indicator.foreground "$HEX_ORANGE" \
    --match.foreground "$HEX_ORANGE")

  if [[ -n $selected ]]; then
    KEYBOARD="$selected"
  fi
}

_edit_country() {
  _wiz_start_edit

  # Footer for filter: height=5 items + 1 input line = 6 lines for component
  _show_input_footer "filter" 6

  local selected
  selected=$(echo "$WIZ_COUNTRIES" | gum filter \
    --placeholder "Type to search..." \
    --indicator "›" \
    --height 5 \
    --no-show-help \
    --prompt "Country: " \
    --prompt.foreground "$HEX_CYAN" \
    --indicator.foreground "$HEX_ORANGE" \
    --match.foreground "$HEX_ORANGE")

  if [[ -n $selected ]]; then
    COUNTRY="$selected"
  fi
}
