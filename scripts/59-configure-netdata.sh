# shellcheck shell=bash
# =============================================================================
# Netdata - Real-time performance and health monitoring
# Provides web dashboard on port 19999
# =============================================================================

# Installation function for netdata
_install_netdata() {
  run_remote "Installing netdata" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq netdata
  ' "netdata installed"
}

# Configuration function for netdata
_config_netdata() {
  # Deploy netdata configuration
  deploy_template "netdata.conf" "/etc/netdata/netdata.conf"

  remote_exec '
    # Enable and start netdata service
    systemctl daemon-reload
    systemctl enable netdata
    systemctl restart netdata
  ' || exit 1
}

# Installs and configures Netdata for real-time monitoring.
# Provides web dashboard accessible on port 19999.
# Side effects: Sets NETDATA_INSTALLED global, installs netdata package
configure_netdata() {
  # Skip if netdata is not requested
  if [[ $INSTALL_NETDATA != "yes" ]]; then
    log "Skipping netdata (not requested)"
    return 0
  fi

  log "Installing and configuring netdata"

  # Install and configure using helper (with background progress)
  (
    _install_netdata || exit 1
    _config_netdata || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing netdata" "netdata configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: netdata setup failed"
    print_warning "netdata setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  NETDATA_INSTALLED="yes"
}
