# shellcheck shell=bash
# Configuration phases for Proxmox post-install
# Broken out for maintainability and testability

# PHASE 1: Base Configuration (sequential - dependencies)
# Must run first - sets up admin user and base system
_phase_base_configuration() {
  make_templates || {
    log "ERROR: make_templates failed"
    return 1
  }
  configure_admin_user || {
    log "ERROR: configure_admin_user failed"
    return 1
  }
  configure_base_system || {
    log "ERROR: configure_base_system failed"
    return 1
  }
  configure_shell || { log "WARNING: configure_shell failed"; }
  configure_system_services || { log "WARNING: configure_system_services failed"; }
}

# PHASE 2: Storage Configuration (sequential - ZFS dependencies)
_phase_storage_configuration() {
  configure_zfs_arc || { log "WARNING: configure_zfs_arc failed"; }
  configure_zfs_pool || {
    log "ERROR: configure_zfs_pool failed"
    return 1
  }
  configure_zfs_scrub || { log "WARNING: configure_zfs_scrub failed"; }
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
  deploy_ssh_hardening_config || {
    log "ERROR: deploy_ssh_hardening_config failed"
    return 1
  }

  # Validate installation (SSH config file now has hardened settings)
  # Non-fatal: continue even if validation has warnings
  validate_installation || { log "WARNING: validate_installation reported issues"; }

  # Restart SSH as the LAST operation - after this, password auth is disabled
  restart_ssh_service || { log "WARNING: restart_ssh_service failed"; }

  # Power off VM - SSH no longer available, use QEMU ACPI shutdown
  finalize_vm || { log "WARNING: finalize_vm did not complete cleanly"; }
}
