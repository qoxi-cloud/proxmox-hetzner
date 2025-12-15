# shellcheck shell=bash
# =============================================================================
# General utilities
# =============================================================================
# NOTE: Many functions have been moved to specialized modules:
# - download_file → 09-downloads.sh
# - apply_template_vars, download_template → 09a-templates.sh
# - generate_password, read_password → 09b-password-utils.sh
# - show_progress, show_timed_progress → 01-display.sh
# =============================================================================

# Prompts for input with validation loop until valid value provided.
# Parameters:
#   $1 - Prompt text
#   $2 - Default value
#   $3 - Validator function name
#   $4 - Error message for invalid input
# Returns: Validated input value via stdout
prompt_validated() {
  local prompt="$1"
  local default="$2"
  local validator="$3"
  local error_msg="$4"
  local result=""

  while true; do
    read -r -e -p "$prompt" -i "$default" result
    if $validator "$result"; then
      echo "$result"
      return 0
    fi
    print_error "$error_msg"
  done
}
