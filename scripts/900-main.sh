# shellcheck shell=bash
# Finish and reboot

# Render completion screen with credentials and access info
_render_completion_screen() {
  local output=""
  local banner_output

  # Capture banner output
  banner_output=$(show_banner)

  # Start output with banner
  output+="${banner_output}\n\n"

  # Success header (wizard step continuation style)
  output+="$(format_wizard_header "Installation Complete")\n\n"

  # Warning to save credentials
  output+="  ${CLR_YELLOW}⚠ SAVE THESE CREDENTIALS${CLR_RESET}\n\n"

  # Helper to add field (wizard style)
  _cred_field() {
    local label="$1" value="$2" note="${3:-}"
    if [[ -n $label ]]; then
      output+="  ${CLR_GRAY}${label}${CLR_RESET}${value}"
    else
      output+="                   ${value}"
    fi
    [[ -n $note ]] && output+=" ${CLR_GRAY}${note}${CLR_RESET}"
    output+="\n"
  }

  # System info
  _cred_field "Hostname         " "${CLR_CYAN}${PVE_HOSTNAME}.${DOMAIN_SUFFIX}${CLR_RESET}"
  output+="\n"

  # Admin credentials (SSH + Proxmox UI)
  _cred_field "Admin User       " "${CLR_CYAN}${ADMIN_USERNAME}${CLR_RESET}"
  _cred_field "Admin Password   " "${CLR_ORANGE}${ADMIN_PASSWORD}${CLR_RESET}" "(SSH + Proxmox UI)"
  output+="\n"

  # Root credentials (console/KVM only - SSH blocked)
  _cred_field "Root Password    " "${CLR_ORANGE}${NEW_ROOT_PASSWORD}${CLR_RESET}" "(console/KVM only)"
  output+="\n"

  # Determine access based on firewall mode
  local has_tailscale=""
  [[ -n $TAILSCALE_IP && $TAILSCALE_IP != "pending" && $TAILSCALE_IP != "not authenticated" ]] && has_tailscale="yes"

  case "${FIREWALL_MODE:-standard}" in
    stealth)
      if [[ $has_tailscale == "yes" ]]; then
        _cred_field "SSH              " "${CLR_CYAN}ssh ${ADMIN_USERNAME}@${TAILSCALE_IP}${CLR_RESET}" "(Tailscale)"
        _cred_field "Web UI           " "${CLR_CYAN}https://${TAILSCALE_IP}:8006${CLR_RESET}" "(Tailscale)"
      else
        _cred_field "SSH              " "${CLR_YELLOW}blocked${CLR_RESET}" "(stealth mode)"
        _cred_field "Web UI           " "${CLR_YELLOW}blocked${CLR_RESET}" "(stealth mode)"
      fi
      ;;
    strict)
      _cred_field "SSH              " "${CLR_CYAN}ssh ${ADMIN_USERNAME}@${MAIN_IPV4}${CLR_RESET}"
      if [[ $has_tailscale == "yes" ]]; then
        _cred_field "" "${CLR_CYAN}ssh ${ADMIN_USERNAME}@${TAILSCALE_IP}${CLR_RESET}" "(Tailscale)"
        _cred_field "Web UI           " "${CLR_CYAN}https://${TAILSCALE_IP}:8006${CLR_RESET}" "(Tailscale)"
      else
        _cred_field "Web UI           " "${CLR_YELLOW}blocked${CLR_RESET}" "(strict mode)"
      fi
      ;;
    *)
      _cred_field "SSH              " "${CLR_CYAN}ssh ${ADMIN_USERNAME}@${MAIN_IPV4}${CLR_RESET}"
      [[ $has_tailscale == "yes" ]] && _cred_field "" "${CLR_CYAN}ssh ${ADMIN_USERNAME}@${TAILSCALE_IP}${CLR_RESET}" "(Tailscale)"
      _cred_field "Web UI           " "${CLR_CYAN}https://${MAIN_IPV4}:8006${CLR_RESET}"
      [[ $has_tailscale == "yes" ]] && _cred_field "" "${CLR_CYAN}https://${TAILSCALE_IP}:8006${CLR_RESET}" "(Tailscale)"
      ;;
  esac

  # API Token (if created)
  if [[ -f /tmp/pve-install-api-token.env ]]; then
    # shellcheck disable=SC1091
    source /tmp/pve-install-api-token.env

    if [[ -n $API_TOKEN_VALUE ]]; then
      output+="\n"
      _cred_field "API Token ID     " "${CLR_CYAN}${API_TOKEN_ID}${CLR_RESET}"
      _cred_field "API Secret       " "${CLR_ORANGE}${API_TOKEN_VALUE}${CLR_RESET}"
    fi
  fi

  output+="\n"

  # Centered footer
  local footer_text="${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] reboot  [${CLR_ORANGE}Q${CLR_GRAY}] quit without reboot${CLR_RESET}"
  output+="$(_wiz_center "$footer_text")"

  # Clear and render
  _wiz_clear
  printf '%b' "$output"
}

# Handle completion screen input (Enter=reboot, Q=exit)
_completion_screen_input() {
  while true; do
    _render_completion_screen

    # Read single keypress
    local key
    IFS= read -rsn1 key

    case "$key" in
      q | Q)
        printf '\n'
        print_info "Exiting without reboot."
        printf '\n'
        print_info "You can reboot manually when ready with: ${CLR_CYAN}reboot${CLR_RESET}"
        exit 0
        ;;
      "")
        # Enter pressed - reboot
        printf '\n'
        print_info "Rebooting the system..."
        if ! reboot; then
          log "ERROR: Failed to reboot - system may require manual restart"
          print_error "Failed to reboot the system"
          exit 1
        fi
        ;;
    esac
  done
}

# Finishes live installation display and shows completion screen.
# Prompts user to reboot or exit without reboot.
reboot_to_main_os() {
  # Finish live installation display
  finish_live_installation

  # Show completion screen with wizard style
  _completion_screen_input
}

# Main execution flow

log "=========================================="
log "Qoxi Automated Installer v${VERSION}"
log "=========================================="
log "QEMU_RAM_OVERRIDE=$QEMU_RAM_OVERRIDE"
log "QEMU_CORES_OVERRIDE=$QEMU_CORES_OVERRIDE"
log "PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
log "SSL_TYPE=${SSL_TYPE:-self-signed}"

# Start installation metrics
metrics_start

# Collect system info with animated banner
log "Step: collect_system_info"

# Start animated banner in background
show_banner_animated_start 0.1

# Create temporary file for sharing variables between processes
SYSTEM_INFO_CACHE=$(mktemp)
register_temp_file "$SYSTEM_INFO_CACHE"

# Run system checks and prefetch Proxmox ISO info in background job
# All output suppressed to prevent interference with animation
{
  collect_system_info
  log "Step: prefetch_proxmox_iso_info"
  prefetch_proxmox_iso_info

  # Export all important variables to temp file using atomic write pattern
  # Include: PREFLIGHT_*, DRIVE_*, INTERFACE_*, CURRENT_INTERFACE, PREDICTABLE_NAME,
  # DEFAULT_INTERFACE, AVAILABLE_*, MAC_ADDRESS, MAIN_IPV*, IPV6_*, FIRST_IPV6_*, _ISO_*, _CHECKSUM_*
  # Also: WIZ_TIMEZONES, WIZ_COUNTRIES, TZ_TO_COUNTRY (loaded dynamically from system)
  # Also: DETECTED_POOLS (for existing ZFS pool import feature)
  # Write to temp file first, then atomic mv to prevent truncated/partial data on interruption
  declare -p | grep -E "^declare -[^ ]* (PREFLIGHT_|DRIVE_|INTERFACE_|CURRENT_INTERFACE|PREDICTABLE_NAME|DEFAULT_INTERFACE|AVAILABLE_|MAC_ADDRESS|MAIN_IPV|IPV6_|FIRST_IPV6_|_ISO_|_CHECKSUM_|WIZ_TIMEZONES|WIZ_COUNTRIES|TZ_TO_COUNTRY|DETECTED_POOLS)" >"${SYSTEM_INFO_CACHE}.tmp" \
    && mv "${SYSTEM_INFO_CACHE}.tmp" "$SYSTEM_INFO_CACHE"
} >/dev/null 2>&1 &

# Wait for background tasks to complete
wait $!

# Stop animation and show static banner with system info
show_banner_animated_stop

# Import variables from background job
if [[ -s $SYSTEM_INFO_CACHE ]]; then
  # shellcheck disable=SC1090
  source "$SYSTEM_INFO_CACHE"
  rm -f "$SYSTEM_INFO_CACHE"
fi

log "Step: show_system_status"
show_system_status
log_metric "system_info"

# Show interactive configuration editor (replaces get_system_inputs)
log "Step: show_gum_config_editor"
show_gum_config_editor
log_metric "config_wizard"

# Start live installation display
start_live_installation

log "Step: prepare_packages"
prepare_packages
log_metric "packages"

log "Step: download_proxmox_iso"
download_proxmox_iso
log_metric "iso_download"

log "Step: make_answer_toml"
make_answer_toml
log "Step: make_autoinstall_iso"
make_autoinstall_iso
log_metric "autoinstall_prep"

log "Step: install_proxmox"
install_proxmox
log_metric "proxmox_install"

log "Step: boot_proxmox_with_port_forwarding"
boot_proxmox_with_port_forwarding || {
  log "ERROR: Failed to boot Proxmox with port forwarding"
  exit 1
}
log_metric "qemu_boot"

log "Step: configure_proxmox_via_ssh"
configure_proxmox_via_ssh
log_metric "system_config"

# Log final metrics
metrics_finish

# Mark installation as completed (disables error handler message)
INSTALL_COMPLETED=true

# Reboot to the main OS
log "Step: reboot_to_main_os"
reboot_to_main_os
