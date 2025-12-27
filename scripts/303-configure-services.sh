# shellcheck shell=bash
# System services configuration via SSH

# Helper functions

# Configure chrony NTP with custom config
_configure_chrony() {
  remote_exec "systemctl stop chrony" || true
  remote_copy "templates/chrony" "/etc/chrony/chrony.conf" || return 1
  remote_exec "systemctl enable --now chrony" || return 1
}

# Configure unattended-upgrades for automatic security updates
_configure_unattended_upgrades() {
  remote_copy "templates/50unattended-upgrades" "/etc/apt/apt.conf.d/50unattended-upgrades" || return 1
  remote_copy "templates/20auto-upgrades" "/etc/apt/apt.conf.d/20auto-upgrades" || return 1
  remote_exec "systemctl enable --now unattended-upgrades" || return 1
}

# Configure CPU governor via systemd (uses CPU_GOVERNOR global)
_configure_cpu_governor() {
  local governor="${CPU_GOVERNOR:-performance}"
  remote_copy "templates/cpupower.service" "/etc/systemd/system/cpupower.service" || return 1
  remote_exec "
    systemctl daemon-reload
    systemctl enable --now cpupower.service
    cpupower frequency-set -g '$governor' 2>/dev/null || true
  " || return 1
}

# Configure I/O scheduler via udev (none/mq-deadline/bfq)
_configure_io_scheduler() {
  remote_copy "templates/60-io-scheduler.rules" "/etc/udev/rules.d/60-io-scheduler.rules" || return 1
  remote_exec "udevadm control --reload-rules && udevadm trigger" || return 1
}

# Remove Proxmox subscription notice (non-enterprise only)
_remove_subscription_notice() {
  remote_copy "templates/remove-subscription-nag.sh" "/tmp/remove-subscription-nag.sh" || return 1
  remote_exec "chmod +x /tmp/remove-subscription-nag.sh && /tmp/remove-subscription-nag.sh && rm -f /tmp/remove-subscription-nag.sh" || return 1
}

# Private implementation

# Configure system services (chrony, upgrades, CPU governor)
_config_system_services() {
  # Configure NTP time synchronization with chrony (package already installed)
  run_with_progress "Configuring chrony" "Chrony configured" _configure_chrony

  # Configure Unattended Upgrades (package already installed)
  run_with_progress "Configuring Unattended Upgrades" "Unattended Upgrades configured" _configure_unattended_upgrades

  # Configure kernel modules (nf_conntrack, tcp_bbr)
  # shellcheck disable=SC2016 # Single quotes intentional - executed on remote
  remote_run "Configuring kernel modules" '
        for mod in nf_conntrack tcp_bbr; do
            if ! grep -q "^${mod}$" /etc/modules 2>/dev/null; then
                echo "$mod" >> /etc/modules
            fi
        done
        modprobe tcp_bbr 2>/dev/null || true
    ' "Kernel modules configured"

  # Configure system limits (nofile for containers/monitoring)
  run_with_progress "Configuring system limits" "System limits configured" \
    remote_copy "templates/99-limits.conf" "/etc/security/limits.d/99-proxmox.conf"

  # Disable APT translations (saves disk/bandwidth on servers)
  remote_run "Optimizing APT configuration" '
        echo "Acquire::Languages \"none\";" > /etc/apt/apt.conf.d/99-disable-translations
    ' "APT configuration optimized"

  # Configure CPU governor using linux-cpupower
  # Governor already validated by wizard (only shows available options)
  local governor="${CPU_GOVERNOR:-performance}"
  run_with_progress "Configuring CPU governor (${governor})" "CPU governor configured" _configure_cpu_governor

  # Configure I/O scheduler udev rules (NVMe: none, SSD: mq-deadline, HDD: bfq)
  run_with_progress "Configuring I/O scheduler" "I/O scheduler configured" _configure_io_scheduler

  # Remove Proxmox subscription notice (only for non-enterprise)
  if [[ ${PVE_REPO_TYPE:-no-subscription} != "enterprise" ]]; then
    log "configure_system_services: removing subscription notice (non-enterprise)"
    run_with_progress "Removing Proxmox subscription notice" "Subscription notice removed" _remove_subscription_notice
  fi
}

# Public wrapper

# Configure system services (NTP, upgrades, CPU governor, I/O scheduler)
configure_system_services() {
  _config_system_services
}
