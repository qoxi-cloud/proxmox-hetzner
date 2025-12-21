# shellcheck shell=bash
# =============================================================================
# Template preparation and download
# =============================================================================

# Modifies template files with variable substitution
_modify_template_files() {
  apply_common_template_vars "./templates/hosts"
  apply_common_template_vars "./templates/interfaces"
  postprocess_interfaces_bridge_mode "./templates/interfaces"
  postprocess_interfaces_ipv6 "./templates/interfaces"
  apply_common_template_vars "./templates/resolv.conf"
  apply_template_vars "./templates/cpupower.service" "CPU_GOVERNOR=${CPU_GOVERNOR:-performance}"
  # Locale templates - substitute {{LOCALE}} with actual locale value
  apply_common_template_vars "./templates/locale.sh"
  apply_common_template_vars "./templates/default-locale"
  apply_common_template_vars "./templates/environment"
}

# Downloads all templates in parallel using aria2c.
# Falls back to sequential wget if aria2c unavailable.
# Parameters:
#   $@ - List of "local_path:remote_name" pairs
# Returns: 0 on success, 1 on failure
_download_templates_parallel() {
  local -a templates=("$@")
  local input_file
  input_file=$(mktemp)

  # Build aria2c input file
  for entry in "${templates[@]}"; do
    local local_path="${entry%%:*}"
    local remote_name="${entry#*:}"
    local url="${GITHUB_BASE_URL}/templates/${remote_name}.tmpl"
    printf '%s\n' "$url"
    printf '%s\n' "  out=$local_path"
  done >"$input_file"

  log "Downloading ${#templates[@]} templates in parallel"

  # Use aria2c for parallel download if available
  if command -v aria2c &>/dev/null; then
    if aria2c -q \
      -j 16 \
      --max-connection-per-server=4 \
      --file-allocation=none \
      --max-tries=3 \
      --retry-wait=2 \
      --timeout=30 \
      --connect-timeout=10 \
      -i "$input_file" \
      >>"$LOG_FILE" 2>&1; then
      rm -f "$input_file"
      return 0
    fi
    log "WARNING: aria2c failed, falling back to sequential download"
  fi

  rm -f "$input_file"

  # Fallback: sequential download with wget
  for entry in "${templates[@]}"; do
    local local_path="${entry%%:*}"
    local remote_name="${entry#*:}"
    if ! download_template "$local_path" "$remote_name"; then
      return 1
    fi
  done
  return 0
}

# Downloads and prepares all template files for Proxmox configuration.
# Selects appropriate templates based on bridge mode and repository type.
# Side effects: Creates templates directory, downloads and modifies templates
make_templates() {
  log "Starting template preparation"
  mkdir -p ./templates
  log "Using bridge mode: ${BRIDGE_MODE:-internal}"

  # Select Proxmox repository template based on PVE_REPO_TYPE
  local proxmox_sources_template="proxmox.sources"
  case "${PVE_REPO_TYPE:-no-subscription}" in
    enterprise) proxmox_sources_template="proxmox-enterprise.sources" ;;
    test) proxmox_sources_template="proxmox-test.sources" ;;
  esac
  log "Using repository template: $proxmox_sources_template"

  # Build list of ALL templates: "local_path:remote_name"
  # All templates are pre-downloaded, used as needed
  local -a template_list=(
    # System base
    "./templates/99-proxmox.conf:99-proxmox.conf"
    "./templates/hosts:hosts"
    "./templates/debian.sources:debian.sources"
    "./templates/proxmox.sources:${proxmox_sources_template}"
    "./templates/sshd_config:sshd_config"
    "./templates/resolv.conf:resolv.conf"
    "./templates/interfaces:interfaces"
    # Locale
    "./templates/locale.sh:locale.sh"
    "./templates/default-locale:default-locale"
    "./templates/environment:environment"
    # Shell
    "./templates/zshrc:zshrc"
    "./templates/p10k.zsh:p10k.zsh"
    "./templates/fastfetch.sh:fastfetch.sh"
    "./templates/bat-config:bat-config"
    # System services
    "./templates/chrony:chrony"
    "./templates/50unattended-upgrades:50unattended-upgrades"
    "./templates/20auto-upgrades:20auto-upgrades"
    "./templates/cpupower.service:cpupower.service"
    "./templates/60-io-scheduler.rules:60-io-scheduler.rules"
    "./templates/remove-subscription-nag.sh:remove-subscription-nag.sh"
    # ZFS
    "./templates/zfs-scrub.service:zfs-scrub.service"
    "./templates/zfs-scrub.timer:zfs-scrub.timer"
    # Let's Encrypt
    "./templates/letsencrypt-deploy-hook.sh:letsencrypt-deploy-hook.sh"
    "./templates/letsencrypt-firstboot.sh:letsencrypt-firstboot.sh"
    "./templates/letsencrypt-firstboot.service:letsencrypt-firstboot.service"
    # Tailscale
    "./templates/disable-openssh.service:disable-openssh.service"
    # Firewall
    "./templates/nftables.conf:nftables.conf"
    # Security - Fail2Ban
    "./templates/fail2ban-jail.local:fail2ban-jail.local"
    "./templates/fail2ban-proxmox.conf:fail2ban-proxmox.conf"
    # Security - AppArmor
    "./templates/apparmor-grub.cfg:apparmor-grub.cfg"
    # Security - Auditd
    "./templates/auditd-rules:auditd-rules"
    # Security - AIDE
    "./templates/aide-check.service:aide-check.service"
    "./templates/aide-check.timer:aide-check.timer"
    # Security - chkrootkit
    "./templates/chkrootkit-scan.service:chkrootkit-scan.service"
    "./templates/chkrootkit-scan.timer:chkrootkit-scan.timer"
    # Security - Lynis
    "./templates/lynis-audit.service:lynis-audit.service"
    "./templates/lynis-audit.timer:lynis-audit.timer"
    # Security - needrestart
    "./templates/needrestart.conf:needrestart.conf"
    # Monitoring - vnStat
    "./templates/vnstat.conf:vnstat.conf"
    # Monitoring - Netdata
    "./templates/netdata.conf:netdata.conf"
    # Monitoring - Promtail
    "./templates/promtail.yml:promtail.yml"
    "./templates/promtail.service:promtail.service"
    # Tools - Yazi
    "./templates/yazi-theme.toml:yazi-theme.toml"
    # Network tuning
    "./templates/network-ringbuffer.service:network-ringbuffer.service"
    # Validation
    "./templates/validation.sh:validation.sh"
  )

  # Download all templates in parallel
  if ! run_with_progress "Downloading template files" "Template files downloaded" \
    _download_templates_parallel "${template_list[@]}"; then
    log "ERROR: Failed to download template files"
    exit 1
  fi

  # Derive PRIVATE_IP_CIDR from PRIVATE_SUBNET (e.g., 10.0.0.0/24 → 10.0.0.1/24)
  if [[ -n ${PRIVATE_SUBNET:-} && $BRIDGE_MODE != "external" ]]; then
    PRIVATE_IP_CIDR="${PRIVATE_SUBNET%.*}.1/${PRIVATE_SUBNET#*/}"
    export PRIVATE_IP_CIDR
    log "Derived PRIVATE_IP_CIDR=$PRIVATE_IP_CIDR from PRIVATE_SUBNET=$PRIVATE_SUBNET"
  fi

  # Modify template files in background with progress
  run_with_progress "Modifying template files" "Template files modified" _modify_template_files
}
