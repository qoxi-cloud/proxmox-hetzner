# shellcheck shell=bash
# =============================================================================
# Tailscale VPN configuration
# =============================================================================

# Configures Tailscale VPN with SSH and Web UI access.
# Optionally authenticates with auth key and enables stealth mode.
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# Side effects: Configures Tailscale on remote system
configure_tailscale() {
  if [[ $INSTALL_TAILSCALE != "yes" ]]; then
    return 0
  fi

  # Start tailscaled (package already installed via batch_install_packages)
  run_remote "Starting Tailscale" '
        systemctl enable tailscaled
        systemctl start tailscaled
        # Wait for tailscaled socket to be ready (up to 3s)
        for i in {1..3}; do
          tailscale status &>/dev/null && break
          sleep 1
        done
    ' "Tailscale started"

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

    # Update log with IP info
    if [[ $LIVE_LOGS_ACTIVE == true ]]; then
      LOG_LINES[TASK_INDEX]="${CLR_GRAY}├─${CLR_RESET} Tailscale authenticated. IP: ${TAILSCALE_IP} ${CLR_CYAN}✓${CLR_RESET}"
      render_logs
    else
      printf "\033[1A\r%s✓ Tailscale authenticated. IP: %s%s                              \n" "${CLR_CYAN}" "${TAILSCALE_IP}" "${CLR_RESET}"
    fi

    # Configure Tailscale Serve for Proxmox Web UI
    if [[ $TAILSCALE_WEBUI == "yes" ]]; then
      remote_exec "tailscale serve --bg --https=443 https://127.0.0.1:8006" >/dev/null 2>&1 &
      show_progress $! "Configuring Tailscale Serve" "Proxmox Web UI available via Tailscale Serve"
    fi

    # Deploy OpenSSH disable service when firewall is in stealth mode
    # In stealth mode, all public ports are blocked - SSH access is only via Tailscale
    if [[ ${FIREWALL_MODE:-standard} == "stealth" ]]; then
      log "Deploying disable-openssh.service (FIREWALL_MODE=$FIREWALL_MODE)"
      (
        log "Using pre-downloaded disable-openssh.service, size: $(wc -c <./templates/disable-openssh.service 2>/dev/null || echo 'failed')"
        remote_copy "templates/disable-openssh.service" "/etc/systemd/system/disable-openssh.service" || exit 1
        log "Copied disable-openssh.service to VM"
        remote_exec "systemctl daemon-reload && systemctl enable disable-openssh.service" >/dev/null 2>&1 || exit 1
        log "Enabled disable-openssh.service"
      ) &
      show_progress $! "Configuring OpenSSH disable on boot" "OpenSSH disable configured"
    else
      log "Skipping disable-openssh.service (FIREWALL_MODE=${FIREWALL_MODE:-standard})"
    fi

    # Note: Firewall is now configured separately via 52-configure-firewall.sh
  else
    TAILSCALE_IP="not authenticated"
    TAILSCALE_HOSTNAME=""
    add_log "${CLR_GRAY}├─${CLR_RESET} ${CLR_YELLOW}⚠️${CLR_RESET} Tailscale installed but not authenticated"
    add_log "${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}After reboot: tailscale up --ssh${CLR_RESET}"
  fi
}
