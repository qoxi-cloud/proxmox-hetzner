# shellcheck shell=bash
# =============================================================================
# AppArmor configuration for Proxmox VE
# Provides mandatory access control (MAC) for LXC containers and system services
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for AppArmor
# Configures GRUB for kernel parameters and enables service
_config_apparmor() {
  # Copy GRUB config for kernel parameters (if not already enabled)
  remote_exec '
    if ! grep -q "Y" /sys/module/apparmor/parameters/enabled 2>/dev/null; then
      if ! grep -q "apparmor=1" /etc/default/grub 2>/dev/null; then
        mkdir -p /etc/default/grub.d
      fi
    fi
  '

  # Only copy grub config if AppArmor not enabled in kernel
  remote_exec 'grep -q "Y" /sys/module/apparmor/parameters/enabled 2>/dev/null' \
    || remote_copy "templates/apparmor-grub.cfg" "/etc/default/grub.d/apparmor.cfg"

  # Configure AppArmor
  # shellcheck disable=SC2016 # Single quotes intentional - executed on remote system
  remote_exec '
    # Update GRUB if config was added
    if [[ -f /etc/default/grub.d/apparmor.cfg ]]; then
      update-grub 2>/dev/null || true
    fi

    # Enable AppArmor to start on boot (will activate after reboot)
    systemctl enable apparmor.service
  ' || {
    log "ERROR: Failed to configure AppArmor"
    return 1
  }
}
