# shellcheck shell=bash
# =============================================================================
# Promtail - Log collector for Grafana Loki
# Collects system, auth, and Proxmox logs
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for promtail
_config_promtail() {
  # Create config directory
  remote_exec 'mkdir -p /etc/promtail' || return 1

  # Deploy configuration with hostname
  deploy_template "templates/promtail.yml" "/etc/promtail/promtail.yml" \
    "HOSTNAME=${PVE_HOSTNAME}" || return 1

  # Deploy systemd service
  deploy_template "templates/promtail.service" "/etc/systemd/system/promtail.service" || return 1

  # Create positions directory
  remote_exec 'mkdir -p /var/lib/promtail' || return 1

  # Enable and start service
  remote_enable_services "promtail"
}

# Configures Promtail log collector.
# Package already installed via batch_install_packages().
# Collects logs from: /var/log/syslog, auth.log, pve*.log, kernel, journal
# Loki URL must be configured post-installation in /etc/promtail/promtail.yml
configure_promtail() {
  if [[ $INSTALL_PROMTAIL != "yes" ]]; then
    log "Skipping promtail (not requested)"
    return 0
  fi

  log "Configuring promtail"
  if ! run_with_progress "Configuring promtail" "promtail configured" _config_promtail; then
    log "WARNING: promtail setup failed"
  fi
  return 0 # Non-fatal
}
