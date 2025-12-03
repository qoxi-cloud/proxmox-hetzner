# shellcheck shell=bash
# =============================================================================
# Fail2Ban configuration (when Tailscale is not installed)
# Protects SSH and Proxmox API from brute-force attacks
# =============================================================================

# Installs and configures Fail2Ban for brute-force protection.
# Only installs when Tailscale is not used (Tailscale provides its own security).
# Configures jails for SSH and Proxmox API protection.
# Side effects: Sets FAIL2BAN_INSTALLED global, installs fail2ban package
configure_fail2ban() {
  # Only install Fail2Ban if Tailscale is NOT installed
  # Tailscale provides its own security through authenticated mesh network
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    log "Skipping Fail2Ban (Tailscale provides security)"
    return 0
  fi

  log "Installing Fail2Ban (no Tailscale)"

  # Install Fail2Ban package
  run_remote "Installing Fail2Ban" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -yqq fail2ban
    ' "Fail2Ban installed"

  # Download and deploy configuration templates
  (
    download_template "./templates/fail2ban-jail.local" || exit 1
    download_template "./templates/fail2ban-proxmox.conf" || exit 1

    # Apply template variables
    apply_template_vars "./templates/fail2ban-jail.local" \
      "EMAIL=${EMAIL}" \
      "HOSTNAME=${PVE_HOSTNAME}"

    # Copy configurations to VM
    remote_copy "templates/fail2ban-jail.local" "/etc/fail2ban/jail.local" || exit 1
    remote_copy "templates/fail2ban-proxmox.conf" "/etc/fail2ban/filter.d/proxmox.conf" || exit 1

    # Enable and start Fail2Ban
    remote_exec "systemctl enable fail2ban && systemctl restart fail2ban" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring Fail2Ban" "Fail2Ban configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: Fail2Ban configuration failed"
    print_warning "Fail2Ban configuration failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  FAIL2BAN_INSTALLED="yes"
}
