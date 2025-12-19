# shellcheck shell=bash
# =============================================================================
# chkrootkit - Rootkit detection scanner
# Weekly scheduled scans with logging
# =============================================================================

# Installation function for chkrootkit
_install_chkrootkit() {
  run_remote "Installing chkrootkit" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq chkrootkit
  ' "chkrootkit installed"
}

# Configuration function for chkrootkit
_config_chkrootkit() {
  # Deploy systemd service and timer for weekly scans
  deploy_template "chkrootkit-scan.service" "/etc/systemd/system/chkrootkit-scan.service"
  deploy_template "chkrootkit-scan.timer" "/etc/systemd/system/chkrootkit-scan.timer"

  remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/chkrootkit

    # Enable weekly scan timer (will activate after reboot)
    systemctl daemon-reload
    systemctl enable chkrootkit-scan.timer
  ' || exit 1
}

# Installs and configures chkrootkit for scheduled rootkit scanning.
# Sets up weekly scans via systemd timer with logging.
# Side effects: Sets CHKROOTKIT_INSTALLED global, installs chkrootkit package
configure_chkrootkit() {
  # Skip if chkrootkit is not requested
  if [[ $INSTALL_CHKROOTKIT != "yes" ]]; then
    log "Skipping chkrootkit (not requested)"
    return 0
  fi

  log "Installing and configuring chkrootkit"

  # Install and configure using helper (with background progress)
  (
    _install_chkrootkit || exit 1
    _config_chkrootkit || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing chkrootkit" "chkrootkit configured"

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
