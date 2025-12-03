# shellcheck shell=bash
# =============================================================================
# System checks and hardware detection
# =============================================================================

# Collects and validates system information with progress indicator.
# Checks: root access, internet connectivity, disk space, RAM, CPU, KVM.
# Installs required packages if missing.
# Side effects: Sets PREFLIGHT_* global variables, may install packages
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

  # Install required tools and display utilities
  # boxes: table display, column: alignment, iproute2: ip command
  # udev: udevadm for interface detection, timeout: command timeouts
  # jq: JSON parsing for API responses
  # aria2c: optional multi-connection downloads (fallback: curl, wget)
  # findmnt: efficient mount point queries
  update_progress
  local packages_to_install=""
  command -v boxes &>/dev/null || packages_to_install+=" boxes"
  command -v column &>/dev/null || packages_to_install+=" bsdmainutils"
  command -v ip &>/dev/null || packages_to_install+=" iproute2"
  command -v udevadm &>/dev/null || packages_to_install+=" udev"
  command -v timeout &>/dev/null || packages_to_install+=" coreutils"
  command -v curl &>/dev/null || packages_to_install+=" curl"
  command -v jq &>/dev/null || packages_to_install+=" jq"
  command -v aria2c &>/dev/null || packages_to_install+=" aria2"
  command -v findmnt &>/dev/null || packages_to_install+=" util-linux"

  if [[ -n $packages_to_install ]]; then
    apt-get update -qq >/dev/null 2>&1
    # shellcheck disable=SC2086
    apt-get install -qq -y $packages_to_install >/dev/null 2>&1
  fi

  # Check if running as root
  update_progress
  if [[ $EUID -ne 0 ]]; then
    PREFLIGHT_ROOT="✗ Not root"
    PREFLIGHT_ROOT_STATUS="error"
    errors=$((errors + 1))
  else
    PREFLIGHT_ROOT="Running as root"
    PREFLIGHT_ROOT_STATUS="ok"
  fi
  sleep 0.1

  # Check internet connectivity
  update_progress
  if ping -c 1 -W 3 "$DNS_PRIMARY" >/dev/null 2>&1; then
    PREFLIGHT_NET="Available"
    PREFLIGHT_NET_STATUS="ok"
  else
    PREFLIGHT_NET="No connection"
    PREFLIGHT_NET_STATUS="error"
    errors=$((errors + 1))
  fi

  # Check available disk space (need at least 3GB in /root for ISO)
  update_progress
  local free_space_mb
  free_space_mb=$(df -m /root | awk 'NR==2 {print $4}')
  if [[ $free_space_mb -ge $MIN_DISK_SPACE_MB ]]; then
    PREFLIGHT_DISK="${free_space_mb} MB"
    PREFLIGHT_DISK_STATUS="ok"
  else
    PREFLIGHT_DISK="${free_space_mb} MB (need ${MIN_DISK_SPACE_MB}MB+)"
    PREFLIGHT_DISK_STATUS="error"
    errors=$((errors + 1))
  fi
  sleep 0.1

  # Check RAM (need at least 4GB)
  update_progress
  local total_ram_mb
  total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
  if [[ $total_ram_mb -ge $MIN_RAM_MB ]]; then
    PREFLIGHT_RAM="${total_ram_mb} MB"
    PREFLIGHT_RAM_STATUS="ok"
  else
    PREFLIGHT_RAM="${total_ram_mb} MB (need ${MIN_RAM_MB}MB+)"
    PREFLIGHT_RAM_STATUS="error"
    errors=$((errors + 1))
  fi
  sleep 0.1

  # Check CPU cores
  update_progress
  local cpu_cores
  cpu_cores=$(nproc)
  if [[ $cpu_cores -ge 2 ]]; then
    PREFLIGHT_CPU="${cpu_cores} cores"
    PREFLIGHT_CPU_STATUS="ok"
  else
    PREFLIGHT_CPU="${cpu_cores} core(s)"
    PREFLIGHT_CPU_STATUS="warn"
  fi
  sleep 0.1

  # Check if KVM is available (try to load module if not present)
  update_progress
  if [[ $TEST_MODE == true ]]; then
    # Test mode uses TCG emulation, KVM not required
    PREFLIGHT_KVM="TCG (test mode)"
    PREFLIGHT_KVM_STATUS="warn"
  else
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
    if [[ -e /dev/kvm ]]; then
      PREFLIGHT_KVM="Available"
      PREFLIGHT_KVM_STATUS="ok"
    else
      PREFLIGHT_KVM="Not available (use --test for TCG)"
      PREFLIGHT_KVM_STATUS="error"
      errors=$((errors + 1))
    fi
  fi
  sleep 0.1

  # Clear progress line
  printf "\r\033[K"

  PREFLIGHT_ERRORS=$errors
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

# Displays system status summary in formatted table.
# Shows preflight checks and detected storage drives.
# Exits with error if critical checks failed or no drives detected.
show_system_status() {
  detect_drives

  local no_drives=0
  if [[ $DRIVE_COUNT -eq 0 ]]; then
    no_drives=1
  fi

  # Build system info rows
  local sys_rows=""

  # Helper to add row
  add_row() {
    local status="$1"
    local label="$2"
    local value="$3"
    case "$status" in
      ok) sys_rows+="[OK]|${label}|${value}"$'\n' ;;
      warn) sys_rows+="[WARN]|${label}|${value}"$'\n' ;;
      error) sys_rows+="[ERROR]|${label}|${value}"$'\n' ;;
    esac
  }

  add_row "ok" "Installer" "v${VERSION}"
  add_row "$PREFLIGHT_ROOT_STATUS" "Root Access" "$PREFLIGHT_ROOT"
  add_row "$PREFLIGHT_NET_STATUS" "Internet" "$PREFLIGHT_NET"
  add_row "$PREFLIGHT_DISK_STATUS" "Temp Space" "$PREFLIGHT_DISK"
  add_row "$PREFLIGHT_RAM_STATUS" "RAM" "$PREFLIGHT_RAM"
  add_row "$PREFLIGHT_CPU_STATUS" "CPU" "$PREFLIGHT_CPU"
  add_row "$PREFLIGHT_KVM_STATUS" "KVM" "$PREFLIGHT_KVM"

  # Remove trailing newline
  sys_rows="${sys_rows%$'\n'}"

  # Build storage rows
  local storage_rows=""
  if [[ $no_drives -eq 1 ]]; then
    storage_rows="[ERROR]|No drives detected!|"
  else
    for i in "${!DRIVE_NAMES[@]}"; do
      storage_rows+="[OK]|${DRIVE_NAMES[$i]}|${DRIVE_SIZES[$i]}  ${DRIVE_MODELS[$i]:0:25}"
      if [[ $i -lt $((${#DRIVE_NAMES[@]} - 1)) ]]; then
        storage_rows+=$'\n'
      fi
    done
  fi

  # Display with boxes and colorize
  # Inner width = MENU_BOX_WIDTH - 4 (borders) - 2 (padding) = 54
  local inner_width=$((MENU_BOX_WIDTH - 6))
  {
    echo "SYSTEM INFORMATION"
    {
      echo "$sys_rows"
      echo "|--- Storage ---|"
      echo "$storage_rows"
    } | column -t -s '|' | while IFS= read -r line; do
      printf "%-${inner_width}s\n" "$line"
    done
  } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH | colorize_status
  echo ""

  # Check for errors
  if [[ $PREFLIGHT_ERRORS -gt 0 ]]; then
    log "ERROR: Pre-flight checks failed with $PREFLIGHT_ERRORS error(s)"
    exit 1
  fi

  if [[ $no_drives -eq 1 ]]; then
    log "ERROR: No drives detected"
    exit 1
  fi
}
