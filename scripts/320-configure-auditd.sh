# shellcheck shell=bash
# =============================================================================
# Auditd configuration for administrative action logging
# Provides audit trail for security compliance and forensics
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for auditd
# Deploys audit rules and configures log retention
_config_auditd() {
  # Copy rules to VM
  remote_copy "templates/auditd-rules" "/etc/audit/rules.d/proxmox.rules" || {
    log "ERROR: Failed to deploy auditd rules"
    return 1
  }

  # Configure auditd for persistent logging
  remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/audit

    # Configure auditd.conf for better log retention
    sed -i "s/^max_log_file = .*/max_log_file = 50/" /etc/audit/auditd.conf 2>/dev/null || true
    sed -i "s/^num_logs = .*/num_logs = 10/" /etc/audit/auditd.conf 2>/dev/null || true
    sed -i "s/^max_log_file_action = .*/max_log_file_action = ROTATE/" /etc/audit/auditd.conf 2>/dev/null || true

    # Load new rules
    augenrules --load 2>/dev/null || true

    # Enable auditd to start on boot (will activate after reboot)
    systemctl enable auditd
  ' || {
    log "ERROR: Failed to configure auditd"
    return 1
  }
}
