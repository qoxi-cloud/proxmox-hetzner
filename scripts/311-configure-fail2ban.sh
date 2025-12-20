# shellcheck shell=bash
# =============================================================================
# Fail2Ban configuration for brute-force protection
# Protects SSH and Proxmox API from brute-force attacks
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for Fail2Ban
# Deploys jail config and Proxmox filter, enables service
_config_fail2ban() {
  deploy_template "templates/fail2ban-jail.local" "/etc/fail2ban/jail.local" \
    "EMAIL=${EMAIL}" "HOSTNAME=${PVE_HOSTNAME}" || return 1

  remote_copy "templates/fail2ban-proxmox.conf" "/etc/fail2ban/filter.d/proxmox.conf" || {
    log "ERROR: Failed to deploy fail2ban filter"
    return 1
  }

  remote_enable_services "fail2ban"
}
