# shellcheck shell=bash
# =============================================================================
# Tailscale VPN configuration
# =============================================================================

# Configures Tailscale VPN with SSH and Web UI access.
# Optionally authenticates with auth key and enables stealth mode.
# Side effects: Installs and configures Tailscale on remote system
configure_tailscale() {
  if [[ $INSTALL_TAILSCALE != "yes" ]]; then
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

  # If auth key is provided, authenticate Tailscale
  if [[ -n $TAILSCALE_AUTH_KEY ]]; then
    # Use unique temporary files to avoid race conditions
    local tmp_ip tmp_hostname
    tmp_ip=$(mktemp)
    tmp_hostname=$(mktemp)

    # Ensure cleanup on function exit (handles errors too)
    # shellcheck disable=SC2064
    trap "rm -f '$tmp_ip' '$tmp_hostname'" RETURN

    # Build and execute tailscale up command with proper quoting
    (
      if [[ $TAILSCALE_SSH == "yes" ]]; then
        remote_exec "tailscale up --authkey='$TAILSCALE_AUTH_KEY' --ssh" || exit 1
      else
        remote_exec "tailscale up --authkey='$TAILSCALE_AUTH_KEY'" || exit 1
      fi
      # Get IP and hostname in one call using tailscale status --json
      remote_exec "tailscale status --json | jq -r '[(.Self.TailscaleIPs[0] // \"pending\"), (.Self.DNSName // \"\" | rtrimstr(\".\"))] | @tsv'" 2>/dev/null | {
        IFS=$'\t' read -r ip hostname
        echo "$ip" >"$tmp_ip"
        echo "$hostname" >"$tmp_hostname"
      } || true
    ) >/dev/null 2>&1 &
    show_progress $! "Authenticating Tailscale"

    # Get Tailscale IP and hostname for display
    TAILSCALE_IP=$(cat "$tmp_ip" 2>/dev/null || echo "pending")
    TAILSCALE_HOSTNAME=$(cat "$tmp_hostname" 2>/dev/null || echo "")
    # Overwrite completion line with IP
    printf "\033[1A\r%s✓ Tailscale authenticated. IP: %s%s                              \n" "${CLR_CYAN}" "${TAILSCALE_IP}" "${CLR_RESET}"

    # Configure Tailscale Serve for Proxmox Web UI
    if [[ $TAILSCALE_WEBUI == "yes" ]]; then
      remote_exec "tailscale serve --bg --https=443 https://127.0.0.1:8006" >/dev/null 2>&1 &
      show_progress $! "Configuring Tailscale Serve" "Proxmox Web UI available via Tailscale Serve"
    fi

    # Deploy OpenSSH disable service if requested (already downloaded in make_templates)
    if [[ $TAILSCALE_SSH == "yes" && $TAILSCALE_DISABLE_SSH == "yes" ]]; then
      log "Deploying disable-openssh.service (TAILSCALE_SSH=$TAILSCALE_SSH, TAILSCALE_DISABLE_SSH=$TAILSCALE_DISABLE_SSH)"
      (
        log "Using pre-downloaded disable-openssh.service, size: $(wc -c <./templates/disable-openssh.service 2>/dev/null || echo 'failed')"
        remote_copy "templates/disable-openssh.service" "/etc/systemd/system/disable-openssh.service" || exit 1
        log "Copied disable-openssh.service to VM"
        remote_exec "systemctl daemon-reload && systemctl enable disable-openssh.service" >/dev/null 2>&1 || exit 1
        log "Enabled disable-openssh.service"
      ) &
      show_progress $! "Configuring OpenSSH disable on boot" "OpenSSH disable configured"
    else
      log "Skipping disable-openssh.service (TAILSCALE_SSH=$TAILSCALE_SSH, TAILSCALE_DISABLE_SSH=$TAILSCALE_DISABLE_SSH)"
    fi

    # Deploy stealth firewall if requested (already downloaded in make_templates)
    if [[ $STEALTH_MODE == "yes" ]]; then
      log "Deploying stealth-firewall.service (STEALTH_MODE=$STEALTH_MODE)"
      (
        log "Using pre-downloaded stealth-firewall.service, size: $(wc -c <./templates/stealth-firewall.service 2>/dev/null || echo 'failed')"
        remote_copy "templates/stealth-firewall.service" "/etc/systemd/system/stealth-firewall.service" || exit 1
        log "Copied stealth-firewall.service to VM"
        remote_exec "systemctl daemon-reload && systemctl enable stealth-firewall.service" >/dev/null 2>&1 || exit 1
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
