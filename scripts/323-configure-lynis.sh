# shellcheck shell=bash
# =============================================================================
# Lynis - Security auditing and hardening tool
# Weekly scheduled scans with logging
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for lynis
# Sets up weekly scans via systemd timer with logging
_config_lynis() {
  # Deploy systemd service and timer for weekly scans
  remote_copy "templates/lynis-audit.service" "/etc/systemd/system/lynis-audit.service" || {
    log "ERROR: Failed to deploy Lynis service"
    return 1
  }
  remote_copy "templates/lynis-audit.timer" "/etc/systemd/system/lynis-audit.timer" || {
    log "ERROR: Failed to deploy Lynis timer"
    return 1
  }

  remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/lynis

    # Enable weekly audit timer (will activate after reboot)
    systemctl daemon-reload
    systemctl enable lynis-audit.timer
  ' || {
    log "ERROR: Failed to configure Lynis"
    return 1
  }
}
