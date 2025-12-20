# shellcheck shell=bash
# =============================================================================
# vnstat - Network traffic monitoring
# Lightweight daemon for monitoring network bandwidth usage
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for vnstat
# Deploys config and initializes database for network interfaces
_config_vnstat() {
  local iface="${INTERFACE_NAME:-eth0}"

  # Apply runtime variable and deploy
  apply_template_vars "templates/vnstat.conf" "INTERFACE_NAME=${iface}"
  remote_copy "templates/vnstat.conf" "/etc/vnstat.conf" || {
    log "ERROR: Failed to deploy vnstat config"
    return 1
  }

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
  " || {
    log "ERROR: Failed to configure vnstat"
    return 1
  }
}
