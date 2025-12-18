# shellcheck shell=bash
# =============================================================================
# ZFS Helper Functions
# =============================================================================
# Reusable ZFS utilities for RAID validation, disk mapping, and pool creation

# Validates RAID type against disk count.
# Parameters:
#   $1 - RAID type (single, raid0, raid1, raidz1, raidz2, raidz3, raid10)
#   $2 - Disk count
# Returns:
#   0 - Valid configuration
#   1 - Invalid (error)
#   2 - Valid but with warning
validate_zfs_raid_disk_count() {
  local raid_type="$1"
  local disk_count="$2"

  case "$raid_type" in
    single)
      if [[ $disk_count -ne 1 ]]; then
        log "WARNING: Single disk RAID expects 1 disk, have $disk_count"
        return 2
      fi
      ;;
    raid0)
      # RAID0 accepts any number of disks
      ;;
    raid1)
      if [[ $disk_count -lt 2 ]]; then
        log "ERROR: RAID1 requires at least 2 disks, have $disk_count"
        return 1
      fi
      ;;
    raidz1)
      if [[ $disk_count -lt 3 ]]; then
        log "WARNING: RAIDZ1 recommended for 3+ disks, have $disk_count"
        return 2
      fi
      ;;
    raidz2)
      if [[ $disk_count -lt 4 ]]; then
        log "WARNING: RAIDZ2 recommended for 4+ disks, have $disk_count"
        return 2
      fi
      ;;
    raidz3)
      if [[ $disk_count -lt 5 ]]; then
        log "WARNING: RAIDZ3 recommended for 5+ disks, have $disk_count"
        return 2
      fi
      ;;
    raid10)
      if [[ $disk_count -lt 4 ]] || [[ $((disk_count % 2)) -ne 0 ]]; then
        log "ERROR: RAID10 requires even number of disks (min 4), have $disk_count"
        return 1
      fi
      ;;
    *)
      log "ERROR: Unknown RAID type: $raid_type"
      return 1
      ;;
  esac

  return 0
}

# Loads virtio mapping from /tmp/virtio_map.env.
# Sets global VIRTIO_MAP associative array.
# Returns: 0 on success, 1 if file not found
load_virtio_mapping() {
  declare -g -A VIRTIO_MAP

  if [[ -f /tmp/virtio_map.env ]]; then
    # shellcheck disable=SC1091
    source /tmp/virtio_map.env
    return 0
  else
    log "WARNING: VIRTIO_MAP file not found at /tmp/virtio_map.env"
    return 1
  fi
}

# Maps physical disks to virtio devices.
# Requires: VIRTIO_MAP must be loaded first (via load_virtio_mapping)
# Parameters:
#   $1 - Output format: "toml_array" or "bash_array" or "space_separated"
#   $2+ - Physical disk names (e.g., nvme0n1, sda)
# Returns: Formatted string via stdout
# Example:
#   map_disks_to_virtio "toml_array" nvme0n1 nvme1n1
#   → ["/dev/vda", "/dev/vdb"]
#   map_disks_to_virtio "bash_array" nvme0n1 nvme1n1
#   → (/dev/vda /dev/vdb)
#   map_disks_to_virtio "space_separated" nvme0n1 nvme1n1
#   → /dev/vda /dev/vdb
map_disks_to_virtio() {
  local format="$1"
  shift
  local disks=("$@")

  if [[ ${#disks[@]} -eq 0 ]]; then
    log "ERROR: No disks provided to map_disks_to_virtio"
    return 1
  fi

  local vdevs=()
  for disk in "${disks[@]}"; do
    local vdev="${VIRTIO_MAP[$disk]}"
    if [[ -z $vdev ]]; then
      log "ERROR: No virtio mapping for disk $disk"
      return 1
    fi
    vdevs+=("/dev/$vdev")
  done

  case "$format" in
    toml_array)
      # TOML array format: ["/dev/vda", "/dev/vdb"]
      local result="["
      for i in "${!vdevs[@]}"; do
        result+="\"${vdevs[$i]}\""
        [[ $i -lt $((${#vdevs[@]} - 1)) ]] && result+=", "
      done
      result+="]"
      echo "$result"
      ;;
    bash_array)
      # Bash array format: (/dev/vda /dev/vdb)
      echo "(${vdevs[*]})"
      ;;
    space_separated)
      # Space-separated list: /dev/vda /dev/vdb
      echo "${vdevs[*]}"
      ;;
    *)
      log "ERROR: Unknown format: $format"
      return 1
      ;;
  esac
}

# Builds zpool create command for given RAID type.
# Parameters:
#   $1 - Pool name
#   $2 - RAID type (single, raid0, raid1, raidz1, raidz2, raidz3, raid10)
#   $3+ - Vdev paths (e.g., /dev/vda /dev/vdb)
# Returns: Command string via stdout
# Example:
#   build_zpool_command "tank" "raid1" /dev/vda /dev/vdb
#   → zpool create -f tank mirror /dev/vda /dev/vdb
build_zpool_command() {
  local pool_name="$1"
  local raid_type="$2"
  shift 2
  local vdevs=("$@")

  if [[ -z $pool_name ]]; then
    log "ERROR: Pool name not provided"
    return 1
  fi

  if [[ ${#vdevs[@]} -eq 0 ]]; then
    log "ERROR: No vdevs provided to build_zpool_command"
    return 1
  fi

  local cmd="zpool create -f $pool_name"

  case "$raid_type" in
    single)
      cmd+=" ${vdevs[0]}"
      ;;
    raid0)
      cmd+=" ${vdevs[*]}"
      ;;
    raid1)
      cmd+=" mirror ${vdevs[*]}"
      ;;
    raidz1)
      cmd+=" raidz ${vdevs[*]}"
      ;;
    raidz2)
      cmd+=" raidz2 ${vdevs[*]}"
      ;;
    raidz3)
      cmd+=" raidz3 ${vdevs[*]}"
      ;;
    raid10)
      # RAID10: pair up disks for striped mirrors
      # Example: mirror vda vdb mirror vdc vdd
      local vdev_count=${#vdevs[@]}
      for ((i = 0; i < vdev_count; i += 2)); do
        cmd+=" mirror ${vdevs[$i]} ${vdevs[$((i + 1))]}"
      done
      ;;
    *)
      log "ERROR: Unknown RAID type: $raid_type"
      return 1
      ;;
  esac

  echo "$cmd"
}

# Maps ZFS_RAID to answer.toml format (kebab-case).
# Parameters:
#   $1 - RAID type (single, raid0, raid1, raidz1, raidz2, raidz3, raid10, raid5)
# Returns: TOML-formatted RAID string via stdout
# Example:
#   map_raid_to_toml "raidz1" → "raidz-1"
#   map_raid_to_toml "single" → "raid0"
map_raid_to_toml() {
  local raid="$1"

  case "$raid" in
    single) echo "raid0" ;; # Single disk uses raid0 in TOML
    raid0) echo "raid0" ;;
    raid1) echo "raid1" ;;
    raidz1) echo "raidz-1" ;;
    raidz2) echo "raidz-2" ;;
    raidz3) echo "raidz-3" ;;
    raid5) echo "raidz-1" ;; # Legacy mapping
    raid10) echo "raid10" ;;
    *)
      log "WARNING: Unknown RAID type '$raid', defaulting to raid0"
      echo "raid0"
      ;;
  esac
}
