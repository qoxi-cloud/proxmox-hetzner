# shellcheck shell=bash
# =============================================================================
# ZFS Helper Functions
# =============================================================================
# Reusable ZFS utilities for RAID validation, disk mapping, and pool creation

# Generates virtio device name for a given index.
# Uses Linux kernel naming: vda-vdz, then vdaa-vdaz, vdba-vdbz, etc.
# Parameters:
#   $1 - Index (0-based)
# Returns: Device name (e.g., "vda", "vdz", "vdaa", "vdba") via stdout
_virtio_name_for_index() {
  local idx="$1"
  local letters="abcdefghijklmnopqrstuvwxyz"

  if ((idx < 26)); then
    printf 'vd%s\n' "${letters:$idx:1}"
  else
    # After vdz: vdaa, vdab, ..., vdaz, vdba, ...
    local prefix_idx=$(((idx - 26) / 26))
    local suffix_idx=$(((idx - 26) % 26))
    printf 'vd%s%s\n' "${letters:$prefix_idx:1}" "${letters:$suffix_idx:1}"
  fi
}

# Creates virtio disk mapping file.
# Maps boot disk (if set) to vda, then pool disks to vdb, vdc, etc.
# Parameters:
#   $1 - Boot disk (optional, pass "" if none)
#   $2+ - Pool disks (space-separated)
# Side effects: Creates /tmp/virtio_map.env
# Example:
#   create_virtio_mapping "/dev/nvme2n1" "/dev/nvme0n1" "/dev/nvme1n1"
#   create_virtio_mapping "" "/dev/sda" "/dev/sdb"  # No separate boot disk
create_virtio_mapping() {
  local boot_disk="$1"
  shift
  local pool_disks=("$@")

  declare -A VIRTIO_MAP
  local virtio_idx=0

  # Add boot disk first (if separate)
  if [[ -n $boot_disk ]]; then
    local vdev
    vdev="$(_virtio_name_for_index "$virtio_idx")"
    VIRTIO_MAP["$boot_disk"]="$vdev"
    log "Virtio mapping: $boot_disk → /dev/$vdev (boot)"
    ((virtio_idx++))
  fi

  # Add pool disks (skip if already mapped as boot disk)
  for drive in "${pool_disks[@]}"; do
    if [[ -n ${VIRTIO_MAP[$drive]:-} ]]; then
      log "Virtio mapping: $drive already mapped as boot disk, skipping"
      continue
    fi
    local vdev
    vdev="$(_virtio_name_for_index "$virtio_idx")"
    VIRTIO_MAP["$drive"]="$vdev"
    log "Virtio mapping: $drive → /dev/$vdev (pool)"
    ((virtio_idx++))
  done

  # Export mapping to file (use -gA so it creates global when sourced)
  declare -p VIRTIO_MAP | sed 's/declare -A/declare -gA/' >/tmp/virtio_map.env
  log "Virtio mapping saved to /tmp/virtio_map.env"
}

# Loads virtio mapping from /tmp/virtio_map.env.
# Sets global VIRTIO_MAP associative array.
# Returns: 0 on success, 1 on failure
load_virtio_mapping() {
  if [[ -f /tmp/virtio_map.env ]]; then
    # shellcheck disable=SC1091
    source /tmp/virtio_map.env
    return 0
  else
    log "ERROR: Virtio mapping file not found"
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
#   → ["vda", "vdb"] (short names for answer.toml)
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
      # TOML array format for answer.toml: ["vda", "vdb"] (short names, no /dev/)
      # Proxmox docs: https://pve.proxmox.com/wiki/Automated_Installation
      local result="["
      for i in "${!vdevs[@]}"; do
        local short_name="${vdevs[$i]#/dev/}" # Strip /dev/ prefix
        result+="\"${short_name}\""
        [[ $i -lt $((${#vdevs[@]} - 1)) ]] && result+=", "
      done
      result+="]"
      printf '%s\n' "$result"
      ;;
    bash_array)
      # Bash array format: (/dev/vda /dev/vdb) - for use in scripts
      printf '%s\n' "(${vdevs[*]})"
      ;;
    space_separated)
      # Space-separated list: /dev/vda /dev/vdb - for use in commands
      printf '%s\n' "${vdevs[*]}"
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
      if ((vdev_count < 4)); then
        log "ERROR: raid10 requires at least 4 vdevs, got $vdev_count"
        return 1
      fi
      if ((vdev_count % 2 != 0)); then
        log "ERROR: raid10 requires even number of vdevs, got $vdev_count"
        return 1
      fi
      for ((i = 0; i < vdev_count; i += 2)); do
        cmd+=" mirror ${vdevs[$i]} ${vdevs[$((i + 1))]}"
      done
      ;;
    *)
      log "ERROR: Unknown RAID type: $raid_type"
      return 1
      ;;
  esac

  printf '%s\n' "$cmd"
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
      printf '%s\n' "raid0"
      ;;
  esac
}
