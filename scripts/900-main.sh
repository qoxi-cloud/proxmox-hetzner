# shellcheck shell=bash
# =============================================================================
# Finish and reboot
# =============================================================================

# Prints a credential field with label and value.
# Parameters:
#   $1 - Label (e.g., "Hostname", "Username")
#   $2 - Value
#   $3 - Optional note (shown in gray)
_print_field() {
  local label="$1" value="$2" note="${3:-}"
  printf "${CLR_CYAN}  %-9s${CLR_RESET} %s" "$label:" "$value"
  [[ -n $note ]] && printf " ${CLR_GRAY}%s${CLR_RESET}" "$note"
  printf "\n"
}

# Displays installation completion message and prompts for system reboot.
# Shows success message and interactive reboot dialog.
_show_credentials_info() {
  echo ""
  echo "${CLR_YELLOW}${CLR_BOLD}Access Credentials${CLR_RESET} ${CLR_RED}(SAVE THIS!)${CLR_RESET}"
  echo ""

  # Root credentials (always shown)
  print_section "Root Access:"
  _print_field "Hostname" "${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
  _print_field "Username" "root"
  _print_field "Password" "${NEW_ROOT_PASSWORD}"

  # Determine Web UI access based on firewall mode
  local has_tailscale=""
  [[ -n $TAILSCALE_IP && $TAILSCALE_IP != "pending" && $TAILSCALE_IP != "not authenticated" ]] && has_tailscale="yes"

  case "${FIREWALL_MODE:-standard}" in
    stealth)
      # All public ports blocked - only Tailscale access
      if [[ $has_tailscale == "yes" ]]; then
        _print_field "Web UI" "https://${TAILSCALE_IP}:8006" "(Tailscale only)"
      else
        _print_field "Web UI" "${CLR_YELLOW}blocked${CLR_RESET}" "(stealth mode, no Tailscale)"
      fi
      ;;
    strict)
      # SSH only on public IP, Web UI only via Tailscale
      if [[ $has_tailscale == "yes" ]]; then
        _print_field "Web UI" "https://${TAILSCALE_IP}:8006" "(Tailscale only)"
      else
        _print_field "Web UI" "${CLR_YELLOW}blocked${CLR_RESET}" "(strict mode blocks :8006)"
      fi
      ;;
    *)
      # Standard mode - public IP access, optionally also Tailscale
      _print_field "Web UI" "https://${MAIN_IPV4}:8006"
      if [[ $has_tailscale == "yes" ]]; then
        _print_field "" "https://${TAILSCALE_IP}:8006" "(Tailscale)"
      fi
      ;;
  esac

  # API Token (shown only if created)
  if [[ -f /tmp/pve-install-api-token.env ]]; then
    # shellcheck disable=SC1091
    source /tmp/pve-install-api-token.env

    if [[ -n $API_TOKEN_VALUE ]]; then
      echo ""
      print_section "API Token:"
      _print_field "Token ID" "${API_TOKEN_ID}"
      _print_field "Secret" "${API_TOKEN_VALUE}"
    fi
  fi
  echo ""
}

reboot_to_main_os() {
  # Finish live installation display
  finish_live_installation

  # Clear screen and show banner
  _wiz_start_edit

  # Show success message
  print_info "Installation completed successfully!"

  # Show credentials (root password + API token if created)
  _show_credentials_info

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

# Run system checks and prefetch Proxmox ISO info in background job
# All output suppressed to prevent interference with animation
{
  collect_system_info
  log "Step: prefetch_proxmox_iso_info"
  prefetch_proxmox_iso_info

  # Export all important variables to temp file
  # Include: PREFLIGHT_*, DRIVE_*, INTERFACE_*, CURRENT_INTERFACE, PREDICTABLE_NAME,
  # DEFAULT_INTERFACE, AVAILABLE_*, MAC_ADDRESS, MAIN_IPV*, IPV6_*, FIRST_IPV6_*, _ISO_*, _CHECKSUM_*
  # Also: WIZ_TIMEZONES, WIZ_COUNTRIES, TZ_TO_COUNTRY (loaded dynamically from system)
  declare -p | grep -E "^declare -[^ ]* (PREFLIGHT_|DRIVE_|INTERFACE_|CURRENT_INTERFACE|PREDICTABLE_NAME|DEFAULT_INTERFACE|AVAILABLE_|MAC_ADDRESS|MAIN_IPV|IPV6_|FIRST_IPV6_|_ISO_|_CHECKSUM_|WIZ_TIMEZONES|WIZ_COUNTRIES|TZ_TO_COUNTRY)" >"$SYSTEM_INFO_CACHE"
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
