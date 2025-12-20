# shellcheck shell=bash
# =============================================================================
# needrestart - Checks which services need restart after library upgrades
# Automatically restarts services when libraries are updated
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for needrestart
# Deploys configuration for automatic restarts
_config_needrestart() {
  remote_copy "templates/needrestart.conf" "/etc/needrestart/conf.d/50-autorestart.conf" || {
    log "ERROR: Failed to deploy needrestart config"
    return 1
  }
}
