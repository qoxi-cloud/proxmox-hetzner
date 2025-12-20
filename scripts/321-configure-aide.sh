# shellcheck shell=bash
# =============================================================================
# AIDE (Advanced Intrusion Detection Environment) configuration
# File integrity monitoring for detecting unauthorized changes
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for AIDE
# Initializes database and sets up daily checks via systemd timer
_config_aide() {
  # Deploy systemd timer for daily checks
  deploy_systemd_timer "aide-check" || return 1

  # Initialize AIDE database
  remote_exec '
    echo "Initializing AIDE database (this may take several minutes)..."
    aideinit -y -f 2>/dev/null || true

    # Move new database to active location
    if [[ -f /var/lib/aide/aide.db.new ]]; then
      mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi
  ' || {
    log "ERROR: Failed to initialize AIDE"
    return 1
  }
}
