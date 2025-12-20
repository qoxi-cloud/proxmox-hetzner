# shellcheck shell=bash
# =============================================================================
# Netdata - Real-time performance and health monitoring
# Provides web dashboard on PORT_NETDATA (default: 19999)
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for netdata
_config_netdata() {
  # Determine bind address based on Tailscale
  local bind_to="127.0.0.1"
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    bind_to="127.0.0.1 100.*"
  fi

  deploy_template "templates/netdata.conf" "/etc/netdata/netdata.conf" \
    "NETDATA_BIND_TO=${bind_to}" || return 1

  remote_enable_services "netdata"
}

# Configures Netdata for real-time monitoring.
# Package already installed via batch_install_packages().
# Provides web dashboard on PORT_NETDATA (see 000-init.sh).
# If Tailscale enabled: accessible via Tailscale network
# Otherwise: localhost only (use reverse proxy for external access)
configure_netdata() {
  if [[ $INSTALL_NETDATA != "yes" ]]; then
    log "Skipping netdata (not requested)"
    return 0
  fi

  log "Configuring netdata"
  if ! run_with_progress "Configuring netdata" "netdata configured" _config_netdata; then
    log "WARNING: netdata setup failed"
  fi
  return 0 # Non-fatal
}
