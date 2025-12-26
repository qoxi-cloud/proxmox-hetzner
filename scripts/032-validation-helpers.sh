# shellcheck shell=bash
# Validation UI helpers

# Show validation error with 3s pause. $1=message
show_validation_error() {
  local message="$1"

  # Hide cursor during error display
  _wiz_hide_cursor

  # Show error message (replaces blank line, footer stays below)
  _wiz_error "$message"
  sleep "${WIZARD_MESSAGE_DELAY:-3}"
}
