# shellcheck shell=bash
# =============================================================================
# AIDE (Advanced Intrusion Detection Environment) configuration
# File integrity monitoring for detecting unauthorized changes
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for AIDE
# Initializes database and sets up daily checks via systemd timer
_config_aide() {
  # Deploy systemd service and timer for daily checks
  remote_copy "templates/aide-check.service" "/etc/systemd/system/aide-check.service" || {
    log "ERROR: Failed to deploy AIDE service"
    return 1
  }
  remote_copy "templates/aide-check.timer" "/etc/systemd/system/aide-check.timer" || {
    log "ERROR: Failed to deploy AIDE timer"
    return 1
  }

  remote_exec '
    # Initialize AIDE database (this takes a while)
    echo "Initializing AIDE database (this may take several minutes)..."
    aideinit -y -f 2>/dev/null || true

    # Move new database to active location
    if [[ -f /var/lib/aide/aide.db.new ]]; then
      mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi

    # Enable daily integrity check timer (will activate after reboot)
    systemctl daemon-reload
    systemctl enable aide-check.timer
  ' || {
    log "ERROR: Failed to initialize AIDE"
    return 1
  }
}
