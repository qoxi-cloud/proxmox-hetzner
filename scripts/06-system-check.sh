# shellcheck shell=bash
# =============================================================================
# System checks and hardware detection
# =============================================================================

# Collects and validates system information silently.
# Checks: root access, internet connectivity, disk space, RAM, CPU, KVM.
# Installs required packages if missing.
# Note: Progress is shown via animated banner in 99-main.sh
# Side effects: Sets PREFLIGHT_* global variables, may install packages
collect_system_info() {
  local errors=0

  # Install required tools and display utilities
  # boxes: table display, column: alignment, iproute2: ip command
  # udev: udevadm for interface detection, timeout: command timeouts
  # jq: JSON parsing for API responses
  # aria2c: optional multi-connection downloads (fallback: curl, wget)
  # findmnt: efficient mount point queries
  # gum: interactive prompts and spinners (from Charm repo)
  local packages_to_install=""
  local need_charm_repo=false
  command -v boxes &>/dev/null || packages_to_install+=" boxes"
  command -v column &>/dev/null || packages_to_install+=" bsdmainutils"
  command -v ip &>/dev/null || packages_to_install+=" iproute2"
  command -v udevadm &>/dev/null || packages_to_install+=" udev"
  command -v timeout &>/dev/null || packages_to_install+=" coreutils"
  command -v curl &>/dev/null || packages_to_install+=" curl"
  command -v jq &>/dev/null || packages_to_install+=" jq"
  command -v aria2c &>/dev/null || packages_to_install+=" aria2"
  command -v findmnt &>/dev/null || packages_to_install+=" util-linux"
  command -v gum &>/dev/null || {
    need_charm_repo=true
    packages_to_install+=" gum"
  }

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
  if [[ $EUID -ne 0 ]]; then
    PREFLIGHT_ROOT="✗ Not root"
    PREFLIGHT_ROOT_STATUS="error"
    errors=$((errors + 1))
  else
    PREFLIGHT_ROOT="Running as root"
    PREFLIGHT_ROOT_STATUS="ok"
  fi

  # Check internet connectivity
  if ping -c 1 -W 3 "$DNS_PRIMARY" >/dev/null 2>&1; then
    PREFLIGHT_NET="Available"
    PREFLIGHT_NET_STATUS="ok"
  else
    PREFLIGHT_NET="No connection"
    PREFLIGHT_NET_STATUS="error"
    errors=$((errors + 1))
  fi

  # Check available disk space (need at least 3GB in /root for ISO)
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

  # Check RAM (need at least 4GB)
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

  # Check CPU cores
  local cpu_cores
  cpu_cores=$(nproc)
  if [[ $cpu_cores -ge 2 ]]; then
    PREFLIGHT_CPU="${cpu_cores} cores"
    PREFLIGHT_CPU_STATUS="ok"
  else
    PREFLIGHT_CPU="${cpu_cores} core(s)"
    PREFLIGHT_CPU_STATUS="warn"
  fi

  # Check if KVM is available (try to load module if not present)
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
    PREFLIGHT_KVM="Not available"
    PREFLIGHT_KVM_STATUS="error"
    errors=$((errors + 1))
  fi

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

  # Build table data with colored status markers
  # Format: ,,\n then Header,Header,Header\n then data rows
  local table_data
  table_data=",,
Status,Item,Value
"

  # Helper to format status with color using gum style
  format_status() {
    local status="$1"
    case "$status" in
      ok) gum style --foreground "$HEX_CYAN" "[OK]" ;;
      warn) gum style --foreground "$HEX_YELLOW" "[WARN]" ;;
      error) gum style --foreground "$HEX_RED" "[ERROR]" ;;
    esac
  }

  # Helper to add row
  add_row() {
    local status="$1"
    local label="$2"
    local value="$3"
    local status_text
    status_text=$(format_status "$status")
    table_data+="${status_text},${label},${value}
"
  }

  add_row "ok" "Installer" "v${VERSION}"
  add_row "$PREFLIGHT_ROOT_STATUS" "Root Access" "$PREFLIGHT_ROOT"
  add_row "$PREFLIGHT_NET_STATUS" "Internet" "$PREFLIGHT_NET"
  add_row "$PREFLIGHT_DISK_STATUS" "Temp Space" "$PREFLIGHT_DISK"
  add_row "$PREFLIGHT_RAM_STATUS" "RAM" "$PREFLIGHT_RAM"
  add_row "$PREFLIGHT_CPU_STATUS" "CPU" "$PREFLIGHT_CPU"
  add_row "$PREFLIGHT_KVM_STATUS" "KVM" "$PREFLIGHT_KVM"

  # Add storage rows
  if [[ $no_drives -eq 1 ]]; then
    local error_status
    error_status=$(format_status "error")
    table_data+="${error_status},No drives detected!,
"
  else
    for i in "${!DRIVE_NAMES[@]}"; do
      local ok_status
      ok_status=$(format_status "ok")
      table_data+="${ok_status},${DRIVE_NAMES[$i]},${DRIVE_SIZES[$i]}  ${DRIVE_MODELS[$i]:0:25}
"
    done
  fi

  # Remove trailing newline
  table_data="${table_data%$'\n'}"

  # Display table using gum table
  echo "$table_data" | gum table \
    --print \
    --border "none" \
    --cell.foreground "$HEX_GRAY" \
    --header.foreground "$HEX_ORANGE"

  echo ""

  # Determine if there are critical errors
  local has_errors=false
  if [[ $PREFLIGHT_ERRORS -gt 0 || $no_drives -eq 1 ]]; then
    has_errors=true
  fi

  # Show confirmation dialog using gum confirm
  if [[ $has_errors == true ]]; then
    # Show error message and only allow Cancel
    print_error "System requirements not met. Please fix the issues above."
    echo ""
    gum confirm "Exit installer?" \
      --affirmative "Exit" \
      --negative "" \
      --default=true \
      --prompt.foreground "#ff8700" \
      --selected.background "#ff8700" \
      --unselected.foreground "#585858" || true
    log "ERROR: Pre-flight checks failed"
    exit 1
  else
    # Allow user to continue or cancel
    if ! gum confirm "Start configuration?" \
      --affirmative "Start" \
      --negative "Cancel" \
      --default=true \
      --prompt.foreground "#ff8700" \
      --selected.background "#ff8700" \
      --unselected.foreground "#585858"; then
      log "INFO: User cancelled installation"
      print_info "Installation cancelled by user"
      exit 0
    fi

    # Clear screen and show logo after Start is pressed
    clear
    show_banner
    echo ""
  fi
}
