# shellcheck shell=bash
# =============================================================================
# AppArmor configuration for Proxmox VE
# Provides mandatory access control (MAC) for LXC containers and system services
# =============================================================================

# Installation function for AppArmor
_install_apparmor() {
  run_remote "Installing AppArmor" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq apparmor apparmor-utils
  ' "AppArmor installed"
}

# Configuration function for AppArmor
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
  ' || exit 1
}

# Installs and configures AppArmor for mandatory access control.
# Enables AppArmor profiles for LXC containers and system services.
# Side effects: Sets APPARMOR_INSTALLED global, installs apparmor packages
configure_apparmor() {
  # Skip if AppArmor installation is not requested
  if [[ ${INSTALL_APPARMOR:-} != "yes" ]]; then
    log "Skipping AppArmor (not requested)"
    return 0
  fi

  log "Installing and configuring AppArmor"

  # Install and configure using helper (with background progress)
  (
    _install_apparmor || exit 1
    _config_apparmor || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing and configuring AppArmor" "AppArmor configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: AppArmor setup failed"
    print_warning "AppArmor setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  APPARMOR_INSTALLED="yes"
}
