# shellcheck shell=bash
# nftables Firewall rule generators
# Returns nftables rule text via stdout

# Generates port accept rules based on firewall mode
_generate_port_rules() {
  local mode="${1:-standard}"
  local ssh="${PORT_SSH:-22}"
  local webui="${PORT_PROXMOX_UI:-8006}"

  case "$mode" in
    stealth)
      cat <<'EOF'
        # Stealth mode: all public ports blocked
        # Access only via Tailscale VPN or VM bridges
EOF
      ;;
    strict)
      cat <<EOF
        # SSH access (port $ssh)
        tcp dport $ssh ct state new accept
EOF
      ;;
    standard | *)
      cat <<EOF
        # SSH access (port $ssh)
        tcp dport $ssh ct state new accept

        # Proxmox Web UI (port $webui)
        tcp dport $webui ct state new accept
EOF
      ;;
  esac
}

# Generates bridge interface rules for input chain
_generate_bridge_input_rules() {
  local mode="${BRIDGE_MODE:-internal}"

  case "$mode" in
    internal)
      cat <<'EOF'
        # Allow traffic from vmbr0 (private NAT network)
        iifname "vmbr0" accept
EOF
      ;;
    external)
      cat <<'EOF'
        # Allow traffic from vmbr1 (external bridge)
        iifname "vmbr1" accept
EOF
      ;;
    both)
      cat <<'EOF'
        # Allow traffic from vmbr0 (private NAT network)
        iifname "vmbr0" accept

        # Allow traffic from vmbr1 (public IPs)
        iifname "vmbr1" accept
EOF
      ;;
  esac
}

# Generates bridge interface rules for forward chain
_generate_bridge_forward_rules() {
  local mode="${BRIDGE_MODE:-internal}"

  case "$mode" in
    internal)
      cat <<'EOF'
        # Allow forwarding for vmbr0 (private NAT network)
        iifname "vmbr0" accept
        oifname "vmbr0" accept
EOF
      ;;
    external)
      cat <<'EOF'
        # Allow forwarding for vmbr1 (external bridge)
        iifname "vmbr1" accept
        oifname "vmbr1" accept
EOF
      ;;
    both)
      cat <<'EOF'
        # Allow forwarding for vmbr0 (private NAT network)
        iifname "vmbr0" accept
        oifname "vmbr0" accept

        # Allow forwarding for vmbr1 (public IPs)
        iifname "vmbr1" accept
        oifname "vmbr1" accept
EOF
      ;;
  esac
}

# Generates Tailscale interface rules if enabled
_generate_tailscale_rules() {
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    cat <<'EOF'
        # Allow Tailscale VPN interface (traffic already on tunnel)
        iifname "tailscale0" accept

        # Allow incoming WireGuard UDP for direct peer connections
        # Required for NAT hole-punching and peer-to-peer connectivity
        udp dport 41641 accept
EOF
  else
    echo "        # Tailscale not installed"
  fi
}

# Generates NAT masquerade rules for private subnet
_generate_nat_rules() {
  local mode="${BRIDGE_MODE:-internal}"
  local subnet="${PRIVATE_SUBNET:-10.0.0.0/24}"

  case "$mode" in
    internal | both)
      cat <<EOF
        # Masquerade traffic from private subnet to internet
        oifname != "lo" ip saddr $subnet masquerade
EOF
      ;;
    external)
      echo "        # External mode: no NAT needed (VMs have public IPs)"
      ;;
  esac
}
