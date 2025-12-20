# shellcheck shell=bash
# =============================================================================
# Lynis - Security auditing and hardening tool
# Weekly scheduled scans with logging
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for lynis
# Sets up weekly scans via systemd timer with logging
_config_lynis() {
  # Deploy systemd timer for weekly scans
  deploy_systemd_timer "lynis-audit" || return 1

  # Ensure log directory exists
  remote_exec 'mkdir -p /var/log/lynis' || {
    log "ERROR: Failed to configure Lynis"
    return 1
  }
}
