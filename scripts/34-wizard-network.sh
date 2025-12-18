# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Network Settings Editors
# interface, bridge_mode, private_subnet, ipv6
# =============================================================================

_edit_interface() {
  _wiz_start_edit

  # Get available interfaces (use cached value)
  local interface_count=${INTERFACE_COUNT:-1}
  local available_interfaces=${AVAILABLE_INTERFACES:-$INTERFACE_NAME}

  # Calculate footer size: 1 header + number of interfaces
  local footer_size=$((interface_count + 1))
  _show_input_footer "filter" "$footer_size"

  local selected
  selected=$(
    echo "$available_interfaces" | _wiz_choose \
      --header="Network Interface:"
  )

  [[ -n $selected ]] && INTERFACE_NAME="$selected"
}

_edit_bridge_mode() {
  _wiz_start_edit

  _wiz_description \
    "Network bridge configuration for VMs:" \
    "" \
    "  {{cyan:External}}: VMs get public IPs directly (routed mode)" \
    "  {{cyan:Internal}}: Private network with NAT (10.x.x.x)" \
    "  {{cyan:Both}}:     External + Internal bridges" \
    ""

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  local selected
  selected=$(
    echo "$WIZ_BRIDGE_MODES" | _wiz_choose \
      --header="Bridge mode:"
  )

  if [[ -n $selected ]]; then
    # Map display names to internal values
    case "$selected" in
      "External bridge") BRIDGE_MODE="external" ;;
      "Internal NAT") BRIDGE_MODE="internal" ;;
      "Both") BRIDGE_MODE="both" ;;
    esac
  fi
}

_edit_private_subnet() {
  _wiz_start_edit

  # 1 header + 4 items for gum choose
  _show_input_footer "filter" 5

  local selected
  selected=$(
    echo "$WIZ_PRIVATE_SUBNETS" | _wiz_choose \
      --header="Private subnet:"
  )

  # If user cancelled (Esc) or no selection
  if [[ -z $selected ]]; then
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

_edit_ipv6() {
  _wiz_start_edit

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  local selected
  selected=$(
    echo "$WIZ_IPV6_MODES" | _wiz_choose \
      --header="IPv6:"
  )

  # If user cancelled (Esc) or no selection
  if [[ -z $selected ]]; then
    return
  fi

  # Map display names to internal values
  local ipv6_mode=""
  case "$selected" in
    "Auto") ipv6_mode="auto" ;;
    "Manual") ipv6_mode="manual" ;;
    "Disabled") ipv6_mode="disabled" ;;
  esac

  IPV6_MODE="$ipv6_mode"

  # Handle manual mode - need to collect IPv6 address and gateway
  if [[ $ipv6_mode == "manual" ]]; then
    # IPv6 Address input
    while true; do
      _wiz_input_screen \
        "Enter IPv6 address in CIDR notation" \
        "Example: 2001:db8::1/64"

      local ipv6_addr
      ipv6_addr=$(
        _wiz_input \
          --placeholder "2001:db8::1/64" \
          --prompt "IPv6 Address: " \
          --value "${IPV6_ADDRESS:-${MAIN_IPV6:+${MAIN_IPV6}/64}}"
      )

      # If empty or cancelled, exit manual mode
      if [[ -z $ipv6_addr ]]; then
        IPV6_MODE=""
        return
      fi

      # Validate IPv6 CIDR
      if validate_ipv6_cidr "$ipv6_addr"; then
        IPV6_ADDRESS="$ipv6_addr"
        MAIN_IPV6="${ipv6_addr%/*}"
        break
      else
        show_validation_error "Invalid IPv6 CIDR notation. Use format like: 2001:db8::1/64"
      fi
    done

    # IPv6 Gateway input
    while true; do
      _wiz_input_screen \
        "Enter IPv6 gateway address" \
        "Default for Hetzner: fe80::1 (link-local)"

      local ipv6_gw
      ipv6_gw=$(
        _wiz_input \
          --placeholder "fe80::1" \
          --prompt "Gateway: " \
          --value "${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
      )

      # If empty or cancelled, use default
      if [[ -z $ipv6_gw ]]; then
        IPV6_GATEWAY="$DEFAULT_IPV6_GATEWAY"
        break
      fi

      # Validate IPv6 gateway
      if validate_ipv6_gateway "$ipv6_gw"; then
        IPV6_GATEWAY="$ipv6_gw"
        break
      else
        show_validation_error "Invalid IPv6 gateway address"
      fi
    done
  elif [[ $ipv6_mode == "disabled" ]]; then
    # Clear IPv6 settings when disabled
    MAIN_IPV6=""
    IPV6_GATEWAY=""
    FIRST_IPV6_CIDR=""
    IPV6_ADDRESS=""
  elif [[ $ipv6_mode == "auto" ]]; then
    # Auto mode - use detected values or defaults
    IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
  fi
}
