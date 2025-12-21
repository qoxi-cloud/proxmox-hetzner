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

  deploy_template "templates/vnstat.conf" "/etc/vnstat.conf" "INTERFACE_NAME=${iface}" || return 1

  # Add main interface and bridge interfaces to vnstat monitoring
  remote_exec "
    mkdir -p /var/lib/vnstat
    vnstat --add -i '${iface}'
    for bridge in vmbr0 vmbr1; do
      ip link show \"\$bridge\" &>/dev/null && vnstat --add -i \"\$bridge\"
    done
    systemctl enable vnstat
  " || {
    log "ERROR: Failed to configure vnstat"
    return 1
  }
}
