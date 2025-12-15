# shellcheck shell=bash
# =============================================================================
# Optional feature installation helpers
# =============================================================================

# Universal optional feature installer with standardized error handling.
# Parameters:
#   $1 - Feature name (for display)
#   $2 - Install variable name (e.g., "USE_FAIL2BAN")
#   $3 - Installation function name
#   $4 - Configuration function name
#   $5 - Optional: installed variable name (e.g., "FAIL2BAN_INSTALLED")
# Returns: 0 on success or skip, exits on fatal error
# Side effects: Calls provided functions, updates installed variable if provided
install_optional_feature() {
  local feature_name="$1"
  local install_var="$2"
  local install_func="$3"
  local config_func="$4"
  local installed_var="${5:-}"

  # Check if feature should be installed
  if [[ ${!install_var} != "yes" ]]; then
    log "Skipping $feature_name (not requested)"
    return 0
  fi

  # Run installation function
  if ! "$install_func"; then
    log "ERROR: $feature_name installation failed"
    print_error "$feature_name installation failed"
    exit 1
  fi

  # Run configuration function (non-fatal on failure)
  if ! "$config_func"; then
    log "WARNING: $feature_name configuration failed"
    print_warning "$feature_name configuration failed - continuing without it"
    return 0 # Non-fatal error for config
  fi

  # Mark as installed if variable name provided
  if [[ -n $installed_var ]]; then
    eval "$installed_var=yes"
    log "$feature_name installed and configured successfully"
  fi

  return 0
}
