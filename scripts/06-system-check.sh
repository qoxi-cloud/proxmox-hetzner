# shellcheck shell=bash
# =============================================================================
# System checks and hardware detection
# =============================================================================

# Collects and validates system information with progress indicator.
# Checks: root access, internet connectivity, disk space, RAM, CPU, KVM.
# Installs required packages if missing.
# Exits with error if critical checks fail.
collect_system_info() {
  local errors=0
  local checks=7
  local current=0

  # Progress update helper (optimized: no subprocess spawning)
  update_progress() {
    current=$((current + 1))
    local pct=$((current * 100 / checks))
    local filled=$((pct / 5))
    local empty=$((20 - filled))
    local bar_filled="" bar_empty=""

    # Build progress bar strings without spawning subprocesses
    printf -v bar_filled '%*s' "$filled" ''
    bar_filled="${bar_filled// /█}"
    printf -v bar_empty '%*s' "$empty" ''
    bar_empty="${bar_empty// /░}"

    printf "\r${CLR_ORANGE}Checking system... [${CLR_ORANGE}%s${CLR_RESET}${CLR_GRAY}%s${CLR_RESET}${CLR_ORANGE}] %3d%%${CLR_RESET}" \
      "$bar_filled" "$bar_empty" "$pct"
  }

  # Install required tools
  # column: alignment, iproute2: ip command
  # udev: udevadm for interface detection, timeout: command timeouts
  # jq: JSON parsing for API responses
  # aria2c: optional multi-connection downloads (fallback: curl, wget)
  # findmnt: efficient mount point queries
  # gum: glamorous shell scripts UI (charmbracelet/gum)
  update_progress
  local packages_to_install=""
  local need_charm_repo=false
  command -v column &>/dev/null || packages_to_install+=" bsdmainutils"
  command -v ip &>/dev/null || packages_to_install+=" iproute2"
  command -v udevadm &>/dev/null || packages_to_install+=" udev"
  command -v timeout &>/dev/null || packages_to_install+=" coreutils"
  command -v curl &>/dev/null || packages_to_install+=" curl"
  command -v jq &>/dev/null || packages_to_install+=" jq"
  command -v aria2c &>/dev/null || packages_to_install+=" aria2"
  command -v findmnt &>/dev/null || packages_to_install+=" util-linux"
  command -v gum &>/dev/null || { need_charm_repo=true; packages_to_install+=" gum"; }

  # Add Charm repo for gum if needed (not in default Debian repos)
  if [[ $need_charm_repo == true ]]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" >/etc/apt/sources.list.d/charm.list
  fi

  if [[ -n $packages_to_install ]]; then
    apt-get update -qq >/dev/null 2>&1
    # shellcheck disable=SC2086
    apt-get install -qq -y $packages_to_install >/dev/null 2>&1
  fi

  # Check if running as root
  update_progress
  if [[ $EUID -ne 0 ]]; then
    errors=$((errors + 1))
  fi
  sleep 0.1

  # Check internet connectivity
  update_progress
  if ! ping -c 1 -W 3 "$DNS_PRIMARY" >/dev/null 2>&1; then
    errors=$((errors + 1))
  fi

  # Check available disk space (need at least 3GB in /root for ISO)
  update_progress
  local free_space_mb
  free_space_mb=$(df -m /root | awk 'NR==2 {print $4}')
  if [[ $free_space_mb -lt $MIN_DISK_SPACE_MB ]]; then
    errors=$((errors + 1))
  fi
  sleep 0.1

  # Check RAM (need at least 4GB)
  update_progress
  local total_ram_mb
  total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
  if [[ $total_ram_mb -lt $MIN_RAM_MB ]]; then
    errors=$((errors + 1))
  fi
  sleep 0.1

  # Check CPU cores (warning only, not critical)
  update_progress
  sleep 0.1

  # Check if KVM is available (try to load module if not present)
  update_progress
  if [[ ! -e /dev/kvm ]]; then
    # Try to load KVM module (needed in rescue mode)
    modprobe kvm 2>/dev/null || true

    # Determine CPU type and load appropriate module
    if grep -q "Intel" /proc/cpuinfo 2>/dev/null; then
      modprobe kvm_intel 2>/dev/null || true
    elif grep -q "AMD" /proc/cpuinfo 2>/dev/null; then
      modprobe kvm_amd 2>/dev/null || true
    else
      # Fallback: try both
      modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || true
    fi
    sleep 0.5
  fi
  if [[ ! -e /dev/kvm ]]; then
    errors=$((errors + 1))
  fi
  sleep 0.1

  # Clear progress line
  printf "\r\033[K"

  # Detect drives
  detect_drives

  # Check for errors
  if [[ $errors -gt 0 ]]; then
    log "ERROR: Pre-flight checks failed with $errors error(s)"
    exit 1
  fi

  if [[ $DRIVE_COUNT -eq 0 ]]; then
    log "ERROR: No drives detected"
    exit 1
  fi
}

# Detects available drives (NVMe preferred, fallback to any disk).
# Excludes loop devices and partitions.
# Side effects: Sets DRIVES, DRIVE_COUNT, DRIVE_NAMES, DRIVE_SIZES, DRIVE_MODELS globals
detect_drives() {
  # Find all NVMe drives (excluding partitions)
  mapfile -t DRIVES < <(lsblk -d -n -o NAME,TYPE | grep nvme | grep disk | awk '{print "/dev/"$1}' | sort)
  DRIVE_COUNT=${#DRIVES[@]}

  # Fall back to any available disk if no NVMe found (for budget servers)
  if [[ $DRIVE_COUNT -eq 0 ]]; then
    # Find any disk (sda, vda, etc.) excluding loop devices
    mapfile -t DRIVES < <(lsblk -d -n -o NAME,TYPE | grep disk | grep -v loop | awk '{print "/dev/"$1}' | sort)
    DRIVE_COUNT=${#DRIVES[@]}
  fi

  # Collect drive info
  DRIVE_NAMES=()
  DRIVE_SIZES=()
  DRIVE_MODELS=()

  for drive in "${DRIVES[@]}"; do
    local name size model
    name=$(basename "$drive")
    size=$(lsblk -d -n -o SIZE "$drive" | xargs)
    model=$(lsblk -d -n -o MODEL "$drive" 2>/dev/null | xargs || echo "Disk")
    DRIVE_NAMES+=("$name")
    DRIVE_SIZES+=("$size")
    DRIVE_MODELS+=("$model")
  done

  # Note: ZFS_RAID defaults are set in 07-input.sh during input collection
  # Only preserve ZFS_RAID if it was explicitly set by user via environment

}

