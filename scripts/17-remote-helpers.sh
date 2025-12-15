# shellcheck shell=bash
# =============================================================================
# Remote execution helpers
# =============================================================================

# Installs packages on remote system via apt with standard error handling.
# Parameters:
#   $@ - Package names to install
# Returns: 0 on success, exits on failure
# Side effects: Updates apt cache, installs packages via run_remote
remote_apt_install() {
  local packages="$*"

  if [[ -z $packages ]]; then
    log "ERROR: No packages specified for installation"
    return 1
  fi

  run_remote "Installing packages: $packages" "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || exit 1
    apt-get install -yqq $packages || exit 1
  " "Packages installed: $packages"
}

# Executes remote command with automatic retry on failure.
# Parameters:
#   $1 - Maximum retries (default: 3)
#   $2 - Message describing the operation
#   $3 - Command to execute remotely
#   $4 - Optional: done message
# Returns: 0 on success, 1 if all retries exhausted
remote_exec_retry() {
  local max_retries="${1:-3}"
  local message="$2"
  local command="$3"
  local done_message="${4:-$message}"

  retry_command "$max_retries" 2 remote_exec "$message" "$command" "$done_message"
}
