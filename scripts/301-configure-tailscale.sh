# shellcheck shell=bash
# Tailscale VPN configuration

# Private implementation - configures Tailscale VPN
# Called by configure_tailscale() public wrapper
_config_tailscale() {

  # Start tailscaled and wait for socket (up to 3s)
  remote_run "Starting Tailscale" '
        set -e
        systemctl enable --now tailscaled
        systemctl start tailscaled
        for i in {1..3}; do tailscale status &>/dev/null && break; sleep 1; done
        true
    ' "Tailscale started"

  # If auth key is provided, authenticate Tailscale
  if [[ -n $TAILSCALE_AUTH_KEY ]]; then
    # Use unique temporary files to avoid race conditions
    local tmp_ip tmp_hostname tmp_result
    tmp_ip=$(mktemp)
    tmp_hostname=$(mktemp)
    tmp_result=$(mktemp)

    # Ensure cleanup on function exit (handles errors too)
    # shellcheck disable=SC2064
    trap "rm -f '$tmp_ip' '$tmp_hostname' '$tmp_result'" RETURN

    # Build and execute tailscale up command (SSH always enabled)
    (
      # Run tailscale up with auth key
      if remote_exec "tailscale up --authkey='$TAILSCALE_AUTH_KEY' --ssh"; then
        echo "success" >"$tmp_result"
        # Get IP and hostname in one call using tailscale status --json
        remote_exec "tailscale status --json | jq -r '[(.Self.TailscaleIPs[0] // \"pending\"), (.Self.DNSName // \"\" | rtrimstr(\".\"))] | @tsv'" 2>/dev/null | {
          IFS=$'\t' read -r ip hostname
          echo "$ip" >"$tmp_ip"
          echo "$hostname" >"$tmp_hostname"
        } || true
      else
        echo "failed" >"$tmp_result"
        log "ERROR: tailscale up command failed"
      fi
    ) >/dev/null 2>&1 &
    show_progress $! "Authenticating Tailscale"

    # Check if authentication succeeded
    local auth_result
    auth_result=$(cat "$tmp_result" 2>/dev/null || echo "failed")

    if [[ $auth_result == "success" ]]; then
      # Get Tailscale IP and hostname for display
      TAILSCALE_IP=$(cat "$tmp_ip" 2>/dev/null || echo "pending")
      TAILSCALE_HOSTNAME=$(cat "$tmp_hostname" 2>/dev/null || printf '\n')

      # Update log with IP info
      complete_task "$TASK_INDEX" "${CLR_ORANGE}├─${CLR_RESET} Tailscale authenticated. IP: ${TAILSCALE_IP}"

      # Configure Tailscale Serve for Proxmox Web UI (only if auth succeeded)
      if [[ $TAILSCALE_WEBUI == "yes" ]]; then
        remote_run "Configuring Tailscale Serve" \
          'tailscale serve --bg --https=443 https://127.0.0.1:8006' \
          "Proxmox Web UI available via Tailscale Serve"
      fi

      # Deploy OpenSSH disable service when firewall is in stealth mode
      # In stealth mode, all public ports are blocked - SSH access is only via Tailscale
      # Only deploy if Tailscale auth succeeded (otherwise we'd lock ourselves out!)
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
    else
      TAILSCALE_IP="auth failed"
      TAILSCALE_HOSTNAME=""
      complete_task "$TASK_INDEX" "${CLR_ORANGE}├─${CLR_RESET} ${CLR_YELLOW}Tailscale auth failed - check auth key${CLR_RESET}" "warning"
      log "WARNING: Tailscale authentication failed. Auth key may be invalid or expired."

      # In stealth mode with failed Tailscale auth, warn but DON'T disable SSH
      # This prevents locking out the user
      if [[ ${FIREWALL_MODE:-standard} == "stealth" ]]; then
        add_log "${CLR_ORANGE}│${CLR_RESET}   ${CLR_YELLOW}SSH will remain enabled (Tailscale auth failed)${CLR_RESET}"
        log "WARNING: Stealth mode requested but Tailscale auth failed - SSH will remain enabled to prevent lockout"
      fi
    fi

    # Note: Firewall is now configured separately via 310-configure-firewall.sh
  else
    TAILSCALE_IP="not authenticated"
    TAILSCALE_HOSTNAME=""
    add_log "${CLR_ORANGE}├─${CLR_RESET} ${CLR_YELLOW}⚠️${CLR_RESET} Tailscale installed but not authenticated"
    add_subtask_log "After reboot: tailscale up --ssh"
  fi
}

# Public wrapper

# Configures Tailscale VPN with SSH and Web UI access.
# Configure Tailscale with optional auth key and stealth mode
configure_tailscale() {
  [[ $INSTALL_TAILSCALE != "yes" ]] && return 0
  _config_tailscale
}
