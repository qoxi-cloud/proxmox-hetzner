# shellcheck shell=bash
# Configuration Wizard - Basic Settings Editors
# hostname, email, password, timezone, keyboard, country

# Edits hostname and domain settings via input dialogs.
# Validates hostname format and updates PVE_HOSTNAME, DOMAIN_SUFFIX, FQDN.
_edit_hostname() {
  _wiz_input_validated "PVE_HOSTNAME" "validate_hostname" "Invalid hostname format" \
    --placeholder "e.g., pve, proxmox, node1" \
    --value "$PVE_HOSTNAME" \
    --prompt "Hostname: " || return

  # Domain input (no validation - accepts any non-empty)
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
  [[ -z $new_domain ]] && return

  DOMAIN_SUFFIX="$new_domain"
  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
}

# Edits admin email address via input dialog.
# Validates email format and updates EMAIL global.
_edit_email() {
  _wiz_input_validated "EMAIL" "validate_email" "Invalid email format" \
    --placeholder "admin@example.com" \
    --value "$EMAIL" \
    --prompt "Email: "
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
  _wiz_filter_select "TIMEZONE" "Timezone: " "$WIZ_TIMEZONES" || return

  # Auto-select country based on timezone (if mapping exists)
  local country_code="${TZ_TO_COUNTRY[$TIMEZONE]:-}"
  if [[ -n $country_code ]]; then
    COUNTRY="$country_code"
    _update_locale_from_country
  fi
}

# Edits keyboard layout via searchable filter list.
# Updates KEYBOARD global with selected layout.
_edit_keyboard() {
  _wiz_filter_select "KEYBOARD" "Keyboard: " "$WIZ_KEYBOARD_LAYOUTS"
}

# Edits country code via searchable filter list.
# Updates COUNTRY and LOCALE globals.
_edit_country() {
  _wiz_filter_select "COUNTRY" "Country: " "$WIZ_COUNTRIES" || return
  _update_locale_from_country
}
