# shellcheck shell=bash
# =============================================================================
# Prometheus Node Exporter configuration
# Exposes system and hardware metrics on port 9100 for Prometheus scraping
# =============================================================================

# Installation function for prometheus-node-exporter
_install_prometheus() {
  run_remote "Installing prometheus-node-exporter" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq prometheus-node-exporter
  ' "Prometheus node exporter installed"
}

# Configuration function for prometheus-node-exporter
_config_prometheus() {
  # Create textfile collector directory for custom metrics
  remote_exec '
    mkdir -p /var/lib/prometheus/node-exporter
    chown prometheus:prometheus /var/lib/prometheus/node-exporter
  ' || exit 1

  # Deploy configuration template
  remote_copy "templates/prometheus-node-exporter" "/etc/default/prometheus-node-exporter" || exit 1

  # Deploy custom metrics collector script
  remote_copy "templates/proxmox-metrics.sh" "/usr/local/bin/proxmox-metrics.sh" || exit 1
  remote_exec "chmod +x /usr/local/bin/proxmox-metrics.sh" || exit 1

  # Deploy cron job for custom metrics (runs every 5 minutes)
  remote_copy "templates/proxmox-metrics.cron" "/etc/cron.d/proxmox-metrics" || exit 1

  # Run metrics collector once to populate initial data
  remote_exec "/usr/local/bin/proxmox-metrics.sh" >/dev/null 2>&1 || log "WARNING: Initial metrics collection failed (non-fatal)"

  # Enable prometheus to start on boot (don't start now - will activate after reboot)
  remote_exec '
    systemctl daemon-reload
    systemctl enable prometheus-node-exporter
  ' || exit 1

  log "Prometheus node exporter listening on :9100 with textfile collector"
  log "Custom metrics cron job installed (/etc/cron.d/proxmox-metrics, runs every 5 minutes)"
}

# Installs and configures Prometheus node exporter for metrics collection.
# Exposes system metrics on port 9100 for Prometheus scraping.
# Metrics include: CPU, memory, disk, network, filesystem stats.
# Textfile collector enabled at /var/lib/prometheus/node-exporter for custom metrics.
# Side effects: Sets PROMETHEUS_INSTALLED global, installs prometheus-node-exporter package
configure_prometheus() {
  # Skip if prometheus installation is not requested
  if [[ $INSTALL_PROMETHEUS != "yes" ]]; then
    log "Skipping prometheus-node-exporter (not requested)"
    return 0
  fi

  log "Installing and configuring prometheus-node-exporter"

  # Install and configure using helper (with background progress)
  (
    _install_prometheus || exit 1
    _config_prometheus || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing and configuring prometheus" "Prometheus configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: Prometheus setup failed"
    print_warning "Prometheus setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  PROMETHEUS_INSTALLED="yes"

  # Security notice based on Tailscale configuration
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    log "Prometheus metrics accessible via Tailscale only (stealth firewall enabled)"
  else
    log "WARNING: Prometheus metrics exposed on public IP ${MAIN_IPV4}:9100"
    log "Consider using firewall rules to restrict access to trusted IPs only"
  fi

  log "Textfile collector directory: /var/lib/prometheus/node-exporter"
}
