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

  deploy_systemd_service "network-ringbuffer" "RINGBUFFER_INTERFACE=${ringbuffer_interface}" || return 1
  parallel_mark_configured "ringbuffer"
}

# =============================================================================
# Public wrapper
# =============================================================================

# Public wrapper for ring buffer configuration
configure_ringbuffer() {
  [[ ${INSTALL_RINGBUFFER:-} != "yes" ]] && return 0
  _config_ringbuffer
}
