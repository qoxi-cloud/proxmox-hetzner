# shellcheck shell=bash
# Lynis - Security auditing and hardening tool
# Weekly scheduled scans with logging
# Package installed via batch_install_packages() in 037-parallel-helpers.sh

# Configuration function for lynis
# Sets up weekly scans via systemd timer with logging
_config_lynis() {
  deploy_timer_with_logdir "lynis-audit" "/var/log/lynis" || return 1
  parallel_mark_configured "lynis"
}

# Public wrapper (generated via factory)
make_feature_wrapper "lynis" "INSTALL_LYNIS"
