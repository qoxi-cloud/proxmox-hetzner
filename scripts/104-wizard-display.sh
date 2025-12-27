# shellcheck shell=bash
# Configuration Wizard - Display Value Formatters
# Formats configuration values for display in wizard menu

# Display mapping table (internal value → display text)

declare -gA _DSP_MAP=(
  # Repository types
  ["repo:no-subscription"]="No-subscription (free)"
  ["repo:enterprise"]="Enterprise"
  ["repo:test"]="Test/Development"

  # IPv6 modes
  ["ipv6:auto"]="Auto"
  ["ipv6:manual"]="Manual"
  ["ipv6:disabled"]="Disabled"

  # Bridge modes
  ["bridge:external"]="External bridge"
  ["bridge:internal"]="Internal NAT"
  ["bridge:both"]="Both"

  # Firewall modes
  ["firewall:stealth"]="Stealth (Tailscale only)"
  ["firewall:strict"]="Strict (SSH only)"
  ["firewall:standard"]="Standard (SSH + Web UI)"

  # ZFS RAID
  ["zfs:single"]="Single disk"
  ["zfs:raid0"]="RAID-0 (striped)"
  ["zfs:raid1"]="RAID-1 (mirror)"
  ["zfs:raidz1"]="RAID-Z1 (parity)"
  ["zfs:raidz2"]="RAID-Z2 (double parity)"
  ["zfs:raidz3"]="RAID-Z3 (triple parity)"
  ["zfs:raid10"]="RAID-10 (striped mirrors)"

  # ZFS ARC
  ["arc:vm-focused"]="VM-focused (4GB)"
  ["arc:balanced"]="Balanced (25-40%)"
  ["arc:storage-focused"]="Storage-focused (50%)"

  # SSL types
  ["ssl:self-signed"]="Self-signed"
  ["ssl:letsencrypt"]="Let's Encrypt"

  # Shell types
  ["shell:zsh"]="ZSH"
  ["shell:bash"]="Bash"

  # CPU governors
  ["power:performance"]="Performance"
  ["power:ondemand"]="Balanced"
  ["power:powersave"]="Balanced"
  ["power:schedutil"]="Adaptive"
  ["power:conservative"]="Conservative"
)

# Lookup display value. $1=category, $2=internal_value → display_text
_dsp_lookup() {
  local key="$1:$2"
  echo "${_DSP_MAP[$key]:-$2}"
}

# Display value formatters (grouped by screen)

# Formats Basic screen values: hostname, password
_dsp_basic() {
  _DSP_PASS=""
  [[ -n $NEW_ROOT_PASSWORD ]] && _DSP_PASS="********"

  _DSP_HOSTNAME=""
  [[ -n $PVE_HOSTNAME && -n $DOMAIN_SUFFIX ]] && _DSP_HOSTNAME="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
}

# Formats Proxmox screen values: repository, ISO version
_dsp_proxmox() {
  _DSP_REPO=""
  [[ -n $PVE_REPO_TYPE ]] && _DSP_REPO=$(_dsp_lookup "repo" "$PVE_REPO_TYPE")

  _DSP_ISO=""
  [[ -n $PROXMOX_ISO_VERSION ]] && _DSP_ISO=$(get_iso_version "$PROXMOX_ISO_VERSION")
}

# Formats Network screen values: IPv6, bridge, firewall, MTU
_dsp_network() {
  _DSP_IPV6=""
  if [[ -n $IPV6_MODE ]]; then
    _DSP_IPV6=$(_dsp_lookup "ipv6" "$IPV6_MODE")
    # Special case: manual mode shows address details
    [[ $IPV6_MODE == "manual" && -n $MAIN_IPV6 ]] && _DSP_IPV6+=" (${MAIN_IPV6}, gw: ${IPV6_GATEWAY})"
  fi

  _DSP_BRIDGE=""
  [[ -n $BRIDGE_MODE ]] && _DSP_BRIDGE=$(_dsp_lookup "bridge" "$BRIDGE_MODE")

  _DSP_FIREWALL=""
  if [[ -n $INSTALL_FIREWALL ]]; then
    if [[ $INSTALL_FIREWALL == "yes" ]]; then
      _DSP_FIREWALL=$(_dsp_lookup "firewall" "$FIREWALL_MODE")
    else
      _DSP_FIREWALL="Disabled"
    fi
  fi

  _DSP_MTU="${BRIDGE_MTU:-9000}"
  [[ $_DSP_MTU == "9000" ]] && _DSP_MTU="9000 (jumbo)"
}

# Formats Storage screen values: ZFS mode, ARC, boot/pool disks, existing pool
_dsp_storage() {
  # Existing pool mode
  _DSP_EXISTING_POOL=""
  if [[ $USE_EXISTING_POOL == "yes" && -n $EXISTING_POOL_NAME ]]; then
    _DSP_EXISTING_POOL="Use: ${EXISTING_POOL_NAME} (${#EXISTING_POOL_DISKS[@]} disks)"
  else
    _DSP_EXISTING_POOL="Create new"
  fi

  _DSP_ZFS=""
  if [[ -n $ZFS_RAID ]]; then
    _DSP_ZFS=$(_dsp_lookup "zfs" "$ZFS_RAID")
  elif [[ $USE_EXISTING_POOL == "yes" ]]; then
    _DSP_ZFS="(preserved)"
  fi

  _DSP_ARC=""
  [[ -n $ZFS_ARC_MODE ]] && _DSP_ARC=$(_dsp_lookup "arc" "$ZFS_ARC_MODE")

  _DSP_BOOT="All in pool"
  if [[ -n $BOOT_DISK ]]; then
    for i in "${!DRIVES[@]}"; do
      if [[ ${DRIVES[$i]} == "$BOOT_DISK" ]]; then
        _DSP_BOOT="${DRIVE_MODELS[$i]}"
        break
      fi
    done
  fi

  if [[ $USE_EXISTING_POOL == "yes" ]]; then
    _DSP_POOL="(existing pool)"
  else
    _DSP_POOL="${#ZFS_POOL_DISKS[@]} disks"
  fi

  # Wipe disks option
  _DSP_WIPE=""
  if [[ $WIPE_DISKS == "yes" ]]; then
    _DSP_WIPE="Yes (full wipe)"
  else
    _DSP_WIPE="No (keep existing)"
  fi
}

# Formats Services screen values: Tailscale, SSL, shell, power, features
_dsp_services() {
  _DSP_TAILSCALE=""
  if [[ -n $INSTALL_TAILSCALE ]]; then
    [[ $INSTALL_TAILSCALE == "yes" ]] && _DSP_TAILSCALE="Enabled + Stealth" || _DSP_TAILSCALE="Disabled"
  fi

  _DSP_SSL=""
  [[ -n $SSL_TYPE ]] && _DSP_SSL=$(_dsp_lookup "ssl" "$SSL_TYPE")

  _DSP_SHELL=""
  [[ -n $SHELL_TYPE ]] && _DSP_SHELL=$(_dsp_lookup "shell" "$SHELL_TYPE")

  _DSP_POWER=""
  [[ -n $CPU_GOVERNOR ]] && _DSP_POWER=$(_dsp_lookup "power" "$CPU_GOVERNOR")

  # Feature lists
  _DSP_SECURITY="none"
  local sec_items=()
  [[ $INSTALL_APPARMOR == "yes" ]] && sec_items+=("apparmor")
  [[ $INSTALL_AUDITD == "yes" ]] && sec_items+=("auditd")
  [[ $INSTALL_AIDE == "yes" ]] && sec_items+=("aide")
  [[ $INSTALL_CHKROOTKIT == "yes" ]] && sec_items+=("chkrootkit")
  [[ $INSTALL_LYNIS == "yes" ]] && sec_items+=("lynis")
  [[ $INSTALL_NEEDRESTART == "yes" ]] && sec_items+=("needrestart")
  [[ ${#sec_items[@]} -gt 0 ]] && _DSP_SECURITY="${sec_items[*]}"

  _DSP_MONITORING="none"
  local mon_items=()
  [[ $INSTALL_VNSTAT == "yes" ]] && mon_items+=("vnstat")
  [[ $INSTALL_NETDATA == "yes" ]] && mon_items+=("netdata")
  [[ $INSTALL_PROMTAIL == "yes" ]] && mon_items+=("promtail")
  [[ ${#mon_items[@]} -gt 0 ]] && _DSP_MONITORING="${mon_items[*]}"

  _DSP_TOOLS="none"
  local tool_items=()
  [[ $INSTALL_YAZI == "yes" ]] && tool_items+=("yazi")
  [[ $INSTALL_NVIM == "yes" ]] && tool_items+=("nvim")
  [[ $INSTALL_RINGBUFFER == "yes" ]] && tool_items+=("ringbuffer")
  [[ ${#tool_items[@]} -gt 0 ]] && _DSP_TOOLS="${tool_items[*]}"
}

# Formats Access screen values: admin user, SSH key, API token
_dsp_access() {
  _DSP_ADMIN_USER=""
  [[ -n $ADMIN_USERNAME ]] && _DSP_ADMIN_USER="$ADMIN_USERNAME"

  _DSP_ADMIN_PASS=""
  [[ -n $ADMIN_PASSWORD ]] && _DSP_ADMIN_PASS="********"

  _DSP_SSH=""
  [[ -n $SSH_PUBLIC_KEY ]] && _DSP_SSH="${SSH_PUBLIC_KEY:0:20}..."

  _DSP_API=""
  if [[ -n $INSTALL_API_TOKEN ]]; then
    case "$INSTALL_API_TOKEN" in
      yes) _DSP_API="Yes (${API_TOKEN_NAME})" ;;
      no) _DSP_API="No" ;;
    esac
  fi
}

# Build _DSP_* display values from current config state
_wiz_build_display_values() {
  _dsp_basic
  _dsp_proxmox
  _dsp_network
  _dsp_storage
  _dsp_services
  _dsp_access
}
