# shellcheck shell=bash
# Configuration Wizard - Main Logic

# Main wizard loop

# Main wizard loop. Returns 0 when 'S' pressed to start installation.
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
          wipe_disks) _edit_wipe_disks ;;
          existing_pool) _edit_existing_pool ;;
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
          admin_username) _edit_admin_username ;;
          admin_password) _edit_admin_password ;;
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

# Edit screen helpers

# Show footer with key hints. $1=type (input/filter/checkbox), $2=lines
_show_input_footer() {
  local type="${1:-input}"
  local component_lines="${2:-1}"

  # Print empty lines for component space
  local i
  for ((i = 0; i < component_lines; i++)); do
    _wiz_blank_line
  done

  # Blank line + centered footer
  _wiz_blank_line
  local footer_text
  case "$type" in
    filter)
      footer_text="${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] select  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
    checkbox)
      footer_text="${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Space${CLR_GRAY}] toggle  [${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
    *)
      footer_text="${CLR_GRAY}[${CLR_ORANGE}Enter${CLR_GRAY}] confirm  [${CLR_ORANGE}Esc${CLR_GRAY}] cancel${CLR_RESET}"
      ;;
  esac
  printf '%s\n' "$(_wiz_center "$footer_text")"

  # Move cursor back up: component_lines + 1 blank + 1 footer
  tput cuu $((component_lines + 2))
}

# Configuration validation

# Validate config, show missing fields. Returns 0=valid, 1=missing
_validate_config() {
  # Quick check first
  _wiz_config_complete && return 0

  # Collect missing fields for display
  local missing_fields=()
  [[ -z $PVE_HOSTNAME ]] && missing_fields+=("Hostname")
  [[ -z $DOMAIN_SUFFIX ]] && missing_fields+=("Domain")
  [[ -z $EMAIL ]] && missing_fields+=("Email")
  [[ -z $NEW_ROOT_PASSWORD ]] && missing_fields+=("Password")
  [[ -z $ADMIN_USERNAME ]] && missing_fields+=("Admin Username")
  [[ -z $ADMIN_PASSWORD ]] && missing_fields+=("Admin Password")
  [[ -z $TIMEZONE ]] && missing_fields+=("Timezone")
  [[ -z $KEYBOARD ]] && missing_fields+=("Keyboard")
  [[ -z $COUNTRY ]] && missing_fields+=("Country")
  [[ -z $PROXMOX_ISO_VERSION ]] && missing_fields+=("Proxmox Version")
  [[ -z $PVE_REPO_TYPE ]] && missing_fields+=("Repository")
  [[ -z $INTERFACE_NAME ]] && missing_fields+=("Network Interface")
  [[ -z $BRIDGE_MODE ]] && missing_fields+=("Bridge mode")
  [[ $BRIDGE_MODE != "external" && -z $PRIVATE_SUBNET ]] && missing_fields+=("Private subnet")
  [[ -z $IPV6_MODE ]] && missing_fields+=("IPv6")
  # ZFS validation: require raid/disks only when NOT using existing pool
  if [[ $USE_EXISTING_POOL == "yes" ]]; then
    [[ -z $EXISTING_POOL_NAME ]] && missing_fields+=("Existing pool name")
  else
    [[ -z $ZFS_RAID ]] && missing_fields+=("ZFS mode")
    [[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]] && missing_fields+=("Pool disks")
  fi
  [[ -z $ZFS_ARC_MODE ]] && missing_fields+=("ZFS ARC")
  [[ -z $SHELL_TYPE ]] && missing_fields+=("Shell")
  [[ -z $CPU_GOVERNOR ]] && missing_fields+=("Power profile")
  [[ -z $SSH_PUBLIC_KEY ]] && missing_fields+=("SSH Key")
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
      printf '%s\n' "  ${CLR_CYAN}•${CLR_RESET} $field"
    done
    _wiz_blank_line
    _wiz_show_cursor
    _wiz_confirm "Return to configuration?" --default=true || exit 1
    _wiz_hide_cursor
    return 1
  fi

  return 0
}

# Main wizard entry point

# Main entry point for the configuration wizard.
# Runs in alternate screen buffer with hidden cursor.
# Loops until all required configuration is complete.
show_gum_config_editor() {
  # Enter alternate screen buffer and hide cursor (like vim/less)
  tput smcup # alternate screen
  _wiz_hide_cursor
  # Chain with existing cleanup handler - restore terminal THEN run global cleanup
  # shellcheck disable=SC2064
  trap "_wiz_show_cursor; tput rmcup 2>/dev/null; cleanup_and_error_handler" EXIT

  # Run wizard loop until configuration is complete
  while true; do
    _wizard_main

    # Validate configuration before proceeding
    if _validate_config; then
      break
    fi
  done
}
