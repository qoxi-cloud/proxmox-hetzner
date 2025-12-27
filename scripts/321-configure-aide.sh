# shellcheck shell=bash
# AIDE (Advanced Intrusion Detection Environment) configuration
# File integrity monitoring for detecting unauthorized changes
# Package installed via batch_install_packages() in 037-parallel-helpers.sh

# Configuration function for AIDE
# Initializes database and sets up daily checks via systemd timer
_config_aide() {
  # Deploy systemd timer for daily checks
  deploy_systemd_timer "aide-check" || return 1

  # Initialize AIDE database and move to active location
  remote_exec '
    aideinit -y -f
    [[ -f /var/lib/aide/aide.db.new ]] && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  ' || {
    log "ERROR: Failed to initialize AIDE"
    return 1
  }

  parallel_mark_configured "aide"
}

# Public wrapper (generated via factory)
make_feature_wrapper "aide" "INSTALL_AIDE"
