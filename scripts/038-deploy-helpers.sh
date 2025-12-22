# shellcheck shell=bash
# =============================================================================
# Deployment helpers for DRY configuration code
# Reduces duplication in configure scripts by providing common patterns
# =============================================================================

# Deploys a config file to admin user's home directory.
# Creates parent directories and sets correct ownership.
# Uses global ADMIN_USERNAME.
# Parameters:
#   $1 - Template source path (e.g., "templates/bat-config")
#   $2 - Relative path from home (e.g., ".config/bat/config")
# Returns: 0 on success, 1 on failure
# Example: deploy_user_config "templates/bat-config" ".config/bat/config"
deploy_user_config() {
  local template="$1"
  local relative_path="$2"
  local dest="/home/${ADMIN_USERNAME}/${relative_path}"
  local dest_dir
  dest_dir="$(dirname "$dest")"

  # Create parent directory if needed (skip if deploying to home root)
  if [[ "$dest_dir" != "/home/${ADMIN_USERNAME}" ]]; then
    remote_exec "mkdir -p '$dest_dir'" || {
      log "ERROR: Failed to create directory $dest_dir"
      return 1
    }
  fi

  # Copy file
  remote_copy "$template" "$dest" || {
    log "ERROR: Failed to copy $template to $dest"
    return 1
  }

  # Set ownership
  remote_exec "chown ${ADMIN_USERNAME}:${ADMIN_USERNAME} '$dest'" || {
    log "ERROR: Failed to set ownership on $dest"
    return 1
  }
}

# Runs a command in background with progress indicator.
# Simplifies the common pattern of (cmd) >/dev/null 2>&1 & show_progress
# Parameters:
#   $1 - Progress message
#   $2 - Done message (or command if only 2 args after shift)
#   $@ - Command and arguments to run
# Returns: Exit code from the command
run_with_progress() {
  local message="$1"
  local done_message="$2"
  shift 2

  (
    "$@" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "$message" "$done_message"
}

# Deploys a systemd timer (both .service and .timer files).
# Handles remote_copy for both files and enables the timer.
# Parameters:
#   $1 - Timer name (e.g., "aide-check" for aide-check.service/timer)
#   $2 - Optional: directory prefix in templates (default: "")
# Returns: 0 on success, 1 on failure
# Side effects: Copies files to remote, enables timer
deploy_systemd_timer() {
  local timer_name="$1"
  local template_dir="${2:+$2/}"

  remote_copy "templates/${template_dir}${timer_name}.service" \
    "/etc/systemd/system/${timer_name}.service" || {
    log "ERROR: Failed to deploy ${timer_name} service"
    return 1
  }

  remote_copy "templates/${template_dir}${timer_name}.timer" \
    "/etc/systemd/system/${timer_name}.timer" || {
    log "ERROR: Failed to deploy ${timer_name} timer"
    return 1
  }

  remote_exec "systemctl daemon-reload && systemctl enable ${timer_name}.timer" || {
    log "ERROR: Failed to enable ${timer_name} timer"
    return 1
  }
}

# Deploys a systemd service file (with optional template vars) and enables it.
# Parameters:
#   $1 - Service name (e.g., "network-ringbuffer" for network-ringbuffer.service)
#   $@ - Optional: template variable assignments (VAR=value format)
# Returns: 0 on success, 1 on failure
deploy_systemd_service() {
  local service_name="$1"
  shift
  local template="templates/${service_name}.service"
  local dest="/etc/systemd/system/${service_name}.service"

  # Apply template vars if provided
  if [[ $# -gt 0 ]]; then
    apply_template_vars "$template" "$@"
  fi

  remote_copy "$template" "$dest" || {
    log "ERROR: Failed to deploy ${service_name} service"
    return 1
  }

  remote_exec "systemctl daemon-reload && systemctl enable ${service_name}.service" || {
    log "ERROR: Failed to enable ${service_name} service"
    return 1
  }
}

# Enables multiple systemd services in a single remote call.
# Use when services are already installed via packages (not custom .service files).
# Parameters:
#   $@ - Service names to enable
# Returns: 0 on success, 1 on failure
remote_enable_services() {
  local services=("$@")

  if [[ ${#services[@]} -eq 0 ]]; then
    return 0
  fi

  remote_exec "systemctl enable ${services[*]}" || {
    log "ERROR: Failed to enable services: ${services[*]}"
    return 1
  }
}

# Deploys a template with variable substitution and copies to remote.
# Combines apply_template_vars + remote_copy pattern.
# Parameters:
#   $1 - Template source path
#   $2 - Remote destination path
#   $@ - Variable assignments (VAR=value format)
# Returns: 0 on success, 1 on failure
deploy_template() {
  local template="$1"
  local dest="$2"
  shift 2

  # Apply template vars if any provided
  if [[ $# -gt 0 ]]; then
    apply_template_vars "$template" "$@"
  fi

  remote_copy "$template" "$dest" || {
    log "ERROR: Failed to deploy $template to $dest"
    return 1
  }
}
