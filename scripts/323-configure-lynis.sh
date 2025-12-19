# shellcheck shell=bash
# =============================================================================
# Lynis - Security auditing and hardening tool
# Weekly scheduled scans with logging
# =============================================================================

# Installation function for lynis
_install_lynis() {
  run_remote "Installing lynis" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq lynis
  ' "lynis installed"
}

# Configuration function for lynis
_config_lynis() {
  # Deploy systemd service and timer for weekly scans
  deploy_template "lynis-audit.service" "/etc/systemd/system/lynis-audit.service"
  deploy_template "lynis-audit.timer" "/etc/systemd/system/lynis-audit.timer"

  remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/lynis

    # Enable weekly audit timer (will activate after reboot)
    systemctl daemon-reload
    systemctl enable lynis-audit.timer
  ' || exit 1
}

# Installs and configures Lynis for scheduled security audits.
# Sets up weekly scans via systemd timer with logging.
# Side effects: Sets LYNIS_INSTALLED global, installs lynis package
configure_lynis() {
  # Skip if lynis is not requested
  if [[ $INSTALL_LYNIS != "yes" ]]; then
    log "Skipping lynis (not requested)"
    return 0
  fi

  log "Installing and configuring lynis"

  # Install and configure using helper (with background progress)
  (
    _install_lynis || exit 1
    _config_lynis || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing lynis" "lynis configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: lynis setup failed"
    print_warning "lynis setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  LYNIS_INSTALLED="yes"
}
