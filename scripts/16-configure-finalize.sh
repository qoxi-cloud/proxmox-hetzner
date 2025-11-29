# shellcheck shell=bash
# =============================================================================
# SSH hardening and finalization
# =============================================================================

configure_ssh_hardening() {
    # Deploy SSH hardening LAST (after all other operations)
    (
        remote_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
        remote_exec "echo '$SSH_PUBLIC_KEY' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
        remote_copy "templates/sshd_config" "/etc/ssh/sshd_config"
    ) > /dev/null 2>&1 &
    show_progress $! "Deploying SSH hardening" "Security hardening configured"
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
    configure_ssh_hardening
    finalize_vm
}
