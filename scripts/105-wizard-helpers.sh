# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Editor Helpers
# =============================================================================
# Reusable helpers for common wizard editor patterns

# =============================================================================
# Password editor helper
# =============================================================================

# Universal password editor with Generate/Manual options.
# Handles validation, generation, and display of saved password warning.
# Parameters:
#   $1 - Variable name to set (e.g., "NEW_ROOT_PASSWORD", "ADMIN_PASSWORD")
#   $2 - Header text for choose menu (e.g., "Password:", "Admin Password:")
#   $3 - Success message after generation (e.g., "it will be required for login")
#   $4 - Label for display (e.g., "Generated password:", "Generated admin password:")
#   $5 - Optional: also set PASSWORD_GENERATED="yes" if "yes"
# Returns: 0 on success, 1 on cancel
# Side effects: Sets the named global variable
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

# =============================================================================
# Choose with mapping helper
# =============================================================================

# Single-select chooser that maps display values to internal values.
# Handles the common pattern of choose + case mapping.
# Parameters:
#   $1 - Variable name to set (e.g., "BRIDGE_MODE")
#   $2 - Header text (e.g., "Bridge mode:")
#   $3 - Options variable name (e.g., "WIZ_BRIDGE_MODES")
#   $@ - Pairs of "Display text:internal_value" (e.g., "External bridge:external")
# Returns: 0 on selection, 1 on cancel
# Side effects: Sets the named global variable
# Example:
#   _wiz_choose_mapped "BRIDGE_MODE" "Bridge mode:" "WIZ_BRIDGE_MODES" \
#     "External bridge:external" \
#     "Internal NAT:internal" \
#     "Both:both"
_wiz_choose_mapped() {
  local var_name="$1"
  local header="$2"
  local options_var="$3"
  shift 3

  # Build mapping from display to internal values
  local -A mapping=()
  for pair in "$@"; do
    local display="${pair%%:*}"
    local internal="${pair#*:}"
    mapping["$display"]="$internal"
  done

  local selected
  if ! selected=$(printf '%s\n' "${!options_var}" | _wiz_choose --header="$header"); then
    return 1
  fi

  # Look up internal value and set variable
  local internal_value="${mapping[$selected]:-}"
  if [[ -n $internal_value ]]; then
    declare -g "$var_name=$internal_value"
  fi

  return 0
}

# =============================================================================
# Feature checkbox editor helper
# =============================================================================

# Universal feature checkbox editor with multi-select.
# Handles building gum args for pre-selected items and setting globals.
# Parameters:
#   $1 - Header text (e.g., "Security:", "Monitoring:")
#   $2 - Footer size (number of items + 1 for header)
#   $3 - Options variable name (e.g., "WIZ_FEATURES_SECURITY")
#   $@ - Pairs of "feature_name:INSTALL_VAR_NAME" (e.g., "apparmor:INSTALL_APPARMOR")
# Returns: 0 on success, 1 on cancel
# Side effects: Sets the named INSTALL_* globals to "yes" or "no"
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
