# shellcheck shell=bash
# =============================================================================
# Fail2Ban configuration for brute-force protection
# Protects SSH and Proxmox API from brute-force attacks
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for Fail2Ban
# Deploys jail config and Proxmox filter, enables service
_config_fail2ban() {
  # Apply template variables
  apply_template_vars "./templates/fail2ban-jail.local" \
    "EMAIL=${EMAIL}" \
    "HOSTNAME=${PVE_HOSTNAME}"

  # Copy configurations to VM
  remote_copy "templates/fail2ban-jail.local" "/etc/fail2ban/jail.local" || {
    log "ERROR: Failed to deploy fail2ban jail config"
    return 1
  }
  remote_copy "templates/fail2ban-proxmox.conf" "/etc/fail2ban/filter.d/proxmox.conf" || {
    log "ERROR: Failed to deploy fail2ban filter"
    return 1
  }

  # Enable fail2ban to start on boot (don't start now - will activate after reboot)
  remote_exec "systemctl enable fail2ban" || {
    log "ERROR: Failed to enable fail2ban"
    return 1
  }
}
