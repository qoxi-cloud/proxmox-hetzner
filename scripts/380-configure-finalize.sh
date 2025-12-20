# shellcheck shell=bash
# =============================================================================
# SSH hardening and finalization
# =============================================================================

# Configures SSH hardening with key-based authentication only.
# Deploys hardened sshd_config (SSH key already added via answer.toml).
# Side effects: Disables password authentication on remote system
configure_ssh_hardening() {
  # Deploy SSH hardening LAST (after all other operations)
  # CRITICAL: This must succeed - if it fails, system remains with password auth enabled
  # NOTE: SSH key was already deployed via answer.toml root_ssh_keys parameter

  # shellcheck disable=SC2329 # invoked by run_with_progress
  _ssh_hardening_impl() {
    remote_copy "templates/sshd_config" "/etc/ssh/sshd_config" || return 1
    remote_exec "chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"
  }

  if ! run_with_progress "Deploying SSH hardening" "Security hardening configured" _ssh_hardening_impl; then
    log "ERROR: SSH hardening failed - system may be insecure"
    exit 1
  fi
}

# =============================================================================
# Installation Validation
# =============================================================================

# Validates installation by checking packages, services, and configs.
# Uses validation.sh.tmpl with variable substitution for enabled features.
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
    "INSTALL_PROMETHEUS=${INSTALL_PROMETHEUS:-no}" \
    "INSTALL_NETDATA=${INSTALL_NETDATA:-no}" \
    "INSTALL_YAZI=${INSTALL_YAZI:-no}" \
    "INSTALL_NVIM=${INSTALL_NVIM:-no}" \
    "INSTALL_RINGBUFFER=${INSTALL_RINGBUFFER:-no}" \
    "SHELL_TYPE=${SHELL_TYPE:-bash}" \
    "SSL_TYPE=${SSL_TYPE:-self-signed}"
  local validation_script
  validation_script=$(cat "./templates/validation.sh")

  log "Validation script generated"
  echo "$validation_script" >>"$LOG_FILE"

  # Execute validation on remote
  (
    echo "$validation_script" | remote_exec 'bash -s' 2>&1 | tee -a "$LOG_FILE" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Validating installation" "Installation validated"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Installation validation failed"
    print_error "Installation validation failed - check $LOG_FILE for details"
    exit 1
  fi
}

# Finalizes VM by powering it off and waiting for QEMU to exit.
finalize_vm() {
  # Power off the VM
  remote_exec "poweroff" >/dev/null 2>&1 &
  show_progress $! "Powering off the VM"

  # Wait for QEMU to exit with background process
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
# Parallel configuration helpers
# =============================================================================

# Wrapper functions that check INSTALL_* and call _config_* silently.
# These are designed for parallel execution after batch package install.
# Each function returns 0 (skip) if feature not enabled, or runs config.

_parallel_config_apparmor() {
  [[ ${INSTALL_APPARMOR:-} != "yes" ]] && return 0
  _config_apparmor
}

_parallel_config_fail2ban() {
  # Requires firewall and not stealth mode
  [[ ${INSTALL_FIREWALL:-} != "yes" || ${FIREWALL_MODE:-standard} == "stealth" ]] && return 0
  _config_fail2ban
}

_parallel_config_auditd() {
  [[ ${INSTALL_AUDITD:-} != "yes" ]] && return 0
  _config_auditd
}

_parallel_config_aide() {
  [[ ${INSTALL_AIDE:-} != "yes" ]] && return 0
  _config_aide
}

_parallel_config_chkrootkit() {
  [[ ${INSTALL_CHKROOTKIT:-} != "yes" ]] && return 0
  _config_chkrootkit
}

_parallel_config_lynis() {
  [[ ${INSTALL_LYNIS:-} != "yes" ]] && return 0
  _config_lynis
}

_parallel_config_needrestart() {
  [[ ${INSTALL_NEEDRESTART:-} != "yes" ]] && return 0
  _config_needrestart
}

_parallel_config_prometheus() {
  [[ ${INSTALL_PROMETHEUS:-} != "yes" ]] && return 0
  _config_prometheus
}

_parallel_config_vnstat() {
  [[ ${INSTALL_VNSTAT:-} != "yes" ]] && return 0
  _config_vnstat
}

_parallel_config_ringbuffer() {
  [[ ${INSTALL_RINGBUFFER:-} != "yes" ]] && return 0
  _config_ringbuffer
}

_parallel_config_nvim() {
  [[ ${INSTALL_NVIM:-} != "yes" ]] && return 0
  _config_nvim
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
  batch_install_packages

  # Tailscale (needs package installed, needed for firewall rules)
  configure_tailscale

  # Firewall next (depends on tailscale for rule generation)
  configure_firewall

  # Parallel security configuration
  run_parallel_group "Configuring security" "Security features configured" \
    _parallel_config_apparmor \
    _parallel_config_fail2ban \
    _parallel_config_auditd \
    _parallel_config_aide \
    _parallel_config_chkrootkit \
    _parallel_config_lynis \
    _parallel_config_needrestart

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
    _parallel_config_prometheus \
    _parallel_config_vnstat \
    _parallel_config_ringbuffer \
    _parallel_config_nvim

  # Wait for special installers
  wait $special_pid 2>/dev/null || true

  # ==========================================================================
  # PHASE 5: SSL & API Configuration
  # ==========================================================================
  configure_ssl_certificate
  if [[ $INSTALL_API_TOKEN == "yes" ]]; then
    (create_api_token || exit 1) >/dev/null 2>&1 &
    show_progress $! "Creating API token" "API token created"
  fi

  # ==========================================================================
  # PHASE 6: Validation & Finalization
  # ==========================================================================
  configure_ssh_hardening
  validate_installation
  finalize_vm
}
