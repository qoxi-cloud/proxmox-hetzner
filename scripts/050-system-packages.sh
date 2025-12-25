# shellcheck shell=bash
# =============================================================================
# System package installation
# =============================================================================

# Installs ZFS tools if not available.
# On Hetzner rescue, uses their install script (compiles from source).
# On other systems, tries apt-get.
# Side effects: May install ZFS packages
_install_zfs_if_needed() {
  command -v zpool &>/dev/null && return 0

  # Check for Hetzner rescue install script
  if [[ -x /root/.oldroot/nfs/install/zfs.sh ]]; then
    # Hetzner rescue: auto-accept license and install
    echo "y" | /root/.oldroot/nfs/install/zfs.sh >/dev/null 2>&1 || true
  elif [[ -f /etc/debian_version ]]; then
    # Debian/Ubuntu: try apt
    apt-get install -qq -y zfsutils-linux >/dev/null 2>&1 || true
  fi
}

# Installs required packages for the installer.
# Adds Charm repo for gum if needed.
# Side effects: May install packages, add apt repos
_install_required_packages() {
  local -A required_commands=(
    [column]="bsdmainutils"
    [ip]="iproute2"
    [udevadm]="udev"
    [timeout]="coreutils"
    [curl]="curl"
    [jq]="jq"
    [aria2c]="aria2"
    [findmnt]="util-linux"
    [gpg]="gnupg"
    [gum]="gum"
  )

  local packages_to_install=""
  local need_charm_repo=false

  for cmd in "${!required_commands[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      packages_to_install+=" ${required_commands[$cmd]}"
      [[ $cmd == "gum" ]] && need_charm_repo=true
    fi
  done

  if [[ $need_charm_repo == true ]]; then
    mkdir -p /etc/apt/keyrings 2>/dev/null
    curl -fsSL https://repo.charm.sh/apt/gpg.key 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/charm.gpg >/dev/null 2>&1
    printf '%s\n' "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" >/etc/apt/sources.list.d/charm.list 2>/dev/null
  fi

  if [[ -n $packages_to_install ]]; then
    apt-get update -qq >/dev/null 2>&1
    # shellcheck disable=SC2086
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y $packages_to_install >/dev/null 2>&1
  fi

  # Install ZFS for pool detection (needed for existing pool feature)
  _install_zfs_if_needed
}
