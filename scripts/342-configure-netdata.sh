# shellcheck shell=bash
# =============================================================================
# Netdata - Real-time performance and health monitoring
# Provides web dashboard on port 19999
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for netdata
_config_netdata() {
  # Determine bind address based on Tailscale
  local bind_to="127.0.0.1"

  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    # Bind to localhost and Tailscale interface (100.x.x.x)
    # Tailscale IP will be detected at runtime
    bind_to="127.0.0.1 100.*"
  fi

  # Apply runtime variable and deploy
  apply_template_vars "templates/netdata.conf" "NETDATA_BIND_TO=${bind_to}"
  remote_copy "templates/netdata.conf" "/etc/netdata/netdata.conf" || {
    log "ERROR: Failed to deploy netdata config"
    return 1
  }

  # Enable netdata to start on boot (don't start now - will activate after reboot)
  remote_exec '
    systemctl daemon-reload
    systemctl enable netdata
  ' || {
    log "ERROR: Failed to enable netdata"
    return 1
  }
}

# Configures Netdata for real-time monitoring.
# Package already installed via batch_install_packages().
# Provides web dashboard accessible on port 19999.
# If Tailscale enabled: accessible via Tailscale network
# Otherwise: localhost only (use reverse proxy for external access)
configure_netdata() {
  # Skip if netdata is not requested
  if [[ $INSTALL_NETDATA != "yes" ]]; then
    log "Skipping netdata (not requested)"
    return 0
  fi

  log "Configuring netdata"

  # Configure using helper (with background progress)
  (
    _config_netdata || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring netdata" "netdata configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: netdata setup failed"
    return 0 # Non-fatal error
  fi
}
