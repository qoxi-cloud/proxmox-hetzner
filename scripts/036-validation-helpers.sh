# shellcheck shell=bash
# =============================================================================
# Validation UI helpers
# =============================================================================

# Displays validation error message in gum style with consistent formatting.
# Should be called after input components that use _show_input_footer.
# The error will be displayed above the footer with a blank line separator.
# Parameters:
#   $1 - Error message to display
# Side effects: Outputs to stdout, pauses for 3 seconds
show_validation_error() {
  local message="$1"

  # Hide cursor during error display
  _wiz_hide_cursor

  # Show error message (replaces blank line, footer stays below)
  _wiz_error "$message"
  sleep 3
}
