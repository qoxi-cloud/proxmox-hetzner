# shellcheck shell=bash
# =============================================================================
# Netdata - Real-time performance and health monitoring
# Provides web dashboard on port 19999
# =============================================================================

# Installation function for netdata
_install_netdata() {
  run_remote "Installing netdata" '
    export DEBIAN_FRONTEND=noninteractive

    # Add Netdata official repository (package not in default Debian repos)
    curl -fsSL https://repo.netdata.cloud/netdatabot.gpg.key | gpg --dearmor -o /usr/share/keyrings/netdata-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/netdata-archive-keyring.gpg] https://repo.netdata.cloud/repos/stable/debian/ bookworm/" > /etc/apt/sources.list.d/netdata.list

    apt-get update -qq
    apt-get install -yqq netdata
  ' "netdata installed"
}

# Configuration function for netdata
_config_netdata() {
  # Determine bind address based on Tailscale
  local bind_to="127.0.0.1"

  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    # Bind to localhost and Tailscale interface (100.x.x.x)
    # Tailscale IP will be detected at runtime
    bind_to="127.0.0.1 100.*"
  fi

  # Export for template
  export NETDATA_BIND_TO="$bind_to"

  # Deploy netdata configuration
  deploy_template "netdata.conf" "/etc/netdata/netdata.conf" NETDATA_BIND_TO

  # Enable netdata to start on boot (don't start now - will activate after reboot)
  remote_exec '
    systemctl daemon-reload
    systemctl enable netdata
  ' || exit 1
}

# Installs and configures Netdata for real-time monitoring.
# Provides web dashboard accessible on port 19999.
# If Tailscale enabled: accessible via Tailscale network
# Otherwise: localhost only (use reverse proxy for external access)
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
