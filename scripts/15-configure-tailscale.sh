# shellcheck shell=bash
# =============================================================================
# Tailscale VPN configuration
# =============================================================================

configure_tailscale() {
    if [[ "$INSTALL_TAILSCALE" != "yes" ]]; then
        return 0
    fi

    run_remote "Installing Tailscale VPN" '
        curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
        apt-get update -qq
        apt-get install -yqq tailscale
        systemctl enable tailscaled
        systemctl start tailscaled
    ' "Tailscale VPN installed"

    # Build tailscale up command with selected options
    TAILSCALE_UP_CMD="tailscale up"
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        TAILSCALE_UP_CMD="$TAILSCALE_UP_CMD --authkey='$TAILSCALE_AUTH_KEY'"
    fi
    if [[ "$TAILSCALE_SSH" == "yes" ]]; then
        TAILSCALE_UP_CMD="$TAILSCALE_UP_CMD --ssh"
    fi

    # If auth key is provided, authenticate Tailscale
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        (
            remote_exec "$TAILSCALE_UP_CMD"
            remote_exec "tailscale ip -4" > /tmp/tailscale_ip.txt 2>/dev/null
            remote_exec "tailscale status --json | grep -o '\"DNSName\":\"[^\"]*\"' | head -1 | cut -d'\"' -f4 | sed 's/\\.$//' " > /tmp/tailscale_hostname.txt 2>/dev/null
        ) > /dev/null 2>&1 &
        show_progress $! "Authenticating Tailscale"

        # Get Tailscale IP and hostname for display
        TAILSCALE_IP=$(cat /tmp/tailscale_ip.txt 2>/dev/null || echo "pending")
        TAILSCALE_HOSTNAME=$(cat /tmp/tailscale_hostname.txt 2>/dev/null || echo "")
        rm -f /tmp/tailscale_ip.txt /tmp/tailscale_hostname.txt
        # Overwrite completion line with IP
        printf "\033[1A\r${CLR_GREEN}✓ Tailscale authenticated. IP: ${TAILSCALE_IP}${CLR_RESET}                              \n"

        # Configure Tailscale Serve for Proxmox Web UI
        if [[ "$TAILSCALE_WEBUI" == "yes" ]]; then
            remote_exec "tailscale serve --bg --https=443 https://127.0.0.1:8006" > /dev/null 2>&1 &
            show_progress $! "Configuring Tailscale Serve" "Proxmox Web UI available via Tailscale Serve"
        fi

        # Deploy OpenSSH disable service if requested
        if [[ "$TAILSCALE_SSH" == "yes" && "$TAILSCALE_DISABLE_SSH" == "yes" ]]; then
            log "Deploying disable-openssh.service (TAILSCALE_SSH=$TAILSCALE_SSH, TAILSCALE_DISABLE_SSH=$TAILSCALE_DISABLE_SSH)"
            (
                download_template "./templates/disable-openssh.service"
                log "Downloaded disable-openssh.service, size: $(wc -c < ./templates/disable-openssh.service 2>/dev/null || echo 'failed')"
                remote_copy "templates/disable-openssh.service" "/etc/systemd/system/disable-openssh.service"
                log "Copied disable-openssh.service to VM"
                remote_exec "systemctl daemon-reload && systemctl enable disable-openssh.service" > /dev/null 2>&1
                log "Enabled disable-openssh.service"
            ) &
            show_progress $! "Configuring OpenSSH disable on boot" "OpenSSH disable configured"
        else
            log "Skipping disable-openssh.service (TAILSCALE_SSH=$TAILSCALE_SSH, TAILSCALE_DISABLE_SSH=$TAILSCALE_DISABLE_SSH)"
        fi

        # Deploy stealth firewall if requested
        if [[ "$STEALTH_MODE" == "yes" ]]; then
            log "Deploying stealth-firewall.service (STEALTH_MODE=$STEALTH_MODE)"
            (
                download_template "./templates/stealth-firewall.service"
                log "Downloaded stealth-firewall.service, size: $(wc -c < ./templates/stealth-firewall.service 2>/dev/null || echo 'failed')"
                remote_copy "templates/stealth-firewall.service" "/etc/systemd/system/stealth-firewall.service"
                log "Copied stealth-firewall.service to VM"
                remote_exec "systemctl daemon-reload && systemctl enable stealth-firewall.service" > /dev/null 2>&1
                log "Enabled stealth-firewall.service"
            ) &
            show_progress $! "Configuring stealth firewall" "Stealth firewall configured"
        else
            log "Skipping stealth-firewall.service (STEALTH_MODE=$STEALTH_MODE)"
        fi
    else
        TAILSCALE_IP="not authenticated"
        TAILSCALE_HOSTNAME=""
        print_warning "Tailscale installed but not authenticated."
        print_info "After reboot, run these commands to enable SSH and Web UI:"
        print_info "  tailscale up --ssh"
        print_info "  tailscale serve --bg --https=443 https://127.0.0.1:8006"
    fi
}
