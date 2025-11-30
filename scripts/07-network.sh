# shellcheck shell=bash
# =============================================================================
# Network interface detection
# =============================================================================

detect_network_interface() {
    # Get default interface name (the one with default route)
    CURRENT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$CURRENT_INTERFACE" ]]; then
        CURRENT_INTERFACE="eth0"
    fi

    # CRITICAL: Get the predictable interface name for bare metal
    # Rescue System often uses eth0, but Proxmox uses predictable naming
    PREDICTABLE_NAME=""

    # Try to get predictable name from udev
    if [[ -e "/sys/class/net/${CURRENT_INTERFACE}" ]]; then
        # Try ID_NET_NAME_PATH first (most reliable for PCIe devices)
        PREDICTABLE_NAME=$(udevadm info "/sys/class/net/${CURRENT_INTERFACE}" 2>/dev/null | grep "ID_NET_NAME_PATH=" | cut -d'=' -f2)

        # Fallback to ID_NET_NAME_ONBOARD (for onboard NICs)
        if [[ -z "$PREDICTABLE_NAME" ]]; then
            PREDICTABLE_NAME=$(udevadm info "/sys/class/net/${CURRENT_INTERFACE}" 2>/dev/null | grep "ID_NET_NAME_ONBOARD=" | cut -d'=' -f2)
        fi

        # Fallback to altname from ip link
        if [[ -z "$PREDICTABLE_NAME" ]]; then
            PREDICTABLE_NAME=$(ip -d link show "$CURRENT_INTERFACE" 2>/dev/null | grep "altname" | awk '{print $2}' | head -1)
        fi
    fi

    # Use predictable name if found
    if [[ -n "$PREDICTABLE_NAME" ]]; then
        DEFAULT_INTERFACE="$PREDICTABLE_NAME"
        print_success "Detected predictable interface name: ${PREDICTABLE_NAME} (current: ${CURRENT_INTERFACE})"
    else
        DEFAULT_INTERFACE="$CURRENT_INTERFACE"
        print_warning "Could not detect predictable interface name"
        print_warning "Using current interface: ${CURRENT_INTERFACE}"
        print_warning "Proxmox might use different interface name - check after installation"
    fi

    # Get all available interfaces and their altnames for display
    AVAILABLE_ALTNAMES=$(ip -d link show | grep -v "lo:" | grep -E '(^[0-9]+:|altname)' | awk '/^[0-9]+:/ {interface=$2; gsub(/:/, "", interface); printf "%s", interface} /altname/ {printf ", %s", $2} END {print ""}' | sed 's/, $//')

    # Set INTERFACE_NAME to default if not already set
    if [[ -z "$INTERFACE_NAME" ]]; then
        INTERFACE_NAME="$DEFAULT_INTERFACE"
    fi
}

# Get network information from current interface
collect_network_info() {
    # Retry network info collection (network may be unstable in rescue mode)
    local max_attempts=3
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        attempt=$((attempt + 1))
        
        MAIN_IPV4_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null | grep global | grep "inet " | xargs | cut -d" " -f2)
        MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
        MAIN_IPV4_GW=$(ip route 2>/dev/null | grep default | xargs | cut -d" " -f3)
        
        if [[ -n "$MAIN_IPV4" ]] && [[ -n "$MAIN_IPV4_GW" ]]; then
            break
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "Network info attempt $attempt failed, retrying in 2 seconds..."
            sleep 2
        fi
    done
    
    MAC_ADDRESS=$(ip link show "$CURRENT_INTERFACE" 2>/dev/null | awk '/ether/ {print $2}')
    IPV6_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null | grep global | grep "inet6 " | xargs | cut -d" " -f2)
    MAIN_IPV6="${IPV6_CIDR%/*}"

    # Validate network configuration with detailed error messages
    if [[ -z "$MAIN_IPV4" ]] || [[ -z "$MAIN_IPV4_GW" ]]; then
        print_error "Failed to detect network configuration"
        print_error "Interface: $CURRENT_INTERFACE"
        print_error "Available interfaces:"
        ip link show 2>/dev/null | grep -E "^[0-9]+:" | awk '{print "  " $2}' >&2 || true
        log "ERROR: MAIN_IPV4=$MAIN_IPV4, MAIN_IPV4_GW=$MAIN_IPV4_GW"
        exit 1
    fi

    # Validate IPv4 address format
    if ! [[ "$MAIN_IPV4" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid IPv4 address format: $MAIN_IPV4"
        log "ERROR: Invalid IPv4 address: $MAIN_IPV4"
        exit 1
    fi

    # Validate gateway format
    if ! [[ "$MAIN_IPV4_GW" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid gateway address format: $MAIN_IPV4_GW"
        log "ERROR: Invalid gateway address: $MAIN_IPV4_GW"
        exit 1
    fi
    
    # Check gateway reachability (may be normal in rescue mode, so warning only)
    if ! ping -c 1 -W 2 "$MAIN_IPV4_GW" > /dev/null 2>&1; then
        print_warning "Gateway $MAIN_IPV4_GW is not reachable (may be normal in rescue mode)"
        log "WARNING: Gateway $MAIN_IPV4_GW not reachable"
    fi

    # Set a default value for FIRST_IPV6_CIDR
    if [[ -n "$IPV6_CIDR" ]]; then
        # Extract first 4 groups of IPv6 using parameter expansion
        local ipv6_prefix="${MAIN_IPV6%%:*:*:*:*}"
        # Fallback: if expansion didn't work as expected, use cut
        if [[ "$ipv6_prefix" == "$MAIN_IPV6" ]] || [[ -z "$ipv6_prefix" ]]; then
            ipv6_prefix=$(printf '%s' "$MAIN_IPV6" | cut -d':' -f1-4)
        fi
        FIRST_IPV6_CIDR="${ipv6_prefix}:1::1/80"
    else
        FIRST_IPV6_CIDR=""
    fi
}
