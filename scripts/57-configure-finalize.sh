# shellcheck shell=bash
# =============================================================================
# SSH hardening and finalization
# =============================================================================

# Configures SSH hardening with key-based authentication only.
# Deploys SSH public key and hardens sshd_config.
# Side effects: Disables password authentication on remote system
configure_ssh_hardening() {
  # Deploy SSH hardening LAST (after all other operations)
  # CRITICAL: This must succeed - if it fails, system remains with password auth enabled
  # NOTE: SSH key already validated in wizard (validate_ssh_key in 20-validation.sh)

  # Escape single quotes in SSH key to prevent injection
  local escaped_ssh_key="${SSH_PUBLIC_KEY//\'/\'\\\'\'}"

  (
    remote_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh" || exit 1
    remote_exec "echo '${escaped_ssh_key}' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" || exit 1
    remote_copy "templates/sshd_config" "/etc/ssh/sshd_config" || exit 1
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

      # Check if ZFS pool exists
      if ! zpool list | grep -q "rpool"; then
        echo "ERROR: ZFS root pool (rpool) not found"
        exit 1
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
# Main configuration function
# =============================================================================

# Main entry point for post-install Proxmox configuration via SSH.
# Orchestrates all configuration steps: templates, base, services, security.
configure_proxmox_via_ssh() {
  log "Starting Proxmox configuration via SSH"
  make_templates
  configure_base_system
  configure_zfs_arc
  configure_zfs_pool
  configure_shell
  configure_system_services

  # Security Configuration section (if applicable)
  if type live_log_security_configuration &>/dev/null 2>&1; then
    live_log_security_configuration
  fi
  configure_tailscale
  configure_fail2ban
  configure_auditd
  configure_prometheus
  configure_yazi
  configure_nvim

  # SSL Configuration section (if applicable)
  if type live_log_ssl_configuration &>/dev/null 2>&1; then
    live_log_ssl_configuration
  fi
  configure_ssl_certificate

  # Create API token (non-fatal if fails)
  if [[ $INSTALL_API_TOKEN == "yes" ]]; then
    (
      # shellcheck disable=SC1091
      source "$SCRIPT_DIR/58-configure-api-token.sh"
      create_api_token || exit 1
    ) >/dev/null 2>&1 &
    show_progress $! "Creating API token" "API token created"
  fi

  # Validation & Finalization section
  if type live_log_validation_finalization &>/dev/null 2>&1; then
    live_log_validation_finalization
  fi
  configure_ssh_hardening
  validate_installation
  finalize_vm
}
