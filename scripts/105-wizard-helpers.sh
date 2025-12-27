# shellcheck shell=bash
# Configuration Wizard - Editor Helpers
# Reusable helpers for common wizard editor patterns

# Password editor helper

# Password editor (Generate/Manual). $1=var, $2=header, $3=success_msg, $4=label, $5=set_generated
_wiz_password_editor() {
  local var_name="$1"
  local header="$2"
  local success_msg="$3"
  local display_label="$4"
  local set_generated="${5:-no}"

  while true; do
    _wiz_start_edit

    # 1 header + 2 options (Manual/Generate)
    _show_input_footer "filter" 3

    local choice
    if ! choice=$(printf '%s\n' "$WIZ_PASSWORD_OPTIONS" | _wiz_choose --header="$header"); then
      return 1
    fi

    case "$choice" in
      "Generate password")
        local generated_pass
        generated_pass=$(generate_password "$DEFAULT_PASSWORD_LENGTH")

        # Set the target variable using declare -g
        declare -g "$var_name=$generated_pass"

        # Optionally set PASSWORD_GENERATED flag
        [[ $set_generated == "yes" ]] && PASSWORD_GENERATED="yes"

        _wiz_start_edit
        _wiz_hide_cursor
        _wiz_warn "Please save this password - $success_msg"
        _wiz_blank_line
        printf '%s\n' "${WIZ_NOTIFY_INDENT}${CLR_CYAN}${display_label}${CLR_RESET} ${CLR_ORANGE}${generated_pass}${CLR_RESET}"
        _wiz_blank_line
        printf '%s\n' "${WIZ_NOTIFY_INDENT}${CLR_GRAY}Press any key to continue...${CLR_RESET}"
        read -n 1 -s -r
        return 0
        ;;
      "Manual entry")
        _wiz_start_edit
        _show_input_footer

        local new_password
        new_password=$(
          _wiz_input \
            --password \
            --placeholder "Enter password" \
            --prompt "${header} "
        )

        # If empty or cancelled, continue loop
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

        # Password is valid - set the target variable
        declare -g "$var_name=$new_password"

        # Clear PASSWORD_GENERATED if set_generated mode
        [[ $set_generated == "yes" ]] && PASSWORD_GENERATED="no"

        return 0
        ;;
    esac
  done
}

# Choose with mapping helper

# Chooser with display→internal mapping. $1=var, $2=header, $@="Display:internal" pairs
_wiz_choose_mapped() {
  local var_name="$1"
  local header="$2"
  shift 2

  # Build mapping and options list from pairs
  local -A mapping=()
  local options=""
  for pair in "$@"; do
    local display="${pair%%:*}"
    local internal="${pair#*:}"
    mapping["$display"]="$internal"
    [[ -n $options ]] && options+=$'\n'
    options+="$display"
  done

  local selected
  if ! selected=$(printf '%s\n' "$options" | _wiz_choose --header="$header"); then
    return 1
  fi

  # Look up internal value and set variable
  local internal_value="${mapping[$selected]:-}"
  if [[ -n $internal_value ]]; then
    declare -g "$var_name=$internal_value"
  fi

  return 0
}

# Toggle (Enabled/Disabled) helper

# Toggle Enabled/Disabled. $1=var, $2=header, $3=default. Returns: 0=disabled, 1=cancel, 2=enabled
_wiz_toggle() {
  local var_name="$1"
  local header="$2"
  local default_on_cancel="${3:-no}"

  local selected
  if ! selected=$(printf '%s\n' "Enabled" "Disabled" | _wiz_choose --header="$header"); then
    declare -g "$var_name=$default_on_cancel"
    return 1
  fi

  if [[ $selected == "Enabled" ]]; then
    declare -g "$var_name=yes"
    return 2
  else
    declare -g "$var_name=no"
    return 0
  fi
}

# Feature checkbox editor helper

# Feature multi-select. $1=header, $2=footer_size, $3=options_var, $@="feature:VAR" pairs
_wiz_feature_checkbox() {
  local header="$1"
  local footer_size="$2"
  local options_var="$3"
  shift 3

  _show_input_footer "checkbox" "$footer_size"

  # Build gum args with pre-selected items
  local gum_args=(--header="$header")
  local feature_map=()

  for pair in "$@"; do
    local feature="${pair%%:*}"
    local var_name="${pair#*:}"
    feature_map+=("$feature:$var_name")

    # Check if currently selected
    local current_value
    current_value="${!var_name}"
    [[ $current_value == "yes" ]] && gum_args+=(--selected "$feature")
  done

  # Show multi-select chooser
  local selected
  if ! selected=$(printf '%s\n' "${!options_var}" | _wiz_choose_multi "${gum_args[@]}"); then
    return 1
  fi

  # Update all feature variables based on selection
  for pair in "${feature_map[@]}"; do
    local feature="${pair%%:*}"
    local var_name="${pair#*:}"

    if [[ $selected == *"$feature"* ]]; then
      declare -g "$var_name=yes"
    else
      declare -g "$var_name=no"
    fi
  done

  return 0
}
