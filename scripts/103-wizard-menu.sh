# shellcheck shell=bash
# Configuration Wizard - Menu Rendering
# Field tracking and menu rendering

# Field tracking

# Menu item indices (for mapping selection to edit functions)
# These track which items are selectable fields vs section headers
_WIZ_FIELD_COUNT=0
_WIZ_FIELD_MAP=()

# Configuration validation

# Check if all required config fields set. Returns 0=complete, 1=missing
_wiz_config_complete() {
  [[ -z $PVE_HOSTNAME ]] && return 1
  [[ -z $DOMAIN_SUFFIX ]] && return 1
  [[ -z $EMAIL ]] && return 1
  [[ -z $NEW_ROOT_PASSWORD ]] && return 1
  [[ -z $ADMIN_USERNAME ]] && return 1
  [[ -z $ADMIN_PASSWORD ]] && return 1
  [[ -z $TIMEZONE ]] && return 1
  [[ -z $KEYBOARD ]] && return 1
  [[ -z $COUNTRY ]] && return 1
  [[ -z $PROXMOX_ISO_VERSION ]] && return 1
  [[ -z $PVE_REPO_TYPE ]] && return 1
  [[ -z $INTERFACE_NAME ]] && return 1
  [[ -z $BRIDGE_MODE ]] && return 1
  [[ $BRIDGE_MODE != "external" && -z $PRIVATE_SUBNET ]] && return 1
  [[ -z $IPV6_MODE ]] && return 1
  # ZFS validation: require raid/disks only when NOT using existing pool
  if [[ $USE_EXISTING_POOL == "yes" ]]; then
    [[ -z $EXISTING_POOL_NAME ]] && return 1
  else
    [[ -z $ZFS_RAID ]] && return 1
    [[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]] && return 1
  fi
  [[ -z $ZFS_ARC_MODE ]] && return 1
  [[ -z $SHELL_TYPE ]] && return 1
  [[ -z $CPU_GOVERNOR ]] && return 1
  [[ -z $SSH_PUBLIC_KEY ]] && return 1
  # SSL required if Tailscale disabled
  [[ $INSTALL_TAILSCALE != "yes" && -z $SSL_TYPE ]] && return 1
  # Stealth firewall requires Tailscale
  [[ $FIREWALL_MODE == "stealth" && $INSTALL_TAILSCALE != "yes" ]] && return 1
  return 0
}

# Screen content renderers

# Render fields for a screen. $1=screen_idx, $2=selection
_wiz_render_screen_content() {
  local screen="$1"
  local selection="$2"

  case $screen in
    0) # Basic
      _add_field "Hostname         " "$(_wiz_fmt "$_DSP_HOSTNAME")" "hostname"
      _add_field "Email            " "$(_wiz_fmt "$EMAIL")" "email"
      _add_field "Password         " "$(_wiz_fmt "$_DSP_PASS")" "password"
      _add_field "Timezone         " "$(_wiz_fmt "$TIMEZONE")" "timezone"
      _add_field "Keyboard         " "$(_wiz_fmt "$KEYBOARD")" "keyboard"
      _add_field "Country          " "$(_wiz_fmt "$COUNTRY")" "country"
      ;;
    1) # Proxmox
      _add_field "Version          " "$(_wiz_fmt "$_DSP_ISO")" "iso_version"
      _add_field "Repository       " "$(_wiz_fmt "$_DSP_REPO")" "repository"
      ;;
    2) # Network
      if [[ ${INTERFACE_COUNT:-1} -gt 1 ]]; then
        _add_field "Interface        " "$(_wiz_fmt "$INTERFACE_NAME")" "interface"
      fi
      _add_field "Bridge mode      " "$(_wiz_fmt "$_DSP_BRIDGE")" "bridge_mode"
      if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
        _add_field "Private subnet   " "$(_wiz_fmt "$PRIVATE_SUBNET")" "private_subnet"
        _add_field "Bridge MTU       " "$(_wiz_fmt "$_DSP_MTU")" "bridge_mtu"
      fi
      _add_field "IPv6             " "$(_wiz_fmt "$_DSP_IPV6")" "ipv6"
      _add_field "Firewall         " "$(_wiz_fmt "$_DSP_FIREWALL")" "firewall"
      ;;
    3) # Storage
      _add_field "Wipe disks       " "$(_wiz_fmt "$_DSP_WIPE")" "wipe_disks"
      if [[ $DRIVE_COUNT -gt 1 ]]; then
        _add_field "Boot disk        " "$(_wiz_fmt "$_DSP_BOOT")" "boot_disk"
        _add_field "Pool mode        " "$(_wiz_fmt "$_DSP_EXISTING_POOL")" "existing_pool"
        # Only show pool disk options if not using existing pool
        if [[ $USE_EXISTING_POOL != "yes" ]]; then
          _add_field "Pool disks       " "$(_wiz_fmt "$_DSP_POOL")" "pool_disks"
          _add_field "ZFS mode         " "$(_wiz_fmt "$_DSP_ZFS")" "zfs_mode"
        fi
      else
        # Single disk: no pool selection needed
        _add_field "ZFS mode         " "$(_wiz_fmt "$_DSP_ZFS")" "zfs_mode"
      fi
      _add_field "ZFS ARC          " "$(_wiz_fmt "$_DSP_ARC")" "zfs_arc"
      ;;
    4) # Services
      _add_field "Tailscale        " "$(_wiz_fmt "$_DSP_TAILSCALE")" "tailscale"
      if [[ $INSTALL_TAILSCALE != "yes" ]]; then
        _add_field "SSL Certificate  " "$(_wiz_fmt "$_DSP_SSL")" "ssl"
      fi
      _add_field "Shell            " "$(_wiz_fmt "$_DSP_SHELL")" "shell"
      _add_field "Power profile    " "$(_wiz_fmt "$_DSP_POWER")" "power_profile"
      _add_field "Security         " "$(_wiz_fmt "$_DSP_SECURITY")" "security"
      _add_field "Monitoring       " "$(_wiz_fmt "$_DSP_MONITORING")" "monitoring"
      _add_field "Tools            " "$(_wiz_fmt "$_DSP_TOOLS")" "tools"
      ;;
    5) # Access
      _add_field "Admin User       " "$(_wiz_fmt "$_DSP_ADMIN_USER")" "admin_username"
      _add_field "Admin Password   " "$(_wiz_fmt "$_DSP_ADMIN_PASS")" "admin_password"
      _add_field "SSH Key          " "$(_wiz_fmt "$_DSP_SSH")" "ssh_key"
      _add_field "API Token        " "$(_wiz_fmt "$_DSP_API")" "api_token"
      ;;
  esac
}

# Render main menu with selection. $1=selection_idx
_wiz_render_menu() {
  local selection="$1"
  local output=""
  local banner_output

  # Capture banner output
  banner_output=$(show_banner)

  # Build display values
  _wiz_build_display_values

  # Start output with banner + navigation header
  output+="${banner_output}\n\n$(_wiz_render_nav)\n\n"

  # Reset field map
  _WIZ_FIELD_MAP=()
  local field_idx=0

  # Helper to add field (used by _wiz_render_screen_content)
  _add_field() {
    local label="$1"
    local value="$2"
    local field_name="$3"
    _WIZ_FIELD_MAP+=("$field_name")
    if [[ $field_idx -eq $selection ]]; then
      output+="${CLR_ORANGE}›${CLR_RESET} ${CLR_GRAY}${label}${CLR_RESET}${value}\n"
    else
      output+="  ${CLR_GRAY}${label}${CLR_RESET}${value}\n"
    fi
    ((field_idx++))
  }

  # Render current screen content
  _wiz_render_screen_content "$WIZ_CURRENT_SCREEN" "$selection"

  # Store total field count for this screen
  _WIZ_FIELD_COUNT=$field_idx

  output+="\n"

  # Footer with navigation hints (centered)
  # Left/right/start hints: orange when active, gray when inactive
  local left_clr right_clr start_clr
  left_clr=$([[ $WIZ_CURRENT_SCREEN -gt 0 ]] && echo "$CLR_ORANGE" || echo "$CLR_GRAY")
  right_clr=$([[ $WIZ_CURRENT_SCREEN -lt $((${#WIZ_SCREENS[@]} - 1)) ]] && echo "$CLR_ORANGE" || echo "$CLR_GRAY")
  start_clr=$(_wiz_config_complete && echo "$CLR_ORANGE" || echo "$CLR_GRAY")

  local nav_hint=""
  nav_hint+="[${left_clr}←${CLR_GRAY}] prev  "
  nav_hint+="[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] edit  "
  nav_hint+="[${right_clr}→${CLR_GRAY}] next  "
  nav_hint+="[${start_clr}S${CLR_GRAY}] start  [${CLR_ORANGE}Q${CLR_GRAY}] quit"

  output+="$(_wiz_center "${CLR_GRAY}${nav_hint}${CLR_RESET}")"

  # Clear screen and output everything atomically
  _wiz_clear
  printf '%b' "$output"
}
