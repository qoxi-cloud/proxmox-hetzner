# shellcheck shell=bash
# SSH hardening and finalization

# Deploys hardened SSH configuration to remote system WITHOUT restarting.
# Uses sshd_config template with ADMIN_USERNAME substitution.
# Called before validation so we can verify the config file.
# shellcheck disable=SC2317 # invoked indirectly by run_with_progress
_deploy_ssh_config() {
  deploy_template "templates/sshd_config" "/etc/ssh/sshd_config" \
    "ADMIN_USERNAME=${ADMIN_USERNAME}" || return 1
}

# Deploys hardened sshd_config without restarting SSH service.
# SSH key was deployed to admin user in 302-configure-admin.sh.
deploy_ssh_hardening_config() {
  if ! run_with_progress "Deploying SSH hardening config" "SSH config deployed" _deploy_ssh_config; then
    log "ERROR: SSH config deploy failed"
    return 1
  fi
}

# Restarts SSH service to apply hardened configuration.
# Called as the LAST SSH operation - after this, password auth is disabled.
restart_ssh_service() {
  log "Restarting SSH to apply hardening"
  # Use run_with_progress for consistent UI
  if ! run_with_progress "Applying SSH hardening" "SSH hardening active" \
    remote_exec "systemctl restart sshd"; then
    log "WARNING: SSH restart failed - config will apply on reboot"
  fi
}

# Installation Validation

# Validates installation by checking packages, services, and configs.
# Uses validation.sh.tmpl with variable substitution for enabled features.
# Shows FAIL/WARN results in live logs for visibility.
validate_installation() {
  log "Generating validation script from template..."

  # Stage template to preserve original
  local staged
  staged=$(mktemp) || {
    log "ERROR: Failed to create temp file for validation.sh"
    return 1
  }
  register_temp_file "$staged"
  cp "./templates/validation.sh" "$staged" || {
    log "ERROR: Failed to stage validation.sh"
    rm -f "$staged"
    return 1
  }

  # Generate validation script with current settings
  apply_template_vars "$staged" \
    "INSTALL_TAILSCALE=${INSTALL_TAILSCALE:-no}" \
    "INSTALL_FIREWALL=${INSTALL_FIREWALL:-no}" \
    "FIREWALL_MODE=${FIREWALL_MODE:-standard}" \
    "INSTALL_APPARMOR=${INSTALL_APPARMOR:-no}" \
    "INSTALL_AUDITD=${INSTALL_AUDITD:-no}" \
    "INSTALL_AIDE=${INSTALL_AIDE:-no}" \
    "INSTALL_CHKROOTKIT=${INSTALL_CHKROOTKIT:-no}" \
    "INSTALL_LYNIS=${INSTALL_LYNIS:-no}" \
    "INSTALL_NEEDRESTART=${INSTALL_NEEDRESTART:-no}" \
    "INSTALL_VNSTAT=${INSTALL_VNSTAT:-no}" \
    "INSTALL_PROMTAIL=${INSTALL_PROMTAIL:-no}" \
    "ADMIN_USERNAME=${ADMIN_USERNAME}" \
    "INSTALL_NETDATA=${INSTALL_NETDATA:-no}" \
    "INSTALL_YAZI=${INSTALL_YAZI:-no}" \
    "INSTALL_NVIM=${INSTALL_NVIM:-no}" \
    "INSTALL_RINGBUFFER=${INSTALL_RINGBUFFER:-no}" \
    "SHELL_TYPE=${SHELL_TYPE:-bash}" \
    "SSL_TYPE=${SSL_TYPE:-self-signed}"
  local validation_script
  validation_script=$(cat "$staged")
  rm -f "$staged"

  log "Validation script generated"
  printf '%s\n' "$validation_script" >>"$LOG_FILE"

  # Execute validation and capture output
  start_task "${CLR_ORANGE}├─${CLR_RESET} Validating installation"
  local task_idx=$TASK_INDEX
  local validation_output
  validation_output=$(printf '%s\n' "$validation_script" | remote_exec 'bash -s' 2>&1) || true
  printf '%s\n' "$validation_output" >>"$LOG_FILE"

  # Parse and display results in live logs
  local errors=0 warnings=0
  while IFS= read -r line; do
    case "$line" in
      FAIL:*)
        add_subtask_log "$line" "$CLR_RED"
        ((errors++))
        ;;
      WARN:*)
        add_subtask_log "$line" "$CLR_YELLOW"
        ((warnings++))
        ;;
    esac
  done <<<"$validation_output"

  # Update task with final status
  if ((errors > 0)); then
    complete_task "$task_idx" "${CLR_ORANGE}├─${CLR_RESET} Validation: ${CLR_RED}${errors} error(s)${CLR_RESET}, ${CLR_YELLOW}${warnings} warning(s)${CLR_RESET}" "error"
    log "ERROR: Installation validation failed with $errors error(s)"
  elif ((warnings > 0)); then
    complete_task "$task_idx" "${CLR_ORANGE}├─${CLR_RESET} Validation passed with ${CLR_YELLOW}${warnings} warning(s)${CLR_RESET}" "warning"
  else
    complete_task "$task_idx" "${CLR_ORANGE}├─${CLR_RESET} Validation passed"
  fi
}

# Finalizes VM by powering it off and waiting for QEMU to exit.
# Uses SIGTERM to QEMU process for ACPI shutdown (SSH is disabled after hardening)
finalize_vm() {
  # Send SIGTERM to QEMU for graceful ACPI shutdown
  # This is more reliable than SSH after hardening disables password auth
  (
    if kill -0 "$QEMU_PID" 2>/dev/null; then
      kill -TERM "$QEMU_PID" 2>/dev/null || true
    fi
  ) &
  show_progress $! "Powering off the VM"

  # Wait for QEMU to exit
  (
    local timeout="${VM_SHUTDOWN_TIMEOUT:-120}"
    local wait_interval="${PROCESS_KILL_WAIT:-1}"
    local elapsed=0
    while ((elapsed < timeout)); do
      if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        exit 0
      fi
      sleep "$wait_interval"
      ((elapsed += wait_interval))
    done
    exit 1
  ) &
  local wait_pid=$!

  show_progress $wait_pid "Waiting for QEMU process to exit" "QEMU process exited"
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: QEMU process did not exit cleanly within 120 seconds"
    # Force kill if still running
    kill -9 "$QEMU_PID" 2>/dev/null || true
  fi
}

# Main configuration function

# Main entry point for post-install Proxmox configuration via SSH.
# Orchestrates all configuration steps with parallel execution where safe.
# Uses batch package installation and parallel config groups for speed.
configure_proxmox_via_ssh() {
  log "Starting Proxmox configuration via SSH"

  _phase_base_configuration || {
    log "ERROR: Base configuration failed"
    return 1
  }
  _phase_storage_configuration || {
    log "ERROR: Storage configuration failed"
    return 1
  }
  _phase_security_configuration || {
    log "ERROR: Security configuration failed"
    return 1
  }
  _phase_monitoring_tools || {
    log "WARNING: Monitoring tools configuration had issues"
    # Non-fatal: continue with installation
  }
  _phase_ssl_api || {
    log "WARNING: SSL/API configuration had issues"
    # Non-fatal: continue with installation
  }
  _phase_finalization || {
    log "ERROR: Finalization failed"
    return 1
  }
}
