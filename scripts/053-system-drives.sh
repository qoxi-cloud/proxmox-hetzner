# shellcheck shell=bash
# Drive detection and role assignment

# Detect available drives. Sets DRIVES, DRIVE_COUNT, DRIVE_NAMES/SIZES/MODELS.
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
}

# Get disks in existing ZFS pools → stdout (one per line)
_get_existing_pool_disks() {
  local pool_disks=()
  for pool_info in "${DETECTED_POOLS[@]}"; do
    # Format: "name|status|/dev/disk1,/dev/disk2"
    local disks_csv="${pool_info##*|}"
    IFS=',' read -ra disks <<<"$disks_csv"
    pool_disks+=("${disks[@]}")
  done
  printf '%s\n' "${pool_disks[@]}"
}

# Check if disk is in ZFS pool. $1=disk_path. Returns: 0=in pool, 1=not
_disk_in_existing_pool() {
  local disk="$1"
  local pool_disk
  while IFS= read -r pool_disk; do
    [[ $pool_disk == "$disk" ]] && return 0
  done < <(_get_existing_pool_disks)
  return 1
}

# Smart disk allocation based on size differences.
# Auto-detect boot/pool disk roles. Sets BOOT_DISK, ZFS_POOL_DISKS.
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
    # Mixed sizes → smallest (that's NOT in an existing pool) = boot, rest = pool
    log "Mixed disk sizes, selecting boot disk"

    # Find smallest disk that's not part of an existing pool
    local smallest_idx=-1
    local smallest_size=0
    for i in "${!size_bytes[@]}"; do
      local drive="${DRIVES[$i]}"
      local drive_size="${size_bytes[$i]}"

      # Skip disks that are part of existing pools
      if _disk_in_existing_pool "$drive"; then
        log "  $drive: ${DRIVE_SIZES[$i]} (skipped - part of existing pool)"
        continue
      fi

      # Track smallest available disk
      if [[ $smallest_idx -eq -1 ]] || [[ $drive_size -lt $smallest_size ]]; then
        smallest_idx=$i
        smallest_size=$drive_size
      fi
    done

    if [[ $smallest_idx -eq -1 ]]; then
      # All disks are in existing pools - can't auto-select boot disk
      log "WARNING: All disks belong to existing pools, no automatic boot disk selection"
      BOOT_DISK=""
      ZFS_POOL_DISKS=("${DRIVES[@]}")
    else
      BOOT_DISK="${DRIVES[$smallest_idx]}"
      log "Boot disk: $BOOT_DISK (smallest available, ${DRIVE_SIZES[$smallest_idx]})"

      ZFS_POOL_DISKS=()
      for i in "${!DRIVES[@]}"; do
        [[ $i -ne $smallest_idx ]] && ZFS_POOL_DISKS+=("${DRIVES[$i]}")
      done
    fi
  fi

  log "Boot disk: ${BOOT_DISK:-all in pool}"
  log "Pool disks: ${ZFS_POOL_DISKS[*]}"
}

# Existing ZFS pool detection

# Detect existing ZFS pools → stdout "name|status|disks" per line
detect_existing_pools() {
  # Check if zpool command exists
  command -v zpool &>/dev/null || return 0

  local pools=()

  # Get importable pools (not currently imported)
  # zpool import without args lists all pools available for import
  local import_output
  import_output=$(zpool import 2>&1) || true

  # Check if output contains pool info (not just "no pools available")
  if [[ -z $import_output ]] || [[ $import_output == *"no pools available"* ]]; then
    return 0
  fi

  # Parse zpool import output
  # Format:
  #   pool: tankname
  #      id: 12345
  #   state: ONLINE
  #  action: The pool can be imported...
  #  config:
  #      tankname    ONLINE
  #        mirror-0  ONLINE
  #          nvme0n1 ONLINE
  #          nvme1n1 ONLINE

  local current_pool=""
  local current_state=""
  local current_disks=""
  local in_config=false

  while IFS= read -r line; do
    # Pool name
    if [[ $line =~ ^[[:space:]]*pool:[[:space:]]*(.+)$ ]]; then
      # Save previous pool if exists
      if [[ -n $current_pool ]]; then
        pools+=("${current_pool}|${current_state}|${current_disks}")
      fi
      current_pool="${BASH_REMATCH[1]}"
      current_state=""
      current_disks=""
      in_config=false
    # State
    elif [[ $line =~ ^[[:space:]]*state:[[:space:]]*(.+)$ ]]; then
      current_state="${BASH_REMATCH[1]}"
    # Config section start
    elif [[ $line =~ ^[[:space:]]*config: ]]; then
      in_config=true
    # Disk entries - match common disk patterns
    elif [[ $in_config == true ]]; then
      # Match: nvme0n1, sda, vda, xvda, hda, etc (with partition suffix optional)
      if [[ $line =~ ^[[:space:]]+(nvme[0-9]+n[0-9]+|[shxv]d[a-z]+)[p0-9]*[[:space:]] ]]; then
        local disk="${BASH_REMATCH[1]}"
        if [[ -n $current_disks ]]; then
          current_disks="${current_disks},/dev/${disk}"
        else
          current_disks="/dev/${disk}"
        fi
      fi
    fi
  done <<<"$import_output"

  # Save last pool
  if [[ -n $current_pool ]]; then
    pools+=("${current_pool}|${current_state}|${current_disks}")
  fi

  # Output pools
  for pool in "${pools[@]}"; do
    printf '%s\n' "$pool"
  done
}

# Get disks in pool. $1=pool_name → comma-separated disk paths
get_pool_disks() {
  local pool_name="$1"

  for line in "${DETECTED_POOLS[@]}"; do
    local name="${line%%|*}"
    if [[ $name == "$pool_name" ]]; then
      local rest="${line#*|}"
      printf '%s\n' "${rest#*|}"
      return 0
    fi
  done

  return 1
}

# Stores detected pools for wizard use
# Format: DETECTED_POOLS[0]="name|status|disks"
DETECTED_POOLS=()
