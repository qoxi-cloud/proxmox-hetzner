# shellcheck shell=bash
# =============================================================================
# SSH hardening and finalization
# =============================================================================

# Deploys hardened SSH configuration to remote system.
# Uses sshd_config template with ADMIN_USERNAME substitution.
# Side effects: Restarts sshd, disables password auth
# shellcheck disable=SC2317 # invoked indirectly by run_with_progress
_config_ssh_hardening() {
  # Apply ADMIN_USERNAME template variable to sshd_config
  deploy_template "templates/sshd_config" "/etc/ssh/sshd_config" \
    "ADMIN_USERNAME=${ADMIN_USERNAME}" || return 1
  # Restart SSH to apply new config
  remote_exec "systemctl restart sshd" || return 1
}

# Configures SSH hardening with key-based authentication only.
# Deploys hardened sshd_config (SSH key is deployed to admin user in 302-configure-admin.sh).
# Side effects: Disables password authentication, blocks root login
configure_ssh_hardening() {
  # Deploy SSH hardening LAST (after all other operations)
  # CRITICAL: This must succeed - if it fails, system remains with password auth enabled
  # NOTE: SSH key was deployed to admin user in 302-configure-admin.sh (root has no SSH access)

  if ! run_with_progress "Deploying SSH hardening" "Security hardening configured" _config_ssh_hardening; then
    log "ERROR: SSH hardening failed - system may be insecure"
    exit 1
  fi
}

# =============================================================================
# Installation Validation
# =============================================================================

# Validates installation by checking packages, services, and configs.
# Uses validation.sh.tmpl with variable substitution for enabled features.
# Shows FAIL/WARN results in live logs for visibility.
validate_installation() {
  log "Generating validation script from template..."

  # Generate validation script with current settings
  apply_template_vars "./templates/validation.sh" \
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
  validation_script=$(cat "./templates/validation.sh")

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
        add_log "${CLR_ORANGE}│${CLR_RESET}   ${CLR_RED}${line}${CLR_RESET}"
        ((errors++))
        ;;
      WARN:*)
        add_log "${CLR_ORANGE}│${CLR_RESET}   ${CLR_YELLOW}${line}${CLR_RESET}"
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
    local timeout=120
    local elapsed=0
    while ((elapsed < timeout)); do
      if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        exit 0
      fi
      sleep 1
      ((elapsed += 1))
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

# =============================================================================
# Main configuration function
# =============================================================================

# Main entry point for post-install Proxmox configuration via SSH.
# Orchestrates all configuration steps with parallel execution where safe.
# Uses batch package installation and parallel config groups for speed.
configure_proxmox_via_ssh() {
  log "Starting Proxmox configuration via SSH"

  # ==========================================================================
  # PHASE 1: Base Configuration (sequential - dependencies)
  # ==========================================================================
  make_templates
  configure_admin_user # Must be first - other configs need admin user's home dir
  configure_base_system
  configure_shell
  configure_system_services

  # ==========================================================================
  # PHASE 2: Storage Configuration (sequential - ZFS dependencies)
  # ==========================================================================
  configure_zfs_arc
  configure_zfs_pool
  configure_zfs_scrub

  # ==========================================================================
  # PHASE 3: Security Configuration (parallel after batch install)
  # ==========================================================================
  # Batch install security & optional packages first
  # Uses remote_run internally - exits on failure
  batch_install_packages

  # Tailscale (needs package installed, needed for firewall rules)
  configure_tailscale

  # Firewall next (depends on tailscale for rule generation)
  configure_firewall

  # Parallel security configuration
  run_parallel_group "Configuring security" "Security features configured" \
    configure_apparmor \
    configure_fail2ban \
    configure_auditd \
    configure_aide \
    configure_chkrootkit \
    configure_lynis \
    configure_needrestart

  # ==========================================================================
  # PHASE 4: Monitoring & Tools (parallel where possible)
  # ==========================================================================
  # Special installers (non-apt) - run in parallel
  (
    local pids=()
    if [[ $INSTALL_NETDATA == "yes" ]]; then
      configure_netdata &
      pids+=($!)
    fi
    if [[ $INSTALL_YAZI == "yes" ]]; then
      configure_yazi &
      pids+=($!)
    fi
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
  ) >/dev/null 2>&1 &
  local special_pid=$!

  # Parallel config for apt-installed tools (packages already installed by batch)
  run_parallel_group "Configuring tools" "Tools configured" \
    configure_promtail \
    configure_vnstat \
    configure_ringbuffer \
    configure_nvim

  # Wait for special installers
  wait $special_pid 2>/dev/null || true

  # ==========================================================================
  # PHASE 5: SSL & API Configuration
  # ==========================================================================
  configure_ssl_certificate
  if [[ $INSTALL_API_TOKEN == "yes" ]]; then
    run_with_progress "Creating API token" "API token created" create_api_token
  fi

  # ==========================================================================
  # PHASE 6: Validation & Finalization
  # ==========================================================================
  # Validate BEFORE SSH hardening (after hardening, password SSH is disabled)
  validate_installation

  # SSH hardening is the LAST SSH operation - after this, password auth is disabled
  # and root login is blocked. Only admin user with SSH key can connect.
  configure_ssh_hardening

  # Power off VM - SSH no longer available, use QEMU ACPI shutdown
  finalize_vm
}
