# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Basic Settings Editors
# hostname, email, password, timezone, keyboard, country
# =============================================================================

# Edits hostname and domain settings via input dialogs.
# Validates hostname format and updates PVE_HOSTNAME, DOMAIN_SUFFIX, FQDN.
_edit_hostname() {
  # Hostname input loop
  while true; do
    _wiz_start_edit
    _show_input_footer

    local new_hostname
    new_hostname=$(
      _wiz_input \
        --placeholder "e.g., pve, proxmox, node1" \
        --value "$PVE_HOSTNAME" \
        --prompt "Hostname: "
    )

    # If empty (cancelled), return to menu
    if [[ -z $new_hostname ]]; then
      return
    fi

    # Validate hostname
    if validate_hostname "$new_hostname"; then
      PVE_HOSTNAME="$new_hostname"
      break
    else
      show_validation_error "Invalid hostname format"
    fi
  done

  # Domain input loop
  while true; do
    _wiz_start_edit
    _show_input_footer

    local new_domain
    new_domain=$(
      _wiz_input \
        --placeholder "e.g., local, example.com" \
        --value "$DOMAIN_SUFFIX" \
        --prompt "Domain: "
    )

    # If empty (cancelled), return to menu
    if [[ -z $new_domain ]]; then
      return
    fi

    # Accept any non-empty domain (validation happens later if Let's Encrypt selected)
    DOMAIN_SUFFIX="$new_domain"
    break
  done

  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
}

# Edits admin email address via input dialog.
# Validates email format and updates EMAIL global.
_edit_email() {
  while true; do
    _wiz_start_edit
    _show_input_footer

    local new_email
    new_email=$(
      _wiz_input \
        --placeholder "admin@example.com" \
        --value "$EMAIL" \
        --prompt "Email: "
    )

    # If empty (cancelled), return to menu
    if [[ -z $new_email ]]; then
      return
    fi

    # Validate email
    if validate_email "$new_email"; then
      EMAIL="$new_email"
      break
    else
      show_validation_error "Invalid email format"
    fi
  done
}

# Edits root password via manual entry or generation.
# Shows generated password for user to save.
# Updates NEW_ROOT_PASSWORD and PASSWORD_GENERATED globals.
_edit_password() {
  _wiz_password_editor \
    "NEW_ROOT_PASSWORD" \
    "Root Password:" \
    "it will be required for login" \
    "Generated root password:" \
    "yes"
}

# Edits timezone via searchable filter list.
# Auto-selects country based on timezone if mapping exists.
# Updates TIMEZONE and optionally COUNTRY/LOCALE globals.
_edit_timezone() {
  _wiz_start_edit

  # Footer for filter: height=5 items + 1 input line = 6 lines for component
  _show_input_footer "filter" 6

  local selected
  if ! selected=$(echo "$WIZ_TIMEZONES" | _wiz_filter --prompt "Timezone: "); then
    return
  fi

  TIMEZONE="$selected"
  # Auto-select country based on timezone (if mapping exists)
  local country_code="${TZ_TO_COUNTRY[$selected]:-}"
  if [[ -n $country_code ]]; then
    COUNTRY="$country_code"
    _update_locale_from_country
  fi
}

# Edits keyboard layout via searchable filter list.
# Updates KEYBOARD global with selected layout.
_edit_keyboard() {
  _wiz_start_edit

  # Footer for filter: height=5 items + 1 input line = 6 lines for component
  _show_input_footer "filter" 6

  local selected
  if ! selected=$(echo "$WIZ_KEYBOARD_LAYOUTS" | _wiz_filter --prompt "Keyboard: "); then
    return
  fi

  KEYBOARD="$selected"
}

# Edits country code via searchable filter list.
# Updates COUNTRY and LOCALE globals.
_edit_country() {
  _wiz_start_edit

  # Footer for filter: height=5 items + 1 input line = 6 lines for component
  _show_input_footer "filter" 6

  local selected
  if ! selected=$(echo "$WIZ_COUNTRIES" | _wiz_filter --prompt "Country: "); then
    return
  fi

  COUNTRY="$selected"
  _update_locale_from_country
}
