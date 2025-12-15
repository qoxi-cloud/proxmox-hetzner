# shellcheck shell=bash
# =============================================================================
# Template deployment helpers
# =============================================================================

# Deploys template: downloads, applies variables, and copies to remote.
# Parameters:
#   $1 - Template name (without .tmpl extension)
#   $2 - Destination path on remote system
#   $@ - VAR=VALUE pairs for substitution (optional)
# Returns: 0 on success, 1 on failure
# Side effects: Downloads template, modifies it, copies to remote via SCP
deploy_template() {
  local template_name="$1"
  local dest_path="$2"
  shift 2
  local -a vars=("$@")

  local local_template="./templates/$template_name"

  # Download template
  if ! download_template "$local_template"; then
    log "ERROR: Failed to download template: $template_name"
    return 1
  fi

  # Apply variable substitutions if provided
  if [[ ${#vars[@]} -gt 0 ]]; then
    if ! apply_template_vars "$local_template" "${vars[@]}"; then
      log "ERROR: Failed to apply variables to template: $template_name"
      return 1
    fi
  else
    # Apply common template variables
    if ! apply_common_template_vars "$local_template"; then
      log "ERROR: Failed to apply common variables to template: $template_name"
      return 1
    fi
  fi

  # Copy to remote system
  if ! remote_copy "$local_template" "$dest_path"; then
    log "ERROR: Failed to copy template to remote: $template_name → $dest_path"
    return 1
  fi

  log "Template deployed successfully: $template_name → $dest_path"
  return 0
}

# Deploys multiple templates in parallel for faster execution.
# Parameters:
#   Pairs of: template_name dest_path [template_name dest_path ...]
# Returns: 0 if all succeeded, 1 if any failed
# Side effects: Deploys templates via deploy_template in parallel
deploy_templates() {
  local -a cmds=()

  # Build array of deploy_template commands
  while [[ $# -gt 0 ]]; do
    local template="$1"
    local dest="$2"
    shift 2

    cmds+=("deploy_template '$template' '$dest'")
  done

  # Execute all deployments in parallel
  run_parallel "${cmds[@]}"
}
