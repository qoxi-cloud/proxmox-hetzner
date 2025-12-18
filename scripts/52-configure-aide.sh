# shellcheck shell=bash
# =============================================================================
# AIDE (Advanced Intrusion Detection Environment) configuration
# File integrity monitoring for detecting unauthorized changes
# =============================================================================

# Installation function for AIDE
_install_aide() {
  run_remote "Installing AIDE" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq aide aide-common
  ' "AIDE installed"
}

# Configuration function for AIDE
_config_aide() {
  # Deploy systemd service and timer for daily checks
  deploy_template "aide-check.service" "/etc/systemd/system/aide-check.service"
  deploy_template "aide-check.timer" "/etc/systemd/system/aide-check.timer"

  remote_exec '
    # Initialize AIDE database (this takes a while)
    echo "Initializing AIDE database (this may take several minutes)..."
    aideinit -y -f 2>/dev/null || true

    # Move new database to active location
    if [[ -f /var/lib/aide/aide.db.new ]]; then
      mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi

    # Enable daily integrity check timer
    systemctl daemon-reload
    systemctl enable aide-check.timer
    systemctl start aide-check.timer
  ' || exit 1
}

# Installs and configures AIDE for file integrity monitoring.
# Initializes the baseline database and sets up daily checks via systemd timer.
# Side effects: Sets AIDE_INSTALLED global, installs aide package
configure_aide() {
  # Skip if AIDE installation is not requested
  if [[ $INSTALL_AIDE != "yes" ]]; then
    log "Skipping AIDE (not requested)"
    return 0
  fi

  log "Installing and configuring AIDE"

  # Install and configure using helper (with background progress)
  (
    _install_aide || exit 1
    _config_aide || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing and configuring AIDE" "AIDE configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: AIDE setup failed"
    print_warning "AIDE setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  AIDE_INSTALLED="yes"
}
