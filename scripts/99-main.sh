# shellcheck shell=bash
# =============================================================================
# Finish and reboot
# =============================================================================

# Function to reboot into the main OS
reboot_to_main_os() {
    local inner_width=$((MENU_BOX_WIDTH - 6))

    # Build summary content
    local summary=""

    # Calculate duration
    local end_time total_seconds duration
    end_time=$(date +%s)
    total_seconds=$((end_time - INSTALL_START_TIME))
    duration=$(format_duration $total_seconds)

    summary+="[OK]|Installation time|${duration}"$'\n'
    summary+="|--- Security ---|"$'\n'
    summary+="[OK]|SSH public key|deployed"$'\n'
    summary+="[OK]|Password auth|DISABLED"$'\n'
    summary+="[OK]|CPU governor|performance"$'\n'
    summary+="[OK]|Kernel params|optimized"$'\n'

    # Repository info
    case "${PVE_REPO_TYPE:-no-subscription}" in
        enterprise)
            summary+="[OK]|Repository|enterprise"$'\n'
            if [[ -n "$PVE_SUBSCRIPTION_KEY" ]]; then
                summary+="[OK]|Subscription|registered"$'\n'
            else
                summary+="[WARN]|Subscription|key not provided"$'\n'
            fi
            ;;
        test)
            summary+="[WARN]|Repository|test (unstable)"$'\n'
            summary+="[OK]|Subscription notice|removed"$'\n'
            ;;
        *)
            summary+="[OK]|Repository|no-subscription"$'\n'
            summary+="[OK]|Subscription notice|removed"$'\n'
            ;;
    esac

    # SSL certificate info
    if [[ "$SSL_TYPE" == "letsencrypt" ]]; then
        summary+="[OK]|SSL certificate|Let's Encrypt (on first boot)"$'\n'
        summary+="[OK]|SSL auto-renewal|enabled"$'\n'
    else
        summary+="[OK]|SSL certificate|self-signed"$'\n'
    fi

    summary+="|--- Optimizations ---|"$'\n'
    summary+="[OK]|Monitoring tools|btop, iotop, ncdu, tmux..."$'\n'
    summary+="[OK]|VM image tools|libguestfs-tools"$'\n'
    summary+="[OK]|ZFS ARC limits|configured"$'\n'
    summary+="[OK]|nf_conntrack|optimized"$'\n'
    summary+="[OK]|NTP sync|chrony (Hetzner)"$'\n'
    summary+="[OK]|Dynamic MOTD|enabled"$'\n'
    summary+="[OK]|Security updates|unattended"$'\n'

    # Tailscale status
    if [[ "$INSTALL_TAILSCALE" == "yes" ]]; then
        summary+="[OK]|Tailscale VPN|installed"$'\n'
        if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
            summary+="[OK]|Tailscale IP|${TAILSCALE_IP:-pending}"$'\n'
        else
            summary+="[WARN]|Tailscale|needs auth after reboot"$'\n'
        fi
    fi

    summary+="|--- Access ---|"$'\n'

    # Show generated password if applicable
    if [[ "$PASSWORD_GENERATED" == "yes" ]]; then
        summary+="[WARN]|Root password|${NEW_ROOT_PASSWORD}"$'\n'
    fi

    # Show access methods based on stealth mode and OpenSSH status
    if [[ "$STEALTH_MODE" == "yes" ]]; then
        # Stealth mode: only Tailscale access shown
        summary+="[WARN]|Public IP|BLOCKED (stealth mode)"$'\n'
        if [[ "$TAILSCALE_DISABLE_SSH" == "yes" ]]; then
            summary+="[WARN]|OpenSSH|DISABLED after first boot"
        fi
        if [[ "$INSTALL_TAILSCALE" == "yes" && -n "$TAILSCALE_AUTH_KEY" && "$TAILSCALE_IP" != "pending" && "$TAILSCALE_IP" != "not authenticated" ]]; then
            summary+=$'\n'"[OK]|Tailscale SSH|root@${TAILSCALE_IP}"
            if [[ -n "$TAILSCALE_HOSTNAME" ]]; then
                summary+=$'\n'"[OK]|Tailscale Web|https://${TAILSCALE_HOSTNAME}"
            else
                summary+=$'\n'"[OK]|Tailscale Web|https://${TAILSCALE_IP}:8006"
            fi
        fi
    else
        # Normal mode: public IP access
        summary+="[OK]|Web UI|https://${MAIN_IPV4_CIDR%/*}:8006"$'\n'
        summary+="[OK]|SSH|root@${MAIN_IPV4_CIDR%/*}"
        if [[ "$INSTALL_TAILSCALE" == "yes" && -n "$TAILSCALE_AUTH_KEY" && "$TAILSCALE_IP" != "pending" && "$TAILSCALE_IP" != "not authenticated" ]]; then
            summary+=$'\n'"[OK]|Tailscale SSH|root@${TAILSCALE_IP}"
            if [[ -n "$TAILSCALE_HOSTNAME" ]]; then
                summary+=$'\n'"[OK]|Tailscale Web|https://${TAILSCALE_HOSTNAME}"
            else
                summary+=$'\n'"[OK]|Tailscale Web|https://${TAILSCALE_IP}:8006"
            fi
        fi
    fi

    # Display ASCII art header (centered for MENU_BOX_WIDTH=60)
    echo -e "${CLR_CYAN}"
    cat << 'BANNER'
               ____
              / ___| _   _  ___ ___ ___  ___ ___
              \___ \| | | |/ __/ __/ _ \/ __/ __|
               ___) | |_| | (_| (_|  __/\__ \__ \
              |____/ \__,_|\___\___\___||___/___/
BANNER
    echo -e "${CLR_RESET}"

    # Display with boxes
    {
        echo "INSTALLATION SUMMARY"
        echo "$summary" | column -t -s '|' | while IFS= read -r line; do
            printf "%-${inner_width}s\n" "$line"
        done
    } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH | colorize_status
    echo ""

    # Show Tailscale auth instructions if needed
    if [[ "$INSTALL_TAILSCALE" == "yes" && -z "$TAILSCALE_AUTH_KEY" ]]; then
        print_warning "Tailscale needs authentication after reboot:"
        echo "    tailscale up --ssh"
        echo "    tailscale serve --bg --https=443 https://127.0.0.1:8006"
        echo ""
    fi

    # Ask user to reboot the system
    read -e -p "Do you want to reboot the system? (y/n): " -i "y" REBOOT
    if [[ "$REBOOT" == "y" ]]; then
        print_info "Rebooting the system..."
        reboot
    else
        print_info "Exiting..."
        exit 0
    fi
}

# =============================================================================
# Main execution flow
# =============================================================================

log "=========================================="
log "Proxmox VE Automated Installer v${VERSION}"
log "=========================================="
log "TEST_MODE=$TEST_MODE"
log "NON_INTERACTIVE=$NON_INTERACTIVE"
log "CONFIG_FILE=$CONFIG_FILE"
log "VALIDATE_ONLY=$VALIDATE_ONLY"
log "QEMU_RAM_OVERRIDE=$QEMU_RAM_OVERRIDE"
log "QEMU_CORES_OVERRIDE=$QEMU_CORES_OVERRIDE"
log "PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
log "SSL_TYPE=${SSL_TYPE:-self-signed}"

# Collect system info and display status
log "Step: collect_system_info"
collect_system_info
log "Step: show_system_status"
show_system_status
log "Step: get_system_inputs"
get_system_inputs

# If validate-only mode, show summary and exit
if [[ "$VALIDATE_ONLY" == true ]]; then
    log "Validate-only mode: showing configuration summary"
    echo ""
    echo -e "${CLR_GREEN}✓ Configuration validated successfully${CLR_RESET}"
    echo ""
    echo "Configuration Summary:"
    echo "  Hostname:     $HOSTNAME"
    echo "  FQDN:         $FQDN"
    echo "  Email:        $EMAIL"
    echo "  Timezone:     $TIMEZONE"
    echo "  IPv4:         $MAIN_IPV4_CIDR"
    echo "  Gateway:      $MAIN_IPV4_GW"
    echo "  Interface:    $INTERFACE_NAME"
    echo "  ZFS Mode:     $ZFS_RAID_MODE"
    echo "  Drives:       ${DRIVES[*]}"
    echo "  Bridge Mode:  $BRIDGE_MODE"
    if [[ "$BRIDGE_MODE" != "external" ]]; then
        echo "  Private Net:  $PRIVATE_SUBNET"
    fi
    echo "  Tailscale:    $INSTALL_TAILSCALE"
    echo "  Repository:   ${PVE_REPO_TYPE:-no-subscription}"
    echo "  SSL:          ${SSL_TYPE:-self-signed}"
    if [[ -n "$PROXMOX_ISO_VERSION" ]]; then
        echo "  Proxmox ISO:  ${PROXMOX_ISO_VERSION}"
    else
        echo "  Proxmox ISO:  latest"
    fi
    if [[ -n "$QEMU_RAM_OVERRIDE" ]]; then
        echo "  QEMU RAM:     ${QEMU_RAM_OVERRIDE}MB (override)"
    fi
    if [[ -n "$QEMU_CORES_OVERRIDE" ]]; then
        echo "  QEMU Cores:   ${QEMU_CORES_OVERRIDE} (override)"
    fi
    echo ""
    echo -e "${CLR_CYAN}Run without --validate to start installation${CLR_RESET}"
    exit 0
fi

log "Step: prepare_packages"
prepare_packages
log "Step: download_proxmox_iso"
download_proxmox_iso
log "Step: make_answer_toml"
make_answer_toml
log "Step: make_autoinstall_iso"
make_autoinstall_iso
log "Step: install_proxmox"
install_proxmox

# Boot and configure via SSH
log "Step: boot_proxmox_with_port_forwarding"
boot_proxmox_with_port_forwarding || {
    log "ERROR: Failed to boot Proxmox with port forwarding"
    exit 1
}

# Configure Proxmox via SSH
log "Step: configure_proxmox_via_ssh"
configure_proxmox_via_ssh

# Mark installation as completed (disables error handler message)
INSTALL_COMPLETED=true

# Reboot to the main OS
log "Step: reboot_to_main_os"
reboot_to_main_os
