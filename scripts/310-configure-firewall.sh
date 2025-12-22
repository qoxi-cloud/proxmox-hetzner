# shellcheck shell=bash
# =============================================================================
# nftables Firewall configuration
# Modern replacement for iptables with unified IPv4/IPv6 rules
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# -----------------------------------------------------------------------------
# Rule definitions (data-driven configuration)
# -----------------------------------------------------------------------------

# Port rules by firewall mode: "port1 port2 ..."
# Empty = no public ports (stealth mode)
declare -A FIREWALL_PORT_RULES=(
  [stealth]=""
  [strict]="${PORT_SSH}"
  [standard]="${PORT_SSH} ${PORT_PROXMOX_UI}"
)

# Bridge interfaces by bridge mode
declare -A BRIDGE_IFACES=(
  [internal]="vmbr0"
  [external]="vmbr1"
  [both]="vmbr0 vmbr1"
)

# Bridge descriptions for comments (key format: iface_mode)
declare -A BRIDGE_DESCRIPTIONS=(
  [vmbr0_internal]="private NAT network"
  [vmbr0_external]="external bridge"
  [vmbr0_both]="private NAT network"
  [vmbr1_external]="external bridge"
  [vmbr1_both]="public IPs"
)

# -----------------------------------------------------------------------------
# Rule generators
# -----------------------------------------------------------------------------

# Generates nftables port accept rules based on firewall mode.
# Parameters:
#   $1 - Firewall mode (stealth, strict, standard)
# Returns: nftables rule text via stdout
_generate_port_rules() {
  local mode="$1"
  local ports="${FIREWALL_PORT_RULES[$mode]:-${FIREWALL_PORT_RULES[standard]}}"

  if [[ -z $ports ]]; then
    printf '%s\n' "# Stealth mode: all public ports blocked
        # Access only via Tailscale VPN or VM bridges"
    return
  fi

  local first=true
  for port in $ports; do
    local desc=""
    case "$port" in
      "${PORT_SSH}") desc="SSH" ;;
      "${PORT_PROXMOX_UI}") desc="Proxmox Web UI" ;;
      *) desc="Service" ;;
    esac

    $first || printf '\n'
    printf '        # %s access (port %s)\n' "$desc" "$port"
    printf '        tcp dport %s ct state new accept' "$port"
    first=false
  done
  printf '\n'
}

# Generates nftables bridge interface rules for a specific chain.
# Parameters:
#   $1 - Chain type: "input" or "forward"
# Uses: BRIDGE_MODE global for interface selection
# Returns: nftables rule text via stdout
_generate_bridge_rules() {
  local chain="$1"
  local mode="${BRIDGE_MODE:-internal}"
  local ifaces="${BRIDGE_IFACES[$mode]:-${BRIDGE_IFACES[internal]}}"

  local first=true
  for iface in $ifaces; do
    local desc="${BRIDGE_DESCRIPTIONS[${iface}_${mode}]:-bridge}"
    $first || printf '\n'

    case "$chain" in
      input)
        printf '        # Allow traffic from %s (%s)\n' "$iface" "$desc"
        printf '        iifname "%s" accept' "$iface"
        ;;
      forward)
        printf '        # Allow forwarding for %s (%s)\n' "$iface" "$desc"
        printf '        iifname "%s" accept\n' "$iface"
        printf '        oifname "%s" accept' "$iface"
        ;;
    esac
    first=false
  done
  printf '\n'
}

# Generates bridge input chain rules. Wrapper for _generate_bridge_rules.
# Returns: nftables rule text via stdout
_generate_bridge_input_rules() {
  _generate_bridge_rules "input"
}

# Generates bridge forward chain rules. Wrapper for _generate_bridge_rules.
# Returns: nftables rule text via stdout
_generate_bridge_forward_rules() {
  _generate_bridge_rules "forward"
}

# Generates nftables rules for Tailscale interface if enabled.
# Uses: INSTALL_TAILSCALE global
# Returns: nftables rule text via stdout
_generate_tailscale_rules() {
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    printf '%s\n' '# Allow Tailscale VPN interface
        iifname "tailscale0" accept'
  else
    printf '%s\n' "# Tailscale not installed"
  fi
}

# Generates NAT masquerade rules for private subnet internet access.
# Only generates rules for internal/both modes (private networks).
# Uses: BRIDGE_MODE, PRIVATE_SUBNET globals
# Returns: nftables rule text via stdout
_generate_nat_rules() {
  local mode="${BRIDGE_MODE:-internal}"
  local subnet="${PRIVATE_SUBNET:-10.0.0.0/24}"
  local rules=""

  # NAT is only needed for internal/both modes (private networks)
  case "$mode" in
    internal | both)
      # Masquerade traffic from private subnet to allow internet access
      rules="# Masquerade traffic from private subnet to internet
        oifname != \"lo\" ip saddr ${subnet} masquerade"
      ;;
    external)
      # External mode - no NAT needed (VMs have public IPs)
      rules="# External mode: no NAT needed (VMs have public IPs)"
      ;;
  esac

  printf '%s\n' "$rules"
}

# Main implementation for nftables configuration.
# Generates rules from template, validates syntax, enables service.
# Side effects: Writes /etc/nftables.conf, enables nftables service
_config_nftables() {
  # Set up iptables-nft compatibility layer for tools that call iptables directly
  remote_exec '
    update-alternatives --set iptables /usr/sbin/iptables-nft
    update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
  ' || log "WARNING: Could not set iptables-nft alternatives (nftables still works directly)"

  # Read the template
  local template_content
  template_content=$(cat "./templates/nftables.conf")

  # Generate all rules
  local port_rules bridge_input_rules bridge_forward_rules nat_rules tailscale_rules

  port_rules=$(_generate_port_rules "$FIREWALL_MODE")
  bridge_input_rules=$(_generate_bridge_input_rules)
  bridge_forward_rules=$(_generate_bridge_forward_rules)
  nat_rules=$(_generate_nat_rules)
  tailscale_rules=$(_generate_tailscale_rules)

  # Build the final config by replacing placeholders
  local nftables_conf="$template_content"

  # Replace bridge mode comment
  nftables_conf="${nftables_conf//\{\{BRIDGE_MODE\}\}/$BRIDGE_MODE}"

  # Replace port rules
  nftables_conf=$(printf '%s\n' "$nftables_conf" | sed "/# === FIREWALL_RULES_START ===/,/# === FIREWALL_RULES_END ===/c\\
        # === FIREWALL_RULES_START ===\\
$port_rules\\
        # === FIREWALL_RULES_END ===")

  # Replace bridge input rules
  nftables_conf=$(printf '%s\n' "$nftables_conf" | sed "/# === BRIDGE_INPUT_RULES ===/c\\
$bridge_input_rules")

  # Replace Tailscale rules
  nftables_conf=$(printf '%s\n' "$nftables_conf" | sed "/# === TAILSCALE_RULES ===/c\\
$tailscale_rules")

  # Replace bridge forward rules
  nftables_conf=$(printf '%s\n' "$nftables_conf" | sed "/# === BRIDGE_FORWARD_RULES ===/c\\
$bridge_forward_rules")

  # Replace NAT rules
  nftables_conf=$(printf '%s\n' "$nftables_conf" | sed "/# === NAT_RULES ===/c\\
$nat_rules")

  # Write to temp file
  printf '%s\n' "$nftables_conf" >"./templates/nftables.conf.generated"

  # Log the generated config for debugging
  log "Generated nftables config:"
  log "  Bridge mode: $BRIDGE_MODE"
  log "  Firewall mode: $FIREWALL_MODE"
  log "  Private subnet: ${PRIVATE_SUBNET:-N/A}"

  # Copy configuration to VM
  remote_copy "templates/nftables.conf.generated" "/etc/nftables.conf" || {
    log "ERROR: Failed to deploy nftables config"
    return 1
  }

  # Validate config syntax before enabling (catches errors before SSH gets blocked)
  remote_exec "nft -c -f /etc/nftables.conf" || {
    log "ERROR: nftables config syntax validation failed"
    return 1
  }

  # Enable nftables to start on boot (don't start now - will activate after reboot)
  remote_exec "systemctl enable nftables" || {
    log "ERROR: Failed to enable nftables"
    return 1
  }

  # Clean up temp file
  rm -f "./templates/nftables.conf.generated"
}

# Configures nftables firewall based on INSTALL_FIREWALL and FIREWALL_MODE settings.
# Also considers BRIDGE_MODE for interface rules and PRIVATE_SUBNET for NAT.
# Modes:
#   - stealth: blocks ALL incoming (only tailscale/bridges/loopback)
#   - strict: allows SSH only (port 22)
#   - standard: allows SSH + Proxmox Web UI (8006)
configure_firewall() {
  # Skip if firewall is disabled
  if [[ $INSTALL_FIREWALL != "yes" ]]; then
    log "Skipping firewall configuration (INSTALL_FIREWALL=$INSTALL_FIREWALL)"
    return 0
  fi

  log "Configuring nftables firewall (mode: $FIREWALL_MODE, bridge: $BRIDGE_MODE)"

  # Build mode display string for progress message
  local mode_display=""
  case "$FIREWALL_MODE" in
    stealth) mode_display="stealth (Tailscale only)" ;;
    strict) mode_display="strict (SSH only)" ;;
    standard) mode_display="standard (SSH + Web UI)" ;;
    *) mode_display="$FIREWALL_MODE" ;;
  esac

  # Configure using helper (package already installed via batch_install_packages)
  if ! run_with_progress "Configuring nftables firewall" "Firewall configured ($mode_display)" _config_nftables; then
    log "WARNING: Firewall setup failed"
  fi
  return 0 # Non-fatal error
}
