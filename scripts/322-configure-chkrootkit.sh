# shellcheck shell=bash
# =============================================================================
# chkrootkit - Rootkit detection scanner
# Weekly scheduled scans with logging
# Package installed via batch_install_packages() in 037-parallel-helpers.sh
# =============================================================================

# Configuration function for chkrootkit
# Sets up weekly scans via systemd timer with logging
_config_chkrootkit() {
  deploy_timer_with_logdir "chkrootkit-scan" "/var/log/chkrootkit" || return 1
  parallel_mark_configured "chkrootkit"
}

# =============================================================================
# Public wrapper (generated via factory)
# =============================================================================
make_feature_wrapper "chkrootkit" "INSTALL_CHKROOTKIT"
