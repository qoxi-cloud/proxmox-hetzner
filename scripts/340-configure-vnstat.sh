# shellcheck shell=bash
# =============================================================================
# vnstat - Network traffic monitoring
# Lightweight daemon for monitoring network bandwidth usage
# =============================================================================

# Installation function for vnstat
_install_vnstat() {
  run_remote "Installing vnstat" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq vnstat
  ' "vnstat installed"
}

# Configuration function for vnstat
_config_vnstat() {
  local iface="${INTERFACE_NAME:-eth0}"

  # Deploy vnstat configuration
  deploy_template "vnstat.conf" "/etc/vnstat.conf" \
    "INTERFACE_NAME=${iface}"

  remote_exec "
    # Ensure database directory exists
    mkdir -p /var/lib/vnstat

    # Add main interface to monitor
    vnstat --add -i '${iface}' 2>/dev/null || true

    # Also monitor bridge interfaces if they exist
    for bridge in vmbr0 vmbr1; do
      if ip link show \"\$bridge\" &>/dev/null; then
        vnstat --add -i \"\$bridge\" 2>/dev/null || true
      fi
    done

    # Enable vnstat to start on boot (don't start now - will activate after reboot)
    systemctl enable vnstat
  " || exit 1
}

# Installs and configures vnstat for network traffic monitoring.
# Enables daemon and initializes database for network interfaces.
# Side effects: Sets VNSTAT_INSTALLED global, installs vnstat package
configure_vnstat() {
  # Skip if vnstat installation is not requested
  if [[ $INSTALL_VNSTAT != "yes" ]]; then
    log "Skipping vnstat (not requested)"
    return 0
  fi

  log "Installing and configuring vnstat"

  # Install and configure using helper (with background progress)
  (
    _install_vnstat || exit 1
    _config_vnstat || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing vnstat" "vnstat configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: vnstat setup failed"
    print_warning "vnstat setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  VNSTAT_INSTALLED="yes"
}
