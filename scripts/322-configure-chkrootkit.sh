# shellcheck shell=bash
# =============================================================================
# chkrootkit - Rootkit detection scanner
# Weekly scheduled scans with logging
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for chkrootkit
# Sets up weekly scans via systemd timer with logging
_config_chkrootkit() {
  # Deploy systemd service and timer for weekly scans
  remote_copy "templates/chkrootkit-scan.service" "/etc/systemd/system/chkrootkit-scan.service" || {
    log "ERROR: Failed to deploy chkrootkit service"
    return 1
  }
  remote_copy "templates/chkrootkit-scan.timer" "/etc/systemd/system/chkrootkit-scan.timer" || {
    log "ERROR: Failed to deploy chkrootkit timer"
    return 1
  }

  remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/chkrootkit

    # Enable weekly scan timer (will activate after reboot)
    systemctl daemon-reload
    systemctl enable chkrootkit-scan.timer
  ' || {
    log "ERROR: Failed to configure chkrootkit"
    return 1
  }
}
