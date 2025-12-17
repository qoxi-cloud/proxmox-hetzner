# shellcheck shell=bash
# =============================================================================
# Validation UI helpers
# =============================================================================

# Displays validation error message in gum style with consistent formatting.
# Parameters:
#   $1 - Error message to display
# Side effects: Outputs to stdout, pauses for 1 second
show_validation_error() {
  local message="$1"
  gum style --foreground "$HEX_RED" "$message"
  sleep 1
}

# Validates value and shows error message if invalid.
# Parameters:
#   $1 - Validator function name
#   $2 - Value to validate
#   $3 - Error message to display if invalid
# Returns: 0 if valid, 1 if invalid
# Side effects: Shows error via show_validation_error on failure
validate_with_error() {
  local validator="$1"
  local value="$2"
  local error_message="$3"

  if ! "$validator" "$value"; then
    show_validation_error "$error_message"
    return 1
  fi

  return 0
}
