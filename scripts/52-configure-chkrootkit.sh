# shellcheck shell=bash
# =============================================================================
# chkrootkit - Rootkit detection scanner
# Weekly scheduled scans with logging
# =============================================================================

# Configuration function for chkrootkit
_config_chkrootkit() {
  # Deploy systemd service and timer for weekly scans
  deploy_template "chkrootkit-scan.service" "/etc/systemd/system/chkrootkit-scan.service"
  deploy_template "chkrootkit-scan.timer" "/etc/systemd/system/chkrootkit-scan.timer"

  remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/chkrootkit

    # Enable weekly scan timer
    systemctl daemon-reload
    systemctl enable chkrootkit-scan.timer
    systemctl start chkrootkit-scan.timer
  ' || exit 1
}

# Configures chkrootkit for scheduled rootkit scanning.
# Sets up weekly scans via systemd timer with logging.
# Note: chkrootkit package is already installed via SYSTEM_UTILITIES
# Side effects: Sets CHKROOTKIT_INSTALLED global
configure_chkrootkit() {
  # Skip if chkrootkit scheduling is not requested
  if [[ $INSTALL_CHKROOTKIT != "yes" ]]; then
    log "Skipping chkrootkit scheduling (not requested)"
    return 0
  fi

  log "Configuring chkrootkit scheduled scanning"

  # Configure using helper (with background progress)
  (
    _config_chkrootkit || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring chkrootkit" "chkrootkit configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: chkrootkit setup failed"
    print_warning "chkrootkit setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  CHKROOTKIT_INSTALLED="yes"
}
