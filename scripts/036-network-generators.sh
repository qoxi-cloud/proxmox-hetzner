# shellcheck shell=bash
# =============================================================================
# Network interfaces section generators
# Returns config sections for /etc/network/interfaces
# =============================================================================

# Generates loopback interface section
_generate_loopback() {
  cat <<'EOF'
auto lo
iface lo inet loopback

iface lo inet6 loopback
EOF
}

# Generates physical interface section (manual mode for bridges)
_generate_iface_manual() {
  cat <<EOF
# Physical interface (no IP, part of bridge)
auto ${INTERFACE_NAME}
iface ${INTERFACE_NAME} inet manual
EOF
}

# Generates physical interface section with static IP
# Uses detected CIDR from rescue system (MAIN_IPV4_CIDR, IPV6_CIDR)
# Or manual IPV6_ADDRESS from wizard if user overrode auto-detection
# Falls back to /32 and /128 for Hetzner-style point-to-point routing if not detected
# Adds pointopoint directive for /32 subnets where gateway is outside the interface subnet
_generate_iface_static() {
  local ipv4_addr="${MAIN_IPV4_CIDR:-${MAIN_IPV4}/32}"
  local ipv6_addr="${IPV6_ADDRESS:-${IPV6_CIDR:-${MAIN_IPV6}/128}}"
  local ipv4_prefix="${ipv4_addr##*/}"
  local ipv6_prefix="${ipv6_addr##*/}"

  cat <<EOF
# Physical interface with host IP
auto ${INTERFACE_NAME}
iface ${INTERFACE_NAME} inet static
    address ${ipv4_addr}
EOF

  # For /32 subnets, gateway is outside interface subnet - add pointopoint route
  if [[ $ipv4_prefix == "32" ]]; then
    cat <<EOF
    pointopoint ${MAIN_IPV4_GW}
EOF
  fi

  cat <<EOF
    gateway ${MAIN_IPV4_GW}
    up sysctl --system
EOF

  # Add IPv6 if enabled
  if [[ -n ${MAIN_IPV6:-} && ${IPV6_MODE:-} != "disabled" ]]; then
    local ipv6_gw="${IPV6_GATEWAY:-fe80::1}"
    # Translate "auto" to link-local default (Hetzner standard)
    [[ $ipv6_gw == "auto" ]] && ipv6_gw="fe80::1"
    cat <<EOF

iface ${INTERFACE_NAME} inet6 static
    address ${ipv6_addr}
    gateway ${ipv6_gw}
EOF
    # For /128 with non-link-local gateway, add explicit on-link route
    if [[ $ipv6_prefix == "128" && ! $ipv6_gw =~ ^fe80: ]]; then
      cat <<EOF
    up ip -6 route add ${ipv6_gw}/128 dev ${INTERFACE_NAME}
EOF
    fi
    cat <<EOF
    accept_ra 2
EOF
  fi
}

# Generates vmbr0 as external bridge (host IP on bridge)
# Uses detected CIDR (see _generate_iface_static for fallback logic)
_generate_vmbr0_external() {
  local ipv4_addr="${MAIN_IPV4_CIDR:-${MAIN_IPV4}/32}"
  local ipv6_addr="${IPV6_ADDRESS:-${IPV6_CIDR:-${MAIN_IPV6}/128}}"
  local ipv4_prefix="${ipv4_addr##*/}"
  local ipv6_prefix="${ipv6_addr##*/}"

  cat <<EOF
# vmbr0: External bridge - VMs get IPs from router/DHCP
# Host IP is on this bridge
auto vmbr0
iface vmbr0 inet static
    address ${ipv4_addr}
EOF

  # For /32 subnets, gateway is outside interface subnet - add pointopoint route
  if [[ $ipv4_prefix == "32" ]]; then
    cat <<EOF
    pointopoint ${MAIN_IPV4_GW}
EOF
  fi

  cat <<EOF
    gateway ${MAIN_IPV4_GW}
    bridge-ports ${INTERFACE_NAME}
    bridge-stp off
    bridge-fd 0
    up sysctl --system
EOF

  # Add IPv6 if enabled
  if [[ -n ${MAIN_IPV6:-} && ${IPV6_MODE:-} != "disabled" ]]; then
    local ipv6_gw="${IPV6_GATEWAY:-fe80::1}"
    # Translate "auto" to link-local default (Hetzner standard)
    [[ $ipv6_gw == "auto" ]] && ipv6_gw="fe80::1"
    cat <<EOF

iface vmbr0 inet6 static
    address ${ipv6_addr}
    gateway ${ipv6_gw}
EOF
    # For /128 with non-link-local gateway, add explicit on-link route
    if [[ $ipv6_prefix == "128" && ! $ipv6_gw =~ ^fe80: ]]; then
      cat <<EOF
    up ip -6 route add ${ipv6_gw}/128 dev vmbr0
EOF
    fi
    cat <<EOF
    accept_ra 2
EOF
  fi
}

# Generates vmbr0 as NAT bridge (private network for VMs)
_generate_vmbr0_nat() {
  local mtu="${BRIDGE_MTU:-9000}"
  local private_ip="${PRIVATE_IP_CIDR:-10.0.0.1/24}"

  cat <<EOF
# vmbr0: Private NAT network for VMs
# All VMs connect here and access internet via NAT
# MTU ${mtu} (jumbo frames) for improved VM-to-VM performance
auto vmbr0
iface vmbr0 inet static
    address ${private_ip}
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    mtu ${mtu}
    # NAT masquerade handled by nftables (/etc/nftables.conf)
    # CT zone for Proxmox bridge tracking (required for VM networking)
    post-up   iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
    post-down iptables -t raw -D PREROUTING -i fwbr+ -j CT --zone 1 || true
EOF

  # Add IPv6 if enabled
  if [[ -n ${FIRST_IPV6_CIDR:-} && ${IPV6_MODE:-} != "disabled" ]]; then
    cat <<EOF

iface vmbr0 inet6 static
    address ${FIRST_IPV6_CIDR}
EOF
  fi
}

# Generates vmbr1 as secondary NAT bridge
_generate_vmbr1_nat() {
  local mtu="${BRIDGE_MTU:-9000}"
  local private_ip="${PRIVATE_IP_CIDR:-10.0.0.1/24}"

  cat <<EOF
# vmbr1: Private NAT network for VMs
# VMs connect here for isolated network with NAT to internet
# MTU ${mtu} (jumbo frames) for improved VM-to-VM performance
auto vmbr1
iface vmbr1 inet static
    address ${private_ip}
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    mtu ${mtu}
    # NAT masquerade handled by nftables (/etc/nftables.conf)
    # CT zone for Proxmox bridge tracking (required for VM networking)
    post-up   iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
    post-down iptables -t raw -D PREROUTING -i fwbr+ -j CT --zone 1 || true
EOF

  # Add IPv6 if enabled
  if [[ -n ${FIRST_IPV6_CIDR:-} && ${IPV6_MODE:-} != "disabled" ]]; then
    cat <<EOF

iface vmbr1 inet6 static
    address ${FIRST_IPV6_CIDR}
EOF
  fi
}
