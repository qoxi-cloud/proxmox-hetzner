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

  (
    # Deploy hardened sshd_config (disables password auth, etc.)
    remote_copy "templates/sshd_config" "/etc/ssh/sshd_config" || exit 1
    # Ensure correct permissions on SSH directory (should already be set by installer)
    remote_exec "chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Deploying SSH hardening" "Security hardening configured"
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: SSH hardening failed - system may be insecure"
    exit 1
  fi
}

# Validates that core Proxmox services are installed and running.
# Performs basic sanity checks before finalization.
validate_installation() {
  (
    remote_exec '
      # Check if Proxmox VE packages are installed
      if ! dpkg -l | grep -q "proxmox-ve"; then
        echo "ERROR: Proxmox VE package not found"
        exit 1
      fi

      # Check if pveproxy service is running (Proxmox web interface)
      if ! systemctl is-active --quiet pveproxy; then
        echo "ERROR: pveproxy service is not running"
        exit 1
      fi

      # Check if pvedaemon is running (Proxmox API daemon)
      if ! systemctl is-active --quiet pvedaemon; then
        echo "ERROR: pvedaemon service is not running"
        exit 1
      fi

      # Check if ZFS pool exists (rpool for full ZFS install, or tank for ext4 boot + ZFS pool)
      if ! zpool list 2>/dev/null | grep -qE "^(rpool|tank) "; then
        # If neither pool exists, check if this is an ext4-only installation (valid for single disk without ZFS)
        if ! mount | grep -q "on / type ext4"; then
          echo "ERROR: Neither ZFS pool (rpool/tank) nor ext4 root filesystem found"
          exit 1
        fi
      fi

      exit 0
    ' || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Validating installation" "Installation validated"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Installation validation failed"
    print_error "Installation validation failed - review logs for details"
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
  if type live_log_storage_configuration &>/dev/null 2>&1; then
    live_log_storage_configuration
  fi
  configure_zfs_arc
  configure_zfs_pool
  configure_zfs_scrub

  # ==========================================================================
  # PHASE 3: Security Configuration (parallel after batch install)
  # ==========================================================================
  if type live_log_security_configuration &>/dev/null 2>&1; then
    live_log_security_configuration
  fi

  # Tailscale first (uses curl installer, needed for firewall rules)
  configure_tailscale

  # Firewall next (depends on tailscale for rule generation)
  configure_firewall

  # Batch install remaining security packages
  batch_install_packages

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
  if type live_log_monitoring_configuration &>/dev/null 2>&1; then
    live_log_monitoring_configuration
  fi

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
  if type live_log_ssl_configuration &>/dev/null 2>&1; then
    live_log_ssl_configuration
  fi
  configure_ssl_certificate
  if [[ $INSTALL_API_TOKEN == "yes" ]]; then
    (create_api_token || exit 1) >/dev/null 2>&1 &
    show_progress $! "Creating API token" "API token created"
  fi

  # ==========================================================================
  # PHASE 6: Validation & Finalization
  # ==========================================================================
  if type live_log_validation_finalization &>/dev/null 2>&1; then
    live_log_validation_finalization
  fi
  configure_ssh_hardening
  validate_installation
  finalize_vm
}
