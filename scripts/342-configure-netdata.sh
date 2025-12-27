# shellcheck shell=bash
# Netdata - Real-time performance and health monitoring
# Provides web dashboard on port 19999
# Package installed via batch_install_packages() in 037-parallel-helpers.sh

# Configuration function for netdata
_config_netdata() {
  # Determine bind address based on Tailscale
  local bind_to="127.0.0.1"
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    bind_to="127.0.0.1 100.*"
  fi

  deploy_template "templates/netdata.conf" "/etc/netdata/netdata.conf" \
    "NETDATA_BIND_TO=${bind_to}" || return 1

  remote_enable_services "netdata"
}

# Public wrapper (generated via factory)
# Provides web dashboard on port 19999.
# If Tailscale enabled: accessible via Tailscale network
# Otherwise: localhost only (use reverse proxy for external access)
make_feature_wrapper "netdata" "INSTALL_NETDATA"
