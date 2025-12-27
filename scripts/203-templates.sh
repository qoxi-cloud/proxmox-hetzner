# shellcheck shell=bash
# Template preparation and download

# Applies variable substitution to all template files.
# Handles hosts, resolv.conf, cpupower, locale templates.
# Interfaces is generated via heredoc (039-network-helpers.sh).
_modify_template_files() {
  log "Starting template modification"
  apply_common_template_vars "./templates/hosts" || return 1
  generate_interfaces_file "./templates/interfaces" || return 1
  apply_common_template_vars "./templates/resolv.conf" || return 1
  apply_template_vars "./templates/cpupower.service" "CPU_GOVERNOR=${CPU_GOVERNOR:-performance}" || return 1
  # Locale templates - substitute {{LOCALE}} with actual locale value
  apply_common_template_vars "./templates/locale.sh" || return 1
  apply_common_template_vars "./templates/default-locale" || return 1
  apply_common_template_vars "./templates/environment" || return 1
  log "Template modification complete"
}

# Download templates in parallel (aria2c→wget fallback). $@="path:name" pairs
_download_templates_parallel() {
  local -a templates=("$@")
  local input_file
  input_file=$(mktemp)
  register_temp_file "$input_file"

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
  if cmd_exists aria2c; then
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
      # Validate all downloaded templates (aria2c doesn't validate content)
      for entry in "${templates[@]}"; do
        local local_path="${entry%%:*}"
        if [[ ! -s $local_path ]]; then
          log "ERROR: Template $local_path is empty after aria2c download"
          return 1
        fi
      done
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

# Download and prepare all template files for Proxmox configuration
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
    "./templates/99-limits.conf:99-limits.conf"
    "./templates/hosts:hosts"
    "./templates/debian.sources:debian.sources"
    "./templates/proxmox.sources:${proxmox_sources_template}"
    "./templates/sshd_config:sshd_config"
    "./templates/resolv.conf:resolv.conf"
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
    "./templates/yazi.toml:yazi.toml"
    "./templates/yazi-theme.toml:yazi-theme.toml"
    "./templates/yazi-init.lua:yazi-init.lua"
    "./templates/yazi-keymap.toml:yazi-keymap.toml"
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
  if ! run_with_progress "Modifying template files" "Template files modified" _modify_template_files; then
    log "ERROR: Template modification failed"
    return 1
  fi
}
