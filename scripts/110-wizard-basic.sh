# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Basic Settings Editors
# hostname, email, password, timezone, keyboard, country
# =============================================================================

# Maps country code to locale (language_COUNTRY.UTF-8)
# Uses most common language for each country
_country_to_locale() {
  local country="${1:-us}"
  country="${country,,}" # lowercase

  # Common country to language mappings
  case "$country" in
    us | gb | au | nz | ca | ie) echo "en_${country^^}.UTF-8" ;;
    ru) echo "ru_RU.UTF-8" ;;
    ua) echo "uk_UA.UTF-8" ;;
    de | at) echo "de_${country^^}.UTF-8" ;;
    fr | be) echo "fr_${country^^}.UTF-8" ;;
    es | mx | ar | co | cl | pe) echo "es_${country^^}.UTF-8" ;;
    pt | br) echo "pt_${country^^}.UTF-8" ;;
    it) echo "it_IT.UTF-8" ;;
    nl) echo "nl_NL.UTF-8" ;;
    pl) echo "pl_PL.UTF-8" ;;
    cz) echo "cs_CZ.UTF-8" ;;
    sk) echo "sk_SK.UTF-8" ;;
    hu) echo "hu_HU.UTF-8" ;;
    ro) echo "ro_RO.UTF-8" ;;
    bg) echo "bg_BG.UTF-8" ;;
    hr) echo "hr_HR.UTF-8" ;;
    rs) echo "sr_RS.UTF-8" ;;
    si) echo "sl_SI.UTF-8" ;;
    se) echo "sv_SE.UTF-8" ;;
    no) echo "nb_NO.UTF-8" ;;
    dk) echo "da_DK.UTF-8" ;;
    fi) echo "fi_FI.UTF-8" ;;
    ee) echo "et_EE.UTF-8" ;;
    lv) echo "lv_LV.UTF-8" ;;
    lt) echo "lt_LT.UTF-8" ;;
    gr) echo "el_GR.UTF-8" ;;
    tr) echo "tr_TR.UTF-8" ;;
    il) echo "he_IL.UTF-8" ;;
    jp) echo "ja_JP.UTF-8" ;;
    cn) echo "zh_CN.UTF-8" ;;
    tw) echo "zh_TW.UTF-8" ;;
    kr) echo "ko_KR.UTF-8" ;;
    in) echo "hi_IN.UTF-8" ;;
    th) echo "th_TH.UTF-8" ;;
    vn) echo "vi_VN.UTF-8" ;;
    id) echo "id_ID.UTF-8" ;;
    my) echo "ms_MY.UTF-8" ;;
    ph) echo "en_PH.UTF-8" ;;
    sg) echo "en_SG.UTF-8" ;;
    za) echo "en_ZA.UTF-8" ;;
    eg) echo "ar_EG.UTF-8" ;;
    sa) echo "ar_SA.UTF-8" ;;
    ae) echo "ar_AE.UTF-8" ;;
    ir) echo "fa_IR.UTF-8" ;;
    *) echo "en_US.UTF-8" ;; # Default fallback
  esac
}

# Updates LOCALE based on current COUNTRY
_update_locale_from_country() {
  LOCALE=$(_country_to_locale "$COUNTRY")
  log "Set LOCALE=$LOCALE from COUNTRY=$COUNTRY"
}

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
        _wiz_hide_cursor
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
            --prompt "Password: "
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
    # Auto-select country based on timezone (if mapping exists)
    local country_code="${TZ_TO_COUNTRY[$selected]:-}"
    if [[ -n $country_code ]]; then
      COUNTRY="$country_code"
      _update_locale_from_country
    fi
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
    _update_locale_from_country
  fi
}
