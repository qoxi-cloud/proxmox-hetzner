# =============================================================================
# User input functions
# =============================================================================

# Helper to prompt or use existing value
prompt_or_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local current_value="${!var_name}"

    if [[ "$NON_INTERACTIVE" == true ]]; then
        if [[ -n "$current_value" ]]; then
            echo "$current_value"
        else
            echo "$default"
        fi
    else
        local result
        read -e -p "$prompt" -i "${current_value:-$default}" result
        echo "$result"
    fi
}

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

# =============================================================================
# Input collection - Non-interactive mode
# =============================================================================

get_inputs_non_interactive() {
    # Use defaults or config values
    PVE_HOSTNAME="${PVE_HOSTNAME:-pve-qoxi-cloud}"
    DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-local}"
    TIMEZONE="${TIMEZONE:-Europe/Kyiv}"
    EMAIL="${EMAIL:-admin@qoxi.cloud}"
    BRIDGE_MODE="${BRIDGE_MODE:-internal}"
    PRIVATE_SUBNET="${PRIVATE_SUBNET:-10.0.0.0/24}"

    # Display configuration
    print_success "Network interface: ${INTERFACE_NAME}"
    print_success "Hostname: ${PVE_HOSTNAME}"
    print_success "Domain: ${DOMAIN_SUFFIX}"
    print_success "Timezone: ${TIMEZONE}"
    print_success "Email: ${EMAIL}"
    print_success "Bridge mode: ${BRIDGE_MODE}"

    if [[ "$BRIDGE_MODE" == "internal" || "$BRIDGE_MODE" == "both" ]]; then
        print_success "Private subnet: ${PRIVATE_SUBNET}"
    fi

    # ZFS RAID mode
    if [[ -z "$ZFS_RAID" ]]; then
        if [[ "${NVME_COUNT:-0}" -ge 2 ]]; then
            ZFS_RAID="raid1"
        else
            ZFS_RAID="single"
        fi
    fi
    print_success "ZFS mode: ${ZFS_RAID}"

    # Password required
    if [[ -z "$NEW_ROOT_PASSWORD" ]]; then
        print_error "NEW_ROOT_PASSWORD required in non-interactive mode"
        exit 1
    fi
    if ! validate_password "$NEW_ROOT_PASSWORD"; then
        print_error "Password contains invalid characters (Cyrillic or non-ASCII)."
        exit 1
    fi

    # SSH Public Key
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        SSH_PUBLIC_KEY=$(get_rescue_ssh_key)
    fi
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        print_error "SSH_PUBLIC_KEY required in non-interactive mode"
        exit 1
    fi
    parse_ssh_key "$SSH_PUBLIC_KEY"
    print_success "SSH key configured (${SSH_KEY_TYPE})"

    # Tailscale
    INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-no}"
    if [[ "$INSTALL_TAILSCALE" == "yes" ]]; then
        TAILSCALE_SSH="${TAILSCALE_SSH:-yes}"
        TAILSCALE_WEBUI="${TAILSCALE_WEBUI:-yes}"
        if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
            print_success "Tailscale will be installed (auto-connect)"
        else
            print_success "Tailscale will be installed (manual auth required)"
        fi
        print_success "Tailscale SSH: ${TAILSCALE_SSH}"
        print_success "Tailscale WebUI: ${TAILSCALE_WEBUI}"
    else
        print_success "Tailscale: skipped"
    fi
}

# =============================================================================
# Input collection - Interactive mode
# =============================================================================

get_inputs_interactive() {
    # =========================================================================
    # SECTION 1: Text inputs
    # =========================================================================

    # Network interface
    print_warning "Use the predictable name (enp*, eno*) for bare metal, not eth0"
    local iface_prompt="Interface name (options: ${AVAILABLE_ALTNAMES}): "
    read -e -p "$iface_prompt" -i "$INTERFACE_NAME" INTERFACE_NAME
    printf "\033[A\r${CLR_GREEN}✓${CLR_RESET} ${iface_prompt}${INTERFACE_NAME}\033[K\n"

    # Hostname
    if [[ -n "$PVE_HOSTNAME" ]]; then
        print_success "Hostname: ${PVE_HOSTNAME} (from env)"
    else
        prompt_with_validation \
            "Enter your hostname (e.g., pve, proxmox): " \
            "pve-qoxi-cloud" \
            "validate_hostname" \
            "Invalid hostname. Use only letters, numbers, and hyphens (1-63 chars)." \
            "PVE_HOSTNAME"
    fi

    # Domain
    if [[ -n "$DOMAIN_SUFFIX" ]]; then
        print_success "Domain: ${DOMAIN_SUFFIX} (from env)"
    else
        local domain_prompt="Enter domain suffix: "
        read -e -p "$domain_prompt" -i "local" DOMAIN_SUFFIX
        printf "\033[A\r${CLR_GREEN}✓${CLR_RESET} ${domain_prompt}${DOMAIN_SUFFIX}\033[K\n"
    fi

    # Email
    if [[ -n "$EMAIL" ]]; then
        print_success "Email: ${EMAIL} (from env)"
    else
        prompt_with_validation \
            "Enter your email address: " \
            "admin@qoxi.cloud" \
            "validate_email" \
            "Invalid email address format." \
            "EMAIL"
    fi

    # Password
    if [[ -n "$NEW_ROOT_PASSWORD" ]]; then
        if ! validate_password "$NEW_ROOT_PASSWORD"; then
            print_error "Password contains invalid characters (Cyrillic or non-ASCII)."
            print_error "Only Latin letters, digits, and special characters are allowed."
            exit 1
        fi
        print_success "Password: ******** (from env)"
    else
        prompt_password "Enter your System New root password: " "NEW_ROOT_PASSWORD"
    fi

    # =========================================================================
    # SECTION 2: Interactive menus
    # =========================================================================

    # --- Timezone ---
    if [[ -n "$TIMEZONE" ]]; then
        print_success "Timezone: ${TIMEZONE} (from env)"
    else
        local tz_options=("Europe/Kyiv" "Europe/London" "Europe/Berlin" "America/New_York" "America/Los_Angeles" "Asia/Tokyo" "UTC" "custom")

        interactive_menu \
            "Timezone (↑/↓ select, Enter confirm)" \
            "" \
            "Europe/Kyiv|Ukraine" \
            "Europe/London|United Kingdom (GMT/BST)" \
            "Europe/Berlin|Germany, Central Europe (CET/CEST)" \
            "America/New_York|US Eastern Time (EST/EDT)" \
            "America/Los_Angeles|US Pacific Time (PST/PDT)" \
            "Asia/Tokyo|Japan Standard Time (JST)" \
            "UTC|Coordinated Universal Time" \
            "Custom|Enter timezone manually"

        if [[ $MENU_SELECTED -eq 7 ]]; then
            prompt_with_validation \
                "Enter your timezone: " \
                "Europe/Kyiv" \
                "validate_timezone" \
                "Invalid timezone. Use format like: Europe/London, America/New_York" \
                "TIMEZONE"
        else
            TIMEZONE="${tz_options[$MENU_SELECTED]}"
            print_success "Timezone: ${TIMEZONE}"
        fi
    fi

    # --- Bridge mode ---
    if [[ -n "$BRIDGE_MODE" ]]; then
        print_success "Bridge mode: ${BRIDGE_MODE} (from env)"
    else
        local bridge_options=("internal" "external" "both")
        local bridge_header="Configure network bridges for VMs and containers"$'\n'
        bridge_header+="vmbr0 = external (bridged to physical NIC)"$'\n'
        bridge_header+="vmbr1 = internal (NAT with private subnet)"

        interactive_menu \
            "Network Bridge Mode (↑/↓ select, Enter confirm)" \
            "$bridge_header" \
            "Internal only (NAT)|VMs use private IPs with NAT to internet" \
            "External only (Bridged)|VMs get IPs from your router/DHCP" \
            "Both bridges|Internal NAT + External bridged network"

        BRIDGE_MODE="${bridge_options[$MENU_SELECTED]}"
        case "$BRIDGE_MODE" in
            internal) print_success "Bridge mode: Internal NAT only (vmbr0)" ;;
            external) print_success "Bridge mode: External bridged only (vmbr0)" ;;
            both)     print_success "Bridge mode: Both (vmbr0=external, vmbr1=internal)" ;;
        esac
    fi

    # --- Private subnet ---
    if [[ "$BRIDGE_MODE" == "internal" || "$BRIDGE_MODE" == "both" ]]; then
        if [[ -n "$PRIVATE_SUBNET" ]]; then
            print_success "Private subnet: ${PRIVATE_SUBNET} (from env)"
        else
            local subnet_options=("10.0.0.0/24" "192.168.1.0/24" "172.16.0.0/24" "custom")

            interactive_menu \
                "Private Subnet (↑/↓ select, Enter confirm)" \
                "Internal network for VMs and containers" \
                "10.0.0.0/24|Class A private (recommended)" \
                "192.168.1.0/24|Class C private (common home network)" \
                "172.16.0.0/24|Class B private" \
                "Custom|Enter subnet manually"

            if [[ $MENU_SELECTED -eq 3 ]]; then
                prompt_with_validation \
                    "Enter your private subnet: " \
                    "10.0.0.0/24" \
                    "validate_subnet" \
                    "Invalid subnet. Use CIDR format like: 10.0.0.0/24" \
                    "PRIVATE_SUBNET"
            else
                PRIVATE_SUBNET="${subnet_options[$MENU_SELECTED]}"
                print_success "Private subnet: ${PRIVATE_SUBNET}"
            fi
        fi
    fi

    # --- ZFS RAID mode ---
    if [[ "${NVME_COUNT:-0}" -ge 2 ]]; then
        if [[ -n "$ZFS_RAID" ]]; then
            print_success "ZFS mode: ${ZFS_RAID} (from env)"
        else
            local zfs_options=("raid1" "raid0" "single")
            local zfs_labels=("RAID-1 (mirror) - Recommended" "RAID-0 (stripe) - No redundancy" "Single drive - No redundancy")

            interactive_menu \
                "ZFS Storage Mode (↑/↓ select, Enter confirm)" \
                "" \
                "${zfs_labels[0]}|Survives 1 disk failure" \
                "${zfs_labels[1]}|2x space & speed, data loss if any disk fails" \
                "${zfs_labels[2]}|Uses first drive only, ignores other drives"

            ZFS_RAID="${zfs_options[$MENU_SELECTED]}"
            print_success "ZFS mode: ${zfs_labels[$MENU_SELECTED]}"
        fi
    fi

    # --- SSH Public Key ---
    if [[ -n "$SSH_PUBLIC_KEY" ]]; then
        parse_ssh_key "$SSH_PUBLIC_KEY"
        print_success "SSH key: ${SSH_KEY_TYPE} (from env)"
    else
        local DETECTED_SSH_KEY=$(get_rescue_ssh_key)

        if [[ -n "$DETECTED_SSH_KEY" ]]; then
            parse_ssh_key "$DETECTED_SSH_KEY"

            local ssh_header="! Password authentication will be DISABLED"$'\n'
            ssh_header+="Detected key from Rescue System:"$'\n'
            ssh_header+="  Type:    ${SSH_KEY_TYPE}"$'\n'
            ssh_header+="  Key:     ${SSH_KEY_SHORT}"
            if [[ -n "$SSH_KEY_COMMENT" ]]; then
                ssh_header+=$'\n'"  Comment: ${SSH_KEY_COMMENT}"
            fi

            interactive_menu \
                "SSH Public Key (↑/↓ select, Enter confirm)" \
                "$ssh_header" \
                "Use detected key|Recommended - already configured in Hetzner" \
                "Enter different key|Paste your own SSH public key"

            if [[ $MENU_SELECTED -eq 0 ]]; then
                SSH_PUBLIC_KEY="$DETECTED_SSH_KEY"
                print_success "SSH key configured (${SSH_KEY_TYPE})"
            else
                SSH_PUBLIC_KEY=""
            fi
        fi

        # Manual entry if no key yet
        if [[ -z "$SSH_PUBLIC_KEY" ]]; then
            local ssh_content="! Password authentication will be DISABLED"$'\n'
            if [[ -z "$DETECTED_SSH_KEY" ]]; then
                ssh_content+=$'\n'"No SSH key detected in Rescue System."
            fi
            ssh_content+=$'\n'$'\n'"Paste your SSH public key below:"$'\n'
            ssh_content+="(Usually from ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)"

            input_box "SSH Public Key Configuration" "$ssh_content" "SSH Public Key: " ""

            while [[ -z "$INPUT_VALUE" ]] || ! validate_ssh_key "$INPUT_VALUE"; do
                if [[ -z "$INPUT_VALUE" ]]; then
                    print_error "SSH public key is required for secure access!"
                else
                    print_warning "SSH key format may be invalid. Continue anyway? (y/n): "
                    read -rsn1 confirm
                    echo ""
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        break
                    fi
                fi
                input_box "SSH Public Key Configuration" "$ssh_content" "SSH Public Key: " ""
            done

            SSH_PUBLIC_KEY="$INPUT_VALUE"
            parse_ssh_key "$SSH_PUBLIC_KEY"
            print_success "SSH key configured (${SSH_KEY_TYPE})"
        fi
    fi

    # --- Tailscale ---
    if [[ -n "$INSTALL_TAILSCALE" ]]; then
        if [[ "$INSTALL_TAILSCALE" == "yes" ]]; then
            TAILSCALE_SSH="${TAILSCALE_SSH:-yes}"
            TAILSCALE_WEBUI="${TAILSCALE_WEBUI:-yes}"
            if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
                print_success "Tailscale: yes (auto-connect, from env)"
            else
                print_success "Tailscale: yes (manual auth, from env)"
            fi
        else
            TAILSCALE_AUTH_KEY=""
            TAILSCALE_SSH="no"
            TAILSCALE_WEBUI="no"
            print_success "Tailscale: skipped (from env)"
        fi
    else
        local ts_header="Tailscale provides secure remote access to your server."$'\n'
        ts_header+="Auth key: https://login.tailscale.com/admin/settings/keys"

        interactive_menu \
            "Tailscale VPN - Optional (↑/↓ select, Enter confirm)" \
            "$ts_header" \
            "Install Tailscale|Recommended for secure remote access" \
            "Skip installation|Install Tailscale later if needed"

        if [[ $MENU_SELECTED -eq 0 ]]; then
            INSTALL_TAILSCALE="yes"
            TAILSCALE_SSH="yes"
            TAILSCALE_WEBUI="yes"

            if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
                local auth_content="Auth key enables automatic configuration."$'\n'
                auth_content+="Leave empty for manual auth after reboot."$'\n'
                auth_content+=$'\n'
                auth_content+="For unattended setup, use a reusable auth key"$'\n'
                auth_content+="with tags and expiry for better security."

                input_box "Tailscale Auth Key (optional)" "$auth_content" "Auth Key: " ""
                TAILSCALE_AUTH_KEY="$INPUT_VALUE"
            fi

            if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
                print_success "Tailscale will be installed (auto-connect)"
            else
                print_success "Tailscale will be installed (manual auth required)"
            fi
        else
            INSTALL_TAILSCALE="no"
            TAILSCALE_AUTH_KEY=""
            TAILSCALE_SSH="no"
            TAILSCALE_WEBUI="no"
            print_success "Tailscale installation skipped"
        fi
    fi
}

# =============================================================================
# Main input collection function
# =============================================================================

get_system_inputs() {
    detect_network_interface

    if [[ "$NON_INTERACTIVE" == true ]]; then
        print_success "Network interface: ${INTERFACE_NAME}"
        get_inputs_non_interactive
    else
        get_inputs_interactive
    fi

    collect_network_info

    # Calculate derived values
    FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"

    # Calculate private network values
    if [[ "$BRIDGE_MODE" == "internal" || "$BRIDGE_MODE" == "both" ]]; then
        PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
        PRIVATE_IP="${PRIVATE_CIDR}.1"
        SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
        PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
    fi

    # Save config if requested
    if [[ -n "$SAVE_CONFIG" ]]; then
        save_config "$SAVE_CONFIG"
    fi
}
