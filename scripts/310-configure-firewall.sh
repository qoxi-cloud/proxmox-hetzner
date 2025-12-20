# shellcheck shell=bash
# =============================================================================
# nftables Firewall configuration
# Modern replacement for iptables with unified IPv4/IPv6 rules
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Generate port rules based on firewall mode
_generate_port_rules() {
  local mode="$1"
  local rules=""

  case "$mode" in
    stealth)
      # Stealth mode: only bridges, tailscale, loopback - no SSH or Web UI on public IP
      rules="# Stealth mode: all public ports blocked
        # Access only via Tailscale VPN or VM bridges"
      ;;
    strict)
      # Strict mode: only SSH allowed
      rules="# SSH access (port ${PORT_SSH})
        tcp dport ${PORT_SSH} ct state new accept"
      ;;
    standard)
      # Standard mode: SSH + Proxmox Web UI
      rules="# SSH access (port ${PORT_SSH})
        tcp dport ${PORT_SSH} ct state new accept

        # Proxmox Web UI (port ${PORT_PROXMOX_UI})
        tcp dport ${PORT_PROXMOX_UI} ct state new accept"
      ;;
    *)
      log "WARNING: Unknown firewall mode: $mode, using standard"
      rules="# SSH access (port ${PORT_SSH})
        tcp dport ${PORT_SSH} ct state new accept

        # Proxmox Web UI (port ${PORT_PROXMOX_UI})
        tcp dport ${PORT_PROXMOX_UI} ct state new accept"
      ;;
  esac

  echo "$rules"
}

# Generate bridge input rules based on BRIDGE_MODE
_generate_bridge_input_rules() {
  local mode="${BRIDGE_MODE:-internal}"
  local rules=""

  case "$mode" in
    internal)
      # Internal NAT only - vmbr0
      rules='# Allow traffic from internal bridge (vmbr0 - private NAT network)
        iifname "vmbr0" accept'
      ;;
    external)
      # External bridge only - vmbr1
      rules='# Allow traffic from external bridge (vmbr1 - public IPs)
        iifname "vmbr1" accept'
      ;;
    both)
      # Both bridges
      rules='# Allow traffic from internal bridge (vmbr0 - private NAT network)
        iifname "vmbr0" accept

        # Allow traffic from external bridge (vmbr1 - public IPs)
        iifname "vmbr1" accept'
      ;;
    *)
      log "WARNING: Unknown bridge mode: $mode, using internal"
      rules='# Allow traffic from internal bridge (vmbr0 - private NAT network)
        iifname "vmbr0" accept'
      ;;
  esac

  echo "$rules"
}

# Generate bridge forward rules based on BRIDGE_MODE
_generate_bridge_forward_rules() {
  local mode="${BRIDGE_MODE:-internal}"
  local rules=""

  case "$mode" in
    internal)
      rules='# Allow forwarding for internal bridge (VM traffic)
        iifname "vmbr0" accept
        oifname "vmbr0" accept'
      ;;
    external)
      rules='# Allow forwarding for external bridge (VM traffic)
        iifname "vmbr1" accept
        oifname "vmbr1" accept'
      ;;
    both)
      rules='# Allow forwarding for both bridges (VM traffic)
        iifname "vmbr0" accept
        iifname "vmbr1" accept
        oifname "vmbr0" accept
        oifname "vmbr1" accept'
      ;;
    *)
      rules='# Allow forwarding for internal bridge (VM traffic)
        iifname "vmbr0" accept
        oifname "vmbr0" accept'
      ;;
  esac

  echo "$rules"
}

# Generate Tailscale rules if enabled
_generate_tailscale_rules() {
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    echo '# Allow Tailscale VPN interface
        iifname "tailscale0" accept'
  else
    echo "# Tailscale not installed"
  fi
}

# Generate NAT masquerade rules based on BRIDGE_MODE and PRIVATE_SUBNET
_generate_nat_rules() {
  local mode="${BRIDGE_MODE:-internal}"
  local subnet="${PRIVATE_SUBNET:-10.0.0.0/24}"
  local rules=""

  # NAT is only needed for internal/both modes (private networks)
  case "$mode" in
    internal | both)
      # Extract network base from CIDR (e.g., 10.0.0.0/24 -> 10.0.0.0/24)
      # Also handle common private ranges for flexibility
      rules="# Masquerade traffic from private subnet to internet
        oifname != \"lo\" ip saddr ${subnet} masquerade"

      # If subnet is part of larger private block, also cover it
      local subnet_base="${subnet%%.*}"
      case "$subnet_base" in
        10)
          # 10.x.x.x range - masquerade the specific subnet
          ;;
        172)
          # 172.16-31.x.x range
          ;;
        192)
          # 192.168.x.x range
          ;;
      esac
      ;;
    external)
      # External mode - no NAT needed (VMs have public IPs)
      rules="# External mode: no NAT needed (VMs have public IPs)"
      ;;
  esac

  echo "$rules"
}

# Configuration function for nftables
_config_nftables() {
  # Set up iptables-nft compatibility layer
  remote_exec '
    update-alternatives --set iptables /usr/sbin/iptables-nft 2>/dev/null || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-nft 2>/dev/null || true
  ' || true

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
  nftables_conf=$(echo "$nftables_conf" | sed "/# === FIREWALL_RULES_START ===/,/# === FIREWALL_RULES_END ===/c\\
        # === FIREWALL_RULES_START ===\\
$port_rules\\
        # === FIREWALL_RULES_END ===")

  # Replace bridge input rules
  nftables_conf=$(echo "$nftables_conf" | sed "/# === BRIDGE_INPUT_RULES ===/c\\
$bridge_input_rules")

  # Replace Tailscale rules
  nftables_conf=$(echo "$nftables_conf" | sed "/# === TAILSCALE_RULES ===/c\\
$tailscale_rules")

  # Replace bridge forward rules
  nftables_conf=$(echo "$nftables_conf" | sed "/# === BRIDGE_FORWARD_RULES ===/c\\
$bridge_forward_rules")

  # Replace NAT rules
  nftables_conf=$(echo "$nftables_conf" | sed "/# === NAT_RULES ===/c\\
$nat_rules")

  # Write to temp file
  echo "$nftables_conf" >"./templates/nftables.conf.generated"

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

  # Configure using helper (package already installed via batch_install_packages)
  (
    _config_nftables || exit 1
  ) >/dev/null 2>&1 &

  local mode_display=""
  case "$FIREWALL_MODE" in
    stealth) mode_display="stealth (Tailscale only)" ;;
    strict) mode_display="strict (SSH only)" ;;
    standard) mode_display="standard (SSH + Web UI)" ;;
    *) mode_display="$FIREWALL_MODE" ;;
  esac

  show_progress $! "Configuring nftables firewall" "Firewall configured ($mode_display)"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: Firewall setup failed"
    return 0 # Non-fatal error
  fi
}
