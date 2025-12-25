# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Input Helpers
# =============================================================================
# Reusable input patterns for validation and filtering

# =============================================================================
# Validated input helper
# =============================================================================

# Input field with validation loop.
# Prompts user until valid input or cancel (empty input).
# Parameters:
#   $1 - Validation function name (e.g., "validate_hostname")
#   $2 - Error message on validation failure
#   $@ - All remaining args passed to _wiz_input (--prompt, --value, etc.)
# Returns: 0 with value on stdout if valid, 1 on cancel
# Side effects: None (caller sets global)
# Example:
#   hostname=$(_wiz_input_validated "validate_hostname" "Invalid hostname format" \
#     --placeholder "e.g., pve" --value "$PVE_HOSTNAME" --prompt "Hostname: ")
_wiz_input_validated() {
  local validate_func="$1"
  local error_msg="$2"
  shift 2

  while true; do
    _wiz_start_edit
    _show_input_footer

    local value
    value=$(_wiz_input "$@")

    # Empty means cancelled
    [[ -z $value ]] && return 1

    if "$validate_func" "$value"; then
      printf '%s' "$value"
      return 0
    fi

    show_validation_error "$error_msg"
  done
}

# =============================================================================
# Filter select helper
# =============================================================================

# Filter list with variable assignment.
# Common pattern for timezone, keyboard, country selection.
# Parameters:
#   $1 - Variable name to set (e.g., "TIMEZONE")
#   $2 - Prompt text (e.g., "Timezone: ")
#   $3 - Data to filter (newline-separated list)
#   $4 - Optional: footer height (default: 6)
# Returns: 0 on selection, 1 on cancel
# Side effects: Sets the named global variable
# Example:
#   _wiz_filter_select "TIMEZONE" "Timezone: " "$WIZ_TIMEZONES"
_wiz_filter_select() {
  local var_name="$1"
  local prompt="$2"
  local data="$3"
  local height="${4:-6}"

  _wiz_start_edit
  _show_input_footer "filter" "$height"

  local selected
  if ! selected=$(printf '%s' "$data" | _wiz_filter --prompt "$prompt"); then
    return 1
  fi

  declare -g "$var_name=$selected"
}
