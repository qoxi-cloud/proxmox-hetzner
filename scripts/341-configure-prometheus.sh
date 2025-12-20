# shellcheck shell=bash
# =============================================================================
# Prometheus Node Exporter configuration
# Exposes system and hardware metrics on port 9100 for Prometheus scraping
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for prometheus-node-exporter
# Sets up textfile collector and custom Proxmox metrics
_config_prometheus() {
  # Create textfile collector directory for custom metrics
  remote_exec '
    mkdir -p /var/lib/prometheus/node-exporter
    chown prometheus:prometheus /var/lib/prometheus/node-exporter
  ' || {
    log "ERROR: Failed to create Prometheus collector directory"
    return 1
  }

  # Deploy configuration template
  remote_copy "templates/prometheus-node-exporter" "/etc/default/prometheus-node-exporter" || {
    log "ERROR: Failed to deploy Prometheus config"
    return 1
  }

  # Deploy custom metrics collector script
  remote_copy "templates/proxmox-metrics.sh" "/usr/local/bin/proxmox-metrics.sh" || {
    log "ERROR: Failed to deploy Proxmox metrics script"
    return 1
  }
  remote_exec "chmod +x /usr/local/bin/proxmox-metrics.sh" || {
    log "ERROR: Failed to set metrics script permissions"
    return 1
  }

  # Deploy cron job for custom metrics (runs every 5 minutes)
  remote_copy "templates/proxmox-metrics.cron" "/etc/cron.d/proxmox-metrics" || {
    log "ERROR: Failed to deploy Prometheus cron job"
    return 1
  }

  # Run metrics collector once to populate initial data
  remote_exec "/usr/local/bin/proxmox-metrics.sh" >/dev/null 2>&1 || log "WARNING: Initial metrics collection failed (non-fatal)"

  # Enable prometheus to start on boot (don't start now - will activate after reboot)
  remote_exec '
    systemctl daemon-reload
    systemctl enable prometheus-node-exporter
  ' || {
    log "ERROR: Failed to enable Prometheus node exporter"
    return 1
  }

  log "Prometheus node exporter listening on :9100 with textfile collector"
}
