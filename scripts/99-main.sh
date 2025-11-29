# =============================================================================
# Finish and reboot
# =============================================================================

# Function to reboot into the main OS
reboot_to_main_os() {
    local inner_width=$((MENU_BOX_WIDTH - 6))

    # Build summary content
    local summary=""

    # Calculate duration
    local end_time=$(date +%s)
    local total_seconds=$((end_time - INSTALL_START_TIME))
    local duration=$(format_duration $total_seconds)

    summary+="[OK]|Installation time|${duration}"$'\n'
    summary+="|--- Security ---|"$'\n'
    summary+="[OK]|SSH public key|deployed"$'\n'
    summary+="[OK]|Password auth|DISABLED"$'\n'
    summary+="[OK]|CPU governor|performance"$'\n'
    summary+="[OK]|Kernel params|optimized"$'\n'
    summary+="[OK]|Subscription notice|removed"$'\n'
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

    # Display ASCII art header (centered for MENU_BOX_WIDTH=60)
    echo ""
    echo '      ___                      _      _         _ _'
    echo '     / __|___ _ __  _ __  ___ | |__ _| |_ ___  | | |'
    echo '    | (__/ _ \  _ \|  _ \/ _ \| / _` |  _/ -_) |_|_|'
    echo '     \___\___/_|_|_|| .__/\___/|_\__,_|\__\___|(_|_)'
    echo '                    |_|'
    echo ""

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

# Collect system info and display status
collect_system_info
show_system_status
get_system_inputs
prepare_packages
download_proxmox_iso
make_answer_toml
make_autoinstall_iso
install_proxmox

# Boot and configure via SSH
boot_proxmox_with_port_forwarding || {
    print_error "Failed to boot Proxmox with port forwarding. Exiting."
    exit 1
}

# Configure Proxmox via SSH
configure_proxmox_via_ssh

# Reboot to the main OS
reboot_to_main_os
