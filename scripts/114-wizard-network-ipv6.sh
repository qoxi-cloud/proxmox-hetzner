# shellcheck shell=bash
# Configuration Wizard - Network Settings Editors (IPv6 & Firewall)
# ipv6, firewall

# Edits IPv6 configuration mode and address/gateway.
# Modes: auto (detected), manual (custom input), disabled.
# Updates IPV6_MODE, IPV6_ADDRESS, IPV6_GATEWAY, MAIN_IPV6 globals.
_edit_ipv6() {
  _wiz_start_edit

  _wiz_description \
    "  IPv6 network configuration:" \
    "" \
    "  {{cyan:Auto}}:     Use detected IPv6 from provider" \
    "  {{cyan:Manual}}:   Specify custom IPv6 address/gateway" \
    "  {{cyan:Disabled}}: IPv4 only" \
    ""

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_IPV6_MODES" | _wiz_choose --header="IPv6:"); then
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
          --value "${IPV6_ADDRESS:-${FIRST_IPV6_CIDR:-$MAIN_IPV6}}"
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
        "Common default: fe80::1 (link-local)"

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

# Edits host firewall mode.
# Modes: stealth (Tailscale only), strict (SSH), standard (SSH+Web), disabled.
# Updates INSTALL_FIREWALL and FIREWALL_MODE globals.
_edit_firewall() {
  _wiz_start_edit

  _wiz_description \
    "  Host firewall (nftables):" \
    "" \
    "  {{cyan:Stealth}}:  Blocks ALL incoming (Tailscale/bridges only)" \
    "  {{cyan:Strict}}:   Allows SSH only (port 22)" \
    "  {{cyan:Standard}}: Allows SSH + Proxmox Web UI (8006)" \
    "  {{cyan:Disabled}}: No firewall rules" \
    "" \
    "  Note: VMs always have full network access via bridges." \
    ""

  # 1 header + 4 items for gum choose
  _show_input_footer "filter" 5

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_FIREWALL_MODES" | _wiz_choose --header="Firewall mode:"); then
    return
  fi

  case "$selected" in
    "Stealth (Tailscale only)")
      INSTALL_FIREWALL="yes"
      FIREWALL_MODE="stealth"
      ;;
    "Strict (SSH only)")
      INSTALL_FIREWALL="yes"
      FIREWALL_MODE="strict"
      ;;
    "Standard (SSH + Web UI)")
      INSTALL_FIREWALL="yes"
      FIREWALL_MODE="standard"
      ;;
    "Disabled")
      INSTALL_FIREWALL="no"
      FIREWALL_MODE=""
      ;;
  esac
}
