# shellcheck shell=bash
# =============================================================================
# Network Ring Buffer Tuning
# Increases ring buffer size for better throughput and reduced packet drops
# =============================================================================

# Installation function for ring buffer tuning
_install_ringbuffer() {
  run_remote "Installing ethtool" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq ethtool
  ' "ethtool installed"
}

# Configuration function for ring buffer tuning
_config_ringbuffer() {
  # Export interface for template
  export RINGBUFFER_INTERFACE="${DEFAULT_INTERFACE:-eth0}"

  # Deploy systemd service for persistent ring buffer settings
  deploy_template "network-ringbuffer.service" "/etc/systemd/system/network-ringbuffer.service" RINGBUFFER_INTERFACE

  remote_exec '
    # Enable service for boot (will activate after reboot)
    systemctl daemon-reload
    systemctl enable network-ringbuffer.service
  ' || exit 1
}

# Installs and configures network ring buffer tuning.
# Maximizes RX/TX ring buffer size for reduced packet drops.
# Side effects: Sets RINGBUFFER_INSTALLED global, installs ethtool
configure_ringbuffer() {
  # Skip if ring buffer tuning is not requested
  if [[ $INSTALL_RINGBUFFER != "yes" ]]; then
    log "Skipping ring buffer tuning (not requested)"
    return 0
  fi

  log "Installing and configuring ring buffer tuning"

  # Install and configure using helper (with background progress)
  (
    _install_ringbuffer || exit 1
    _config_ringbuffer || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring ring buffer" "Ring buffer configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: ring buffer setup failed"
    print_warning "Ring buffer setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  RINGBUFFER_INSTALLED="yes"
}
