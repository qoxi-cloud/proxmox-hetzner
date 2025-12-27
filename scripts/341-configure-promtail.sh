# shellcheck shell=bash
# Promtail - Log collector for Grafana Loki
# Collects system, auth, and Proxmox logs
# Package installed via batch_install_packages() in 037-parallel-helpers.sh

# Configuration function for promtail
_config_promtail() {
  # Deploy configuration with hostname (deploy_template creates parent dirs)
  deploy_template "templates/promtail.yml" "/etc/promtail/promtail.yml" \
    "HOSTNAME=${PVE_HOSTNAME}" || return 1

  # Deploy systemd service
  deploy_template "templates/promtail.service" "/etc/systemd/system/promtail.service" || return 1

  # Create positions directory (not handled by deploy_template - different path)
  remote_exec 'mkdir -p /var/lib/promtail' || return 1

  # Enable and start service
  remote_enable_services "promtail"
  parallel_mark_configured "promtail"
}

# Public wrapper (generated via factory)
# Collects logs from: /var/log/syslog, auth.log, pve*.log, kernel, journal
# Loki URL must be configured post-installation in /etc/promtail/promtail.yml
make_feature_wrapper "promtail" "INSTALL_PROMTAIL"
