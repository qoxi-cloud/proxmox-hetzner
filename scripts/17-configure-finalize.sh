# shellcheck shell=bash
# =============================================================================
# SSH hardening and finalization
# =============================================================================

configure_ssh_hardening() {
    # Deploy SSH hardening LAST (after all other operations)
    # CRITICAL: This must succeed - if it fails, system remains with password auth enabled

    # Escape single quotes in SSH key to prevent injection
    local escaped_ssh_key="${SSH_PUBLIC_KEY//\'/\'\\\'\'}"

    (
        remote_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh" || exit 1
        remote_exec "echo '${escaped_ssh_key}' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" || exit 1
        remote_copy "templates/sshd_config" "/etc/ssh/sshd_config" || exit 1
    ) > /dev/null 2>&1 &
    show_progress $! "Deploying SSH hardening" "Security hardening configured"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: SSH hardening failed - system may be insecure"
        exit 1
    fi
}

finalize_vm() {
    # Power off the VM
    remote_exec "poweroff" > /dev/null 2>&1 &
    show_progress $! "Powering off the VM"

    # Wait for QEMU to exit
    wait_with_progress "Waiting for QEMU process to exit" 120 "! kill -0 $QEMU_PID 2>/dev/null" 1 "QEMU process exited"
}

# =============================================================================
# Main configuration function
# =============================================================================

configure_proxmox_via_ssh() {
    log "Starting Proxmox configuration via SSH"
    make_templates
    configure_base_system
    configure_shell
    configure_system_services
    configure_tailscale
    configure_fail2ban
    configure_auditd
    configure_ssl_certificate
    configure_ssh_hardening
    validate_installation
    finalize_vm
}
