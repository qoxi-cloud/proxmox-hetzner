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
  # Mapping: command -> package name
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
      # gum requires Charm repo (not in default Debian repos)
      [[ $cmd == "gum" ]] && need_charm_repo=true
    fi
  done

  # Add Charm repo for gum if needed (not in default Debian repos)
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

  # Check available disk space (need at least 6GB in /root for ISO + QEMU + overhead)
  if validate_disk_space "/root" "$MIN_DISK_SPACE_MB"; then
    PREFLIGHT_DISK="${DISK_SPACE_MB} MB"
    PREFLIGHT_DISK_STATUS="ok"
  else
    PREFLIGHT_DISK="${DISK_SPACE_MB:-0} MB (need ${MIN_DISK_SPACE_MB}MB+)"
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

  # Network interface detection
  # Get default interface name (the one with default route)
  # Prefer JSON output with jq for more reliable parsing
  if command -v ip &>/dev/null && command -v jq &>/dev/null; then
    CURRENT_INTERFACE=$(ip -j route 2>/dev/null | jq -r '.[] | select(.dst == "default") | .dev' | head -n1)
  elif command -v ip &>/dev/null; then
    CURRENT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
  elif command -v route &>/dev/null; then
    # Fallback to route command (older systems)
    CURRENT_INTERFACE=$(route -n | awk '/^0\.0\.0\.0/ {print $8}' | head -n1)
  fi

  if [[ -z $CURRENT_INTERFACE ]]; then
    # Last resort: try to find first non-loopback interface
    if command -v ip &>/dev/null && command -v jq &>/dev/null; then
      CURRENT_INTERFACE=$(ip -j link show 2>/dev/null | jq -r '.[] | select(.ifname != "lo" and .operstate == "UP") | .ifname' | head -n1)
    elif command -v ip &>/dev/null; then
      CURRENT_INTERFACE=$(ip link show | awk -F': ' '/^[0-9]+:/ && !/lo:/ {print $2; exit}')
    elif command -v ifconfig &>/dev/null; then
      CURRENT_INTERFACE=$(ifconfig -a | awk '/^[a-z]/ && !/^lo/ {print $1; exit}' | tr -d ':')
    fi
  fi

  if [[ -z $CURRENT_INTERFACE ]]; then
    CURRENT_INTERFACE="eth0"
    log "WARNING: Could not detect network interface, defaulting to eth0"
  fi

  # CRITICAL: Get the predictable interface name for bare metal
  # Rescue System often uses eth0, but Proxmox uses predictable naming
  PREDICTABLE_NAME=""

  # Try to get predictable name from udev
  if [[ -e "/sys/class/net/${CURRENT_INTERFACE}" ]]; then
    # Get udevadm info once and extract names
    local udev_info
    udev_info=$(udevadm info "/sys/class/net/${CURRENT_INTERFACE}" 2>/dev/null)

    # Try ID_NET_NAME_PATH first (most reliable for PCIe devices)
    PREDICTABLE_NAME=$(printf '%s\n' "$udev_info" | grep "ID_NET_NAME_PATH=" | cut -d'=' -f2)

    # Fallback to ID_NET_NAME_ONBOARD (for onboard NICs)
    if [[ -z $PREDICTABLE_NAME ]]; then
      PREDICTABLE_NAME=$(printf '%s\n' "$udev_info" | grep "ID_NET_NAME_ONBOARD=" | cut -d'=' -f2)
    fi

    # Fallback to altname from ip link
    if [[ -z $PREDICTABLE_NAME ]]; then
      PREDICTABLE_NAME=$(ip -d link show "$CURRENT_INTERFACE" 2>/dev/null | grep "altname" | awk '{print $2}' | head -1)
    fi
  fi

  # Use predictable name if found
  if [[ -n $PREDICTABLE_NAME ]]; then
    DEFAULT_INTERFACE="$PREDICTABLE_NAME"
  else
    DEFAULT_INTERFACE="$CURRENT_INTERFACE"
  fi

  # Get all available interfaces and their altnames for display
  AVAILABLE_ALTNAMES=$(ip -d link show | grep -v "lo:" | grep -E '(^[0-9]+:|altname)' | awk '/^[0-9]+:/ {interface=$2; gsub(/:/, "", interface); printf "%s", interface} /altname/ {printf ", %s", $2} END {print ""}' | sed 's/, $//')

  # Get all available non-loopback interfaces (for wizard selection)
  if command -v ip &>/dev/null && command -v jq &>/dev/null; then
    AVAILABLE_INTERFACES=$(ip -j link show 2>/dev/null | jq -r '.[] | select(.ifname != "lo") | .ifname' | sort)
  elif command -v ip &>/dev/null; then
    AVAILABLE_INTERFACES=$(ip link show | awk -F': ' '/^[0-9]+:/ && !/lo:/ {print $2}' | sort)
  else
    AVAILABLE_INTERFACES="$CURRENT_INTERFACE"
  fi

  # Count available interfaces
  INTERFACE_COUNT=$(printf '%s\n' "$AVAILABLE_INTERFACES" | wc -l)

  # Set INTERFACE_NAME to default if not already set
  if [[ -z $INTERFACE_NAME ]]; then
    INTERFACE_NAME="$DEFAULT_INTERFACE"
  fi

  # Collect network information from current interface
  local max_attempts=3
  local attempt=0

  # Try to get IPv4 info with retries
  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))

    # Try detection methods in order of preference
    if command -v ip &>/dev/null && command -v jq &>/dev/null; then
      MAIN_IPV4_CIDR=$(ip -j address show "$CURRENT_INTERFACE" 2>/dev/null | jq -r '.[0].addr_info[] | select(.family == "inet" and .scope == "global") | "\(.local)/\(.prefixlen)"' | head -n1)
      MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
      MAIN_IPV4_GW=$(ip -j route 2>/dev/null | jq -r '.[] | select(.dst == "default") | .gateway' | head -n1)
      [[ -n $MAIN_IPV4 ]] && [[ -n $MAIN_IPV4_GW ]] && break
    elif command -v ip &>/dev/null; then
      MAIN_IPV4_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null | grep global | grep "inet " | awk '{print $2}' | head -n1)
      MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
      MAIN_IPV4_GW=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -n1)
      [[ -n $MAIN_IPV4 ]] && [[ -n $MAIN_IPV4_GW ]] && break
    elif command -v ifconfig &>/dev/null; then
      MAIN_IPV4=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null | awk '/inet / {print $2}' | sed 's/addr://')
      local netmask
      netmask=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null | awk '/inet / {print $4}' | sed 's/Mask://')
      # Convert netmask to CIDR if available
      if [[ -n $MAIN_IPV4 ]] && [[ -n $netmask ]]; then
        case "$netmask" in
          255.255.255.0) MAIN_IPV4_CIDR="${MAIN_IPV4}/24" ;;
          255.255.255.128) MAIN_IPV4_CIDR="${MAIN_IPV4}/25" ;;
          255.255.255.192) MAIN_IPV4_CIDR="${MAIN_IPV4}/26" ;;
          255.255.255.224) MAIN_IPV4_CIDR="${MAIN_IPV4}/27" ;;
          255.255.255.240) MAIN_IPV4_CIDR="${MAIN_IPV4}/28" ;;
          255.255.255.248) MAIN_IPV4_CIDR="${MAIN_IPV4}/29" ;;
          255.255.255.252) MAIN_IPV4_CIDR="${MAIN_IPV4}/30" ;;
          255.255.0.0) MAIN_IPV4_CIDR="${MAIN_IPV4}/16" ;;
          *) MAIN_IPV4_CIDR="${MAIN_IPV4}/24" ;;
        esac
      fi
      # Get gateway via route command
      if command -v route &>/dev/null; then
        MAIN_IPV4_GW=$(route -n 2>/dev/null | awk '/^0\.0\.0\.0/ {print $2}' | head -n1)
      fi
      [[ -n $MAIN_IPV4 ]] && [[ -n $MAIN_IPV4_GW ]] && break
    fi

    if [[ $attempt -lt $max_attempts ]]; then
      log "Network info attempt $attempt failed, retrying in 2 seconds..."
      sleep 2
    fi
  done

  # Get MAC address and IPv6 info
  if command -v ip &>/dev/null && command -v jq &>/dev/null; then
    MAC_ADDRESS=$(ip -j link show "$CURRENT_INTERFACE" 2>/dev/null | jq -r '.[0].address // empty')
    IPV6_CIDR=$(ip -j address show "$CURRENT_INTERFACE" 2>/dev/null | jq -r '.[0].addr_info[] | select(.family == "inet6" and .scope == "global") | "\(.local)/\(.prefixlen)"' | head -n1)
  elif command -v ip &>/dev/null; then
    MAC_ADDRESS=$(ip link show "$CURRENT_INTERFACE" 2>/dev/null | awk '/ether/ {print $2}')
    IPV6_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null | grep global | grep "inet6 " | awk '{print $2}' | head -n1)
  elif command -v ifconfig &>/dev/null; then
    MAC_ADDRESS=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null | awk '/ether/ {print $2}')
    IPV6_CIDR=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null | awk '/inet6/ && /global/ {print $2}')
  fi
  MAIN_IPV6="${IPV6_CIDR%/*}"

  # Calculate IPv6 prefix for VM network
  if [[ -n $IPV6_CIDR ]]; then
    # Extract first 4 groups of IPv6 using parameter expansion
    local ipv6_prefix="${MAIN_IPV6%%:*:*:*:*}"
    # Fallback: if expansion didn't work as expected, use cut
    if [[ $ipv6_prefix == "$MAIN_IPV6" ]] || [[ -z $ipv6_prefix ]]; then
      ipv6_prefix=$(printf '%s' "$MAIN_IPV6" | cut -d':' -f1-4)
    fi
    FIRST_IPV6_CIDR="${ipv6_prefix}:1::1/80"
  else
    FIRST_IPV6_CIDR=""
  fi

  # Determine IPv6 gateway (auto-detect fe80 link-local or use provided)
  if [[ -n $MAIN_IPV6 ]]; then
    if command -v ip &>/dev/null; then
      IPV6_GATEWAY=$(ip -6 route 2>/dev/null | grep default | awk '{print $3}' | head -n1)
    fi
    # If no gateway found, will be set to "auto" in input phase
  fi

  # Load dynamic data for wizard (timezones, countries, TZ mapping)
  _load_wizard_data
}

# Loads available timezones from system for wizard selection.
# Uses timedatectl if available, falls back to parsing zoneinfo directory.
# Side effects: Sets WIZ_TIMEZONES global variable
_load_timezones() {
  if command -v timedatectl &>/dev/null; then
    WIZ_TIMEZONES=$(timedatectl list-timezones 2>/dev/null)
  else
    # Fallback: parse zoneinfo directory
    WIZ_TIMEZONES=$(find /usr/share/zoneinfo -type f 2>/dev/null \
      | sed 's|/usr/share/zoneinfo/||' \
      | grep -E '^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/' \
      | sort)
  fi
  # Add UTC at the end
  WIZ_TIMEZONES+=$'\nUTC'
}

# Loads ISO 3166-1 alpha-2 country codes for wizard selection.
# Uses iso-codes package if available, falls back to locale data.
# Side effects: Sets WIZ_COUNTRIES global variable
_load_countries() {
  local iso_file="/usr/share/iso-codes/json/iso_3166-1.json"
  if [[ -f $iso_file ]]; then
    # Parse JSON with grep (no jq dependency for this)
    WIZ_COUNTRIES=$(grep -oP '"alpha_2":\s*"\K[^"]+' "$iso_file" | tr '[:upper:]' '[:lower:]' | sort)
  else
    # Fallback: extract from locale data
    WIZ_COUNTRIES=$(locale -a 2>/dev/null | grep -oP '^[a-z]{2}(?=_)' | sort -u)
  fi
}

# Builds timezone to country mapping from zone.tab file.
# Used for auto-selecting country based on timezone selection.
# Side effects: Sets TZ_TO_COUNTRY associative array
_build_tz_to_country() {
  declare -gA TZ_TO_COUNTRY
  local zone_tab="/usr/share/zoneinfo/zone.tab"
  [[ -f $zone_tab ]] || return 0

  while IFS=$'\t' read -r country _ tz _; do
    [[ $country == \#* ]] && continue
    [[ -z $tz ]] && continue
    TZ_TO_COUNTRY["$tz"]="${country,,}" # lowercase
  done <"$zone_tab"
}

# Loads all dynamic wizard data from system.
# Orchestrates loading of timezones, countries, and TZ-to-country mapping.
# Called by collect_system_info() during initialization.
_load_wizard_data() {
  _load_timezones
  _load_countries
  _build_tz_to_country
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

  # Note: ZFS_RAID defaults can be overridden by user via environment variable

}

# Smart disk allocation based on size differences.
# If mixed sizes: smallest → boot, rest → pool
# If identical: all → pool (legacy behavior)
# Side effects: Sets BOOT_DISK, ZFS_POOL_DISKS
detect_disk_roles() {
  [[ $DRIVE_COUNT -eq 0 ]] && return 1

  # Parse sizes to bytes for comparison
  local size_bytes=()
  for size in "${DRIVE_SIZES[@]}"; do
    local bytes
    if [[ $size =~ ([0-9.]+)T ]]; then
      bytes=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * 1099511627776}")
    elif [[ $size =~ ([0-9.]+)G ]]; then
      bytes=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * 1073741824}")
    else
      bytes=0
    fi
    size_bytes+=("$bytes")
  done

  # Find min/max sizes
  local min_size=${size_bytes[0]}
  local max_size=${size_bytes[0]}
  for size in "${size_bytes[@]}"; do
    [[ $size -lt $min_size ]] && min_size=$size
    [[ $size -gt $max_size ]] && max_size=$size
  done

  # Check if sizes differ by >10%
  local size_diff=$((max_size - min_size))
  local threshold=$((min_size / 10))

  if [[ $size_diff -le $threshold ]]; then
    # All same size → all in pool
    log "All disks same size, using all for ZFS pool"
    BOOT_DISK=""
    ZFS_POOL_DISKS=("${DRIVES[@]}")
  else
    # Mixed sizes → smallest = boot, rest = pool
    log "Mixed disk sizes, using smallest for boot"
    local smallest_idx=0
    for i in "${!size_bytes[@]}"; do
      [[ ${size_bytes[$i]} -lt ${size_bytes[$smallest_idx]} ]] && smallest_idx=$i
    done

    BOOT_DISK="${DRIVES[$smallest_idx]}"
    ZFS_POOL_DISKS=()
    for i in "${!DRIVES[@]}"; do
      [[ $i -ne $smallest_idx ]] && ZFS_POOL_DISKS+=("${DRIVES[$i]}")
    done
  fi

  log "Boot disk: ${BOOT_DISK:-all in pool}"
  log "Pool disks: ${ZFS_POOL_DISKS[*]}"
}

# Displays system status summary in formatted table.
# Only shows table if there are errors, then exits.
# If all checks pass, silently proceeds to wizard.
show_system_status() {
  detect_drives
  detect_disk_roles

  local no_drives=0
  if [[ $DRIVE_COUNT -eq 0 ]]; then
    no_drives=1
  fi

  # Check for errors first
  local has_errors=false
  if [[ $PREFLIGHT_ERRORS -gt 0 || $no_drives -eq 1 ]]; then
    has_errors=true
  fi

  # If no errors, go straight to wizard
  if [[ $has_errors == false ]]; then
    _wiz_start_edit
    return 0
  fi

  # Build table data with colored status markers
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
  printf '%s\n' "$table_data" | gum table \
    --print \
    --border "none" \
    --cell.foreground "$HEX_GRAY" \
    --header.foreground "$HEX_ORANGE"

  printf '\n'
  print_error "System requirements not met. Please fix the issues above."
  printf '\n'
  log "ERROR: Pre-flight checks failed"
  exit 1
}
