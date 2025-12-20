# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Main Logic
# =============================================================================

# =============================================================================
# Main wizard loop
# =============================================================================

_wizard_main() {
  local selection=0

  while true; do
    _wiz_render_menu "$selection"
    _wiz_read_key

    case "$WIZ_KEY" in
      up)
        if [[ $selection -gt 0 ]]; then
          ((selection--))
        fi
        ;;
      down)
        if [[ $selection -lt $((_WIZ_FIELD_COUNT - 1)) ]]; then
          ((selection++))
        fi
        ;;
      left)
        # Previous screen
        if [[ $WIZ_CURRENT_SCREEN -gt 0 ]]; then
          ((WIZ_CURRENT_SCREEN--))
          selection=0
        fi
        ;;
      right)
        # Next screen
        if [[ $WIZ_CURRENT_SCREEN -lt $((${#WIZ_SCREENS[@]} - 1)) ]]; then
          ((WIZ_CURRENT_SCREEN++))
          selection=0
        fi
        ;;
      enter)
        # Show cursor for edit screens
        _wiz_show_cursor
        # Edit selected field based on field map
        local field_name="${_WIZ_FIELD_MAP[$selection]}"
        case "$field_name" in
          hostname) _edit_hostname ;;
          email) _edit_email ;;
          password) _edit_password ;;
          timezone) _edit_timezone ;;
          keyboard) _edit_keyboard ;;
          country) _edit_country ;;
          iso_version) _edit_iso_version ;;
          repository) _edit_repository ;;
          interface) _edit_interface ;;
          bridge_mode) _edit_bridge_mode ;;
          private_subnet) _edit_private_subnet ;;
          bridge_mtu) _edit_bridge_mtu ;;
          ipv6) _edit_ipv6 ;;
          firewall) _edit_firewall ;;
          boot_disk) _edit_boot_disk ;;
          pool_disks) _edit_pool_disks ;;
          zfs_mode) _edit_zfs_mode ;;
          zfs_arc) _edit_zfs_arc ;;
          tailscale) _edit_tailscale ;;
          ssl) _edit_ssl ;;
          shell) _edit_shell ;;
          power_profile) _edit_power_profile ;;
          security) _edit_features_security ;;
          monitoring) _edit_features_monitoring ;;
          tools) _edit_features_tools ;;
          api_token) _edit_api_token ;;
          ssh_key) _edit_ssh_key ;;
        esac
        # Hide cursor again
        _wiz_hide_cursor
        ;;
      start)
        # Exit wizard loop to proceed with validation and installation
        return 0
        ;;
      quit | esc)
        # Clear screen and show confirmation with banner
        _wiz_start_edit
        _wiz_show_cursor
        if _wiz_confirm "Quit installation?" --default=false; then
          # Clean exit: restore screen, clear it, show cursor
          tput rmcup 2>/dev/null || true
          clear
          tput cnorm 2>/dev/null || true
          exit 0
        fi
        # Hide cursor and continue (menu will be redrawn on next iteration)
        _wiz_hide_cursor
        ;;
    esac
  done
}

# =============================================================================
# Edit screen helpers
# =============================================================================

# Display footer with key hints below current cursor position
# Parameters:
#   $1 - type: "input" (default), "filter", or "checkbox"
#   $2 - lines for component (default: 1 for input, used for filter/checkbox height)
_show_input_footer() {
  local type="${1:-input}"
  local component_lines="${2:-1}"

  # Print empty lines for component space
  local i
  for ((i = 0; i < component_lines; i++)); do
    _wiz_blank_line
  done

  # Blank line + footer
  _wiz_blank_line
  case "$type" in
    filter)
      echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
    checkbox)
      echo -e "${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Space${CLR_GRAY}] toggle  [${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
    *)
      echo -e "${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
  esac

  # Move cursor back up: component_lines + 1 blank + 1 footer
  tput cuu $((component_lines + 2))
}

# =============================================================================
# Configuration validation
# =============================================================================

# Validates configuration and shows UI with missing fields
# Returns: 0 if valid, 1 if missing required fields
_validate_config() {
  # Quick check first
  _wiz_config_complete && return 0

  # Collect missing fields for display
  local missing_fields=()
  [[ -z $PVE_HOSTNAME ]] && missing_fields+=("Hostname")
  [[ -z $DOMAIN_SUFFIX ]] && missing_fields+=("Domain")
  [[ -z $EMAIL ]] && missing_fields+=("Email")
  [[ -z $NEW_ROOT_PASSWORD ]] && missing_fields+=("Password")
  [[ -z $TIMEZONE ]] && missing_fields+=("Timezone")
  [[ -z $KEYBOARD ]] && missing_fields+=("Keyboard")
  [[ -z $COUNTRY ]] && missing_fields+=("Country")
  [[ -z $PROXMOX_ISO_VERSION ]] && missing_fields+=("Proxmox Version")
  [[ -z $PVE_REPO_TYPE ]] && missing_fields+=("Repository")
  [[ -z $INTERFACE_NAME ]] && missing_fields+=("Network Interface")
  [[ -z $BRIDGE_MODE ]] && missing_fields+=("Bridge mode")
  [[ $BRIDGE_MODE != "external" && -z $PRIVATE_SUBNET ]] && missing_fields+=("Private subnet")
  [[ -z $IPV6_MODE ]] && missing_fields+=("IPv6")
  [[ -z $ZFS_RAID ]] && missing_fields+=("ZFS mode")
  [[ -z $ZFS_ARC_MODE ]] && missing_fields+=("ZFS ARC")
  [[ -z $SHELL_TYPE ]] && missing_fields+=("Shell")
  [[ -z $CPU_GOVERNOR ]] && missing_fields+=("Power profile")
  [[ -z $SSH_PUBLIC_KEY ]] && missing_fields+=("SSH Key")
  [[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]] && missing_fields+=("Pool disks")
  [[ $INSTALL_TAILSCALE != "yes" && -z $SSL_TYPE ]] && missing_fields+=("SSL Certificate")
  [[ $FIREWALL_MODE == "stealth" && $INSTALL_TAILSCALE != "yes" ]] && missing_fields+=("Tailscale (required for Stealth firewall)")

  # Show error with missing fields
  if [[ ${#missing_fields[@]} -gt 0 ]]; then
    _wiz_start_edit
    _wiz_hide_cursor
    _wiz_error --bold "Configuration incomplete!"
    _wiz_blank_line
    _wiz_warn "Please configure the following required fields:"
    _wiz_blank_line
    for field in "${missing_fields[@]}"; do
      echo "  ${CLR_CYAN}•${CLR_RESET} $field"
    done
    _wiz_blank_line
    _wiz_show_cursor
    _wiz_confirm "Return to configuration?" --default=true || exit 1
    _wiz_hide_cursor
    return 1
  fi

  return 0
}

# =============================================================================
# Main wizard entry point
# =============================================================================

show_gum_config_editor() {
  # Enter alternate screen buffer and hide cursor (like vim/less)
  tput smcup # alternate screen
  _wiz_hide_cursor
  trap '_wiz_show_cursor; tput rmcup' EXIT

  # Run wizard loop until configuration is complete
  while true; do
    _wizard_main

    # Validate configuration before proceeding
    if _validate_config; then
      break
    fi
  done
}
