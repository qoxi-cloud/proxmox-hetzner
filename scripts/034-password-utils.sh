# shellcheck shell=bash
# =============================================================================
# Password utilities
# =============================================================================

# Generates a secure random password.
# Parameters:
#   $1 - Password length (default: 16)
# Returns: Random password via stdout
generate_password() {
  local length="${1:-16}"
  # Use /dev/urandom with base64, filter to alphanumeric + some special chars
  tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c "$length"
}
