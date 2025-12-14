# shellcheck shell=bash
# =============================================================================
# Finish and reboot
# =============================================================================

# Displays installation completion message and prompts for system reboot.
# Shows success message and interactive reboot dialog.
reboot_to_main_os() {
  # Finish live installation display
  finish_live_installation

  # Clear screen and show banner
  clear
  show_banner

  echo ""

  # Show success message
  print_info "Installation completed successfully!"
  echo ""

  # Ask user to reboot using gum confirm
  if gum confirm "Reboot the system now?" \
    --affirmative "Yes" \
    --negative "No" \
    --default=true \
    --prompt.foreground "#ff8700" \
    --selected.background "#ff8700" \
    --unselected.foreground "#585858"; then
    print_info "Rebooting the system..."
    if ! reboot; then
      log "ERROR: Failed to reboot - system may require manual restart"
      print_error "Failed to reboot the system"
      exit 1
    fi
  else
    print_info "Exiting without reboot."
    echo ""
    print_info "You can reboot manually when ready with: ${CLR_CYAN}reboot${CLR_RESET}"
    exit 0
  fi
}

# =============================================================================
# Main execution flow
# =============================================================================

log "=========================================="
log "Proxmox VE Automated Installer v${VERSION}"
log "=========================================="
log "QEMU_RAM_OVERRIDE=$QEMU_RAM_OVERRIDE"
log "QEMU_CORES_OVERRIDE=$QEMU_CORES_OVERRIDE"
log "PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
log "SSL_TYPE=${SSL_TYPE:-self-signed}"

# Collect system info with animated banner
log "Step: collect_system_info"

# Start animated banner in background
show_banner_animated_start 0.1

# Run system checks and prefetch Proxmox ISO info in parallel
collect_system_info
log "Step: prefetch_proxmox_iso_info"
prefetch_proxmox_iso_info

# Stop animation and show static banner with system info
show_banner_animated_stop

log "Step: show_system_status"
show_system_status

# Show interactive configuration editor (replaces get_system_inputs)
log "Step: show_gum_config_editor"
show_gum_config_editor

# Start live installation display
start_live_installation || {
  log "WARNING: Failed to start live installation display, falling back to regular mode"
  # Fallback to regular mode
  clear
  show_banner
}

# ============================================================================
# Rescue System Preparation
# ============================================================================
live_log_system_preparation

log "Step: prepare_packages"
prepare_packages

# ============================================================================
# Proxmox ISO Download
# ============================================================================
live_log_iso_download

log "Step: download_proxmox_iso"
download_proxmox_iso
log "Step: make_answer_toml"
make_answer_toml
log "Step: make_autoinstall_iso"
make_autoinstall_iso

# ============================================================================
# Proxmox Installation
# ============================================================================
live_log_proxmox_installation

log "Step: install_proxmox"
install_proxmox

log "Step: boot_proxmox_with_port_forwarding"
boot_proxmox_with_port_forwarding || {
  log "ERROR: Failed to boot Proxmox with port forwarding"
  exit 1
}

# ============================================================================
# System Configuration
# ============================================================================
live_log_system_configuration

log "Step: configure_proxmox_via_ssh"
configure_proxmox_via_ssh

# ============================================================================
# Installation Complete
# ============================================================================
live_log_installation_complete

# Finish live installation display
finish_live_installation

# Mark installation as completed (disables error handler message)
INSTALL_COMPLETED=true

# Reboot to the main OS
log "Step: reboot_to_main_os"
reboot_to_main_os
