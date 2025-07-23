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
        print_warning "Could not detect predictable name, using: ${CURRENT_INTERFACE}"
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
    MAIN_IPV4_CIDR=$(ip address show "$CURRENT_INTERFACE" | grep global | grep "inet " | xargs | cut -d" " -f2)
    MAIN_IPV4=$(echo "$MAIN_IPV4_CIDR" | cut -d'/' -f1)
    MAIN_IPV4_GW=$(ip route | grep default | xargs | cut -d" " -f3)
    MAC_ADDRESS=$(ip link show "$CURRENT_INTERFACE" | awk '/ether/ {print $2}')
    IPV6_CIDR=$(ip address show "$CURRENT_INTERFACE" | grep global | grep "inet6 " | xargs | cut -d" " -f2)
    MAIN_IPV6=$(echo "$IPV6_CIDR" | cut -d'/' -f1)

    # Set a default value for FIRST_IPV6_CIDR
    if [[ -n "$IPV6_CIDR" ]]; then
        FIRST_IPV6_CIDR="$(echo "$IPV6_CIDR" | cut -d'/' -f1 | cut -d':' -f1-4):1::1/80"
    else
        FIRST_IPV6_CIDR=""
    fi
}
