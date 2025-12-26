# shellcheck shell=bash
# Configuration phases for Proxmox post-install
# Broken out for maintainability and testability

# PHASE 1: Base Configuration (sequential - dependencies)
# Must run first - sets up admin user and base system
_phase_base_configuration() {
  make_templates
  configure_admin_user # Must be first - other configs need admin user's home dir
  configure_base_system
  configure_shell
  configure_system_services
}

# PHASE 2: Storage Configuration (sequential - ZFS dependencies)
_phase_storage_configuration() {
  configure_zfs_arc
  configure_zfs_pool
  configure_zfs_scrub
}

# PHASE 3: Security Configuration (parallel after batch install)
_phase_security_configuration() {
  # Batch install security & optional packages first
  batch_install_packages

  # Tailscale (needs package installed, needed for firewall rules)
  configure_tailscale

  # Firewall next (depends on tailscale for rule generation)
  configure_firewall

  # Parallel security configuration - failures are fatal
  if ! run_parallel_group "Configuring security" "Security features configured" \
    configure_apparmor \
    configure_fail2ban \
    configure_auditd \
    configure_aide \
    configure_chkrootkit \
    configure_lynis \
    configure_needrestart; then
    log "ERROR: Security configuration failed - aborting installation"
    print_error "Security hardening failed. Check $LOG_FILE for details."
    return 1
  fi
}

# PHASE 4: Monitoring & Tools (parallel where possible)
_phase_monitoring_tools() {
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
}

# PHASE 5: SSL & API Configuration
_phase_ssl_api() {
  configure_ssl_certificate
  if [[ $INSTALL_API_TOKEN == "yes" ]]; then
    run_with_progress "Creating API token" "API token created" create_api_token
  fi
}

# PHASE 6: Validation & Finalization
_phase_finalization() {
  # Deploy SSH hardening config BEFORE validation (so validation can verify it)
  deploy_ssh_hardening_config

  # Validate installation (SSH config file now has hardened settings)
  validate_installation

  # Restart SSH as the LAST operation - after this, password auth is disabled
  restart_ssh_service

  # Power off VM - SSH no longer available, use QEMU ACPI shutdown
  finalize_vm
}
