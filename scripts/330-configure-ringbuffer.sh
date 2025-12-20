# shellcheck shell=bash
# =============================================================================
# Network Ring Buffer Tuning
# Increases ring buffer size for better throughput and reduced packet drops
# Package (ethtool) installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for ring buffer tuning
# Deploys systemd service to maximize RX/TX ring buffer size
_config_ringbuffer() {
  local ringbuffer_interface="${DEFAULT_INTERFACE:-eth0}"

  # Apply runtime variable and deploy
  apply_template_vars "templates/network-ringbuffer.service" "RINGBUFFER_INTERFACE=${ringbuffer_interface}"
  remote_copy "templates/network-ringbuffer.service" "/etc/systemd/system/network-ringbuffer.service" || {
    log "ERROR: Failed to deploy ringbuffer service"
    return 1
  }

  remote_exec '
    # Enable service for boot (will activate after reboot)
    systemctl daemon-reload
    systemctl enable network-ringbuffer.service
  ' || {
    log "ERROR: Failed to configure ringbuffer service"
    return 1
  }
}
