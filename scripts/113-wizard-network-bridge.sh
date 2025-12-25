# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Network Settings Editors (Bridge & Basic)
# interface, bridge_mode, private_subnet, bridge_mtu
# =============================================================================

# Edits primary network interface via selection list.
# Uses cached interface list from system detection.
# Updates INTERFACE_NAME global.
_edit_interface() {
  _wiz_start_edit

  # Get available interfaces (use cached value)
  local interface_count=${INTERFACE_COUNT:-1}
  local available_interfaces=${AVAILABLE_INTERFACES:-$INTERFACE_NAME}

  # Calculate footer size: 1 header + number of interfaces
  local footer_size=$((interface_count + 1))
  _show_input_footer "filter" "$footer_size"

  local selected
  if ! selected=$(printf '%s\n' "$available_interfaces" | _wiz_choose --header="Network Interface:"); then
    return
  fi

  INTERFACE_NAME="$selected"
}

# Edits network bridge mode for VM networking.
# Options: internal (NAT), external (routed), both.
# Updates BRIDGE_MODE global.
_edit_bridge_mode() {
  _wiz_start_edit

  _wiz_description \
    "  Network bridge configuration for VMs:" \
    "" \
    "  {{cyan:Internal}}: Private network with NAT (10.x.x.x)" \
    "  {{cyan:External}}: VMs get public IPs directly (routed mode)" \
    "  {{cyan:Both}}:     Internal + External bridges" \
    ""

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  _wiz_choose_mapped "BRIDGE_MODE" "Bridge mode:" "WIZ_BRIDGE_MODES" \
    "External bridge:external" \
    "Internal NAT:internal" \
    "Both:both"
}

# Edits private subnet for NAT bridge.
# Supports preset options or custom CIDR input.
# Updates PRIVATE_SUBNET global.
_edit_private_subnet() {
  _wiz_start_edit

  _wiz_description \
    "  Private network for VMs (NAT to internet):" \
    "" \
    "  {{cyan:10.0.0.0/24}}:    Class A private (default)" \
    "  {{cyan:192.168.1.0/24}}: Class C private (home-style)" \
    "  {{cyan:172.16.0.0/24}}:  Class B private" \
    ""

  # 1 header + 4 items for gum choose
  _show_input_footer "filter" 5

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_PRIVATE_SUBNETS" | _wiz_choose --header="Private subnet:"); then
    return
  fi

  # Handle custom subnet input
  if [[ $selected == "Custom" ]]; then
    while true; do
      _wiz_input_screen \
        "Enter private subnet in CIDR notation" \
        "Example: 10.0.0.0/24"

      local new_subnet
      new_subnet=$(
        _wiz_input \
          --placeholder "e.g., 10.10.10.0/24" \
          --value "$PRIVATE_SUBNET" \
          --prompt "Private subnet: "
      )

      # If empty or cancelled, return to menu
      if [[ -z $new_subnet ]]; then
        return
      fi

      # Validate subnet
      if validate_subnet "$new_subnet"; then
        PRIVATE_SUBNET="$new_subnet"
        break
      else
        show_validation_error "Invalid subnet format. Use CIDR notation like: 10.0.0.0/24"
      fi
    done
  else
    # Use selected preset
    PRIVATE_SUBNET="$selected"
  fi
}

# Edits private bridge MTU for VM-to-VM traffic.
# Options: 9000 (jumbo frames) or 1500 (standard).
# Updates BRIDGE_MTU global.
_edit_bridge_mtu() {
  _wiz_start_edit

  _wiz_description \
    "  MTU for private bridge (VM-to-VM traffic):" \
    "" \
    "  {{cyan:9000}}:  Jumbo frames (better VM performance)" \
    "  {{cyan:1500}}:  Standard MTU (safe default)" \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  _wiz_choose_mapped "BRIDGE_MTU" "Bridge MTU:" "WIZ_BRIDGE_MTU" \
    "9000 (jumbo frames):9000" \
    "1500 (standard):1500"
}
