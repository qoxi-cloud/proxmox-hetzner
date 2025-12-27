# shellcheck shell=bash
# Template deployment helpers

# Deploy config to admin home. Creates dirs, sets ownership, applies template vars.
# $1=template, $2=relative_path (e.g. ".config/bat/config"), $@=VAR=value (optional)
deploy_user_config() {
  local template="$1"
  local relative_path="$2"
  shift 2
  local home_dir="/home/${ADMIN_USERNAME}"
  local dest="${home_dir}/${relative_path}"
  local dest_dir staged
  dest_dir="$(dirname "$dest")"

  # Stage template to temp location to preserve original
  staged=$(mktemp) || {
    log "ERROR: Failed to create temp file for $template"
    return 1
  }
  register_temp_file "$staged"
  cp "$template" "$staged" || {
    log "ERROR: Failed to stage template $template"
    rm -f "$staged"
    return 1
  }

  # Apply template vars (also validates no unsubstituted placeholders remain)
  apply_template_vars "$staged" "$@" || {
    log "ERROR: Template substitution failed for $template"
    rm -f "$staged"
    return 1
  }

  # Create parent directory if needed (skip if deploying to home root)
  if [[ "$dest_dir" != "$home_dir" ]]; then
    remote_exec "mkdir -p '$dest_dir'" || {
      log "ERROR: Failed to create directory $dest_dir"
      rm -f "$staged"
      return 1
    }
    # Fix ownership of ALL directories created by mkdir -p (they're created as root)
    # Walk up from dest_dir to home, collecting all intermediate directories
    local dirs_to_chown=""
    local dir="$dest_dir"
    while [[ "$dir" != "$home_dir" && "$dir" != "/" ]]; do
      dirs_to_chown+="'$dir' "
      dir="$(dirname "$dir")"
    done
    remote_exec "chown ${ADMIN_USERNAME}:${ADMIN_USERNAME} $dirs_to_chown" || {
      log "ERROR: Failed to set ownership on $dirs_to_chown"
      rm -f "$staged"
      return 1
    }
  fi

  # Copy file
  remote_copy "$staged" "$dest" || {
    log "ERROR: Failed to copy $template to $dest"
    rm -f "$staged"
    return 1
  }
  rm -f "$staged"

  # Set ownership
  remote_exec "chown ${ADMIN_USERNAME}:${ADMIN_USERNAME} '$dest'" || {
    log "ERROR: Failed to set ownership on $dest"
    return 1
  }
}

# Run command with progress spinner. $1=message, $2=done_message, $@=command
run_with_progress() {
  local message="$1"
  local done_message="$2"
  shift 2

  (
    "$@" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "$message" "$done_message"
}

# Deploy .service + .timer and enable. $1=timer_name, $2=template_dir (optional)
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

  remote_exec "systemctl daemon-reload && systemctl enable --now ${timer_name}.timer" || {
    log "ERROR: Failed to enable ${timer_name} timer"
    return 1
  }
}

# Deploy template with variable substitution. $1=template, $2=dest, $@=VAR=value
# For .service files: validates ExecStart exists and verifies remote copy
deploy_template() {
  local template="$1"
  local dest="$2"
  shift 2
  local staged
  local is_service=false
  [[ $dest == *.service ]] && is_service=true

  # Stage template to temp location to preserve original
  staged=$(mktemp) || {
    log "ERROR: Failed to create temp file for $template"
    return 1
  }
  register_temp_file "$staged"
  cp "$template" "$staged" || {
    log "ERROR: Failed to stage template $template"
    rm -f "$staged"
    return 1
  }

  # Apply template vars (also validates no unsubstituted placeholders remain)
  apply_template_vars "$staged" "$@" || {
    log "ERROR: Template substitution failed for $template"
    rm -f "$staged"
    return 1
  }

  # For .service files, verify ExecStart exists after substitution
  if [[ $is_service == true ]] && ! grep -q "ExecStart=" "$staged" 2>/dev/null; then
    log "ERROR: Service file $dest missing ExecStart after template substitution"
    rm -f "$staged"
    return 1
  fi

  # Create parent directory on remote if needed
  local dest_dir
  dest_dir=$(dirname "$dest")
  remote_exec "mkdir -p '$dest_dir'" || {
    log "ERROR: Failed to create directory $dest_dir"
    rm -f "$staged"
    return 1
  }

  remote_copy "$staged" "$dest" || {
    log "ERROR: Failed to deploy $template to $dest"
    rm -f "$staged"
    return 1
  }
  rm -f "$staged"

  # For .service files, verify remote copy wasn't corrupted
  if [[ $is_service == true ]]; then
    remote_exec "grep -q 'ExecStart=' '$dest'" || {
      log "ERROR: Remote service file $dest appears corrupted (missing ExecStart)"
      return 1
    }
  fi
}

# Deploy .service with template vars and enable. $1=service_name, $@=VAR=value
# Wrapper around deploy_template that also enables the service
deploy_systemd_service() {
  local service_name="$1"
  shift
  local template="templates/${service_name}.service"
  local dest="/etc/systemd/system/${service_name}.service"

  # Deploy using common function
  deploy_template "$template" "$dest" "$@" || return 1

  remote_enable_services "${service_name}.service"
}

# Enable multiple systemd services (with daemon-reload). $@=service names
remote_enable_services() {
  local services=("$@")

  if [[ ${#services[@]} -eq 0 ]]; then
    return 0
  fi

  remote_exec "systemctl daemon-reload && systemctl enable --now ${services[*]}" || {
    log "ERROR: Failed to enable services: ${services[*]}"
    return 1
  }
}

# Batch deploy configs to admin home. $@="template:relative_dest" pairs
deploy_user_configs() {
  for pair in "$@"; do
    local template="${pair%%:*}"
    local relative="${pair#*:}"
    deploy_user_config "$template" "$relative" || return 1
  done
}
