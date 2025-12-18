# shellcheck shell=bash
# =============================================================================
# Configure separate ZFS pool for VMs
# =============================================================================

# Creates separate ZFS "tank" pool from pool disks when BOOT_DISK is set.
# Only runs when ext4 boot mode is used (BOOT_DISK not empty).
# Configures Proxmox storage: tank for VMs, local for ISO/templates.
# Side effects: Creates ZFS pool, modifies Proxmox storage config
configure_zfs_pool() {
  # Only run when BOOT_DISK is set (ext4 install mode)
  # When BOOT_DISK is empty, all disks are in ZFS rpool (existing behavior)
  if [[ -z $BOOT_DISK ]]; then
    log "INFO: BOOT_DISK not set, skipping separate ZFS pool creation (all-ZFS mode)"
    return 0
  fi

  log "INFO: Creating separate ZFS pool 'tank' from pool disks"

  # Load virtio mapping from QEMU setup
  declare -A VIRTIO_MAP
  if [[ -f /tmp/virtio_map.env ]]; then
    # shellcheck disable=SC1091
    source /tmp/virtio_map.env
  else
    log "ERROR: VIRTIO_MAP not found, cannot map pool disks"
    return 1
  fi

  # Build vdev list from ZFS_POOL_DISKS using virtio mapping
  local vdevs=()
  for disk in "${ZFS_POOL_DISKS[@]}"; do
    local vdev="${VIRTIO_MAP[$disk]}"
    if [[ -z $vdev ]]; then
      log "ERROR: No virtio mapping for pool disk $disk"
      return 1
    fi
    vdevs+=("/dev/$vdev")
  done

  log "INFO: Pool disks: ${vdevs[*]} (RAID: $ZFS_RAID)"

  # Validate disk count vs RAID type
  local vdev_count=${#vdevs[@]}
  case "$ZFS_RAID" in
    single)
      if [[ $vdev_count -ne 1 ]]; then
        log "WARNING: Single disk RAID expects 1 disk, have $vdev_count"
      fi
      ;;
    raid1)
      if [[ $vdev_count -lt 2 ]]; then
        log "ERROR: RAID1 requires at least 2 disks, have $vdev_count"
        return 1
      fi
      ;;
    raidz1)
      if [[ $vdev_count -lt 3 ]]; then
        log "WARNING: RAIDZ1 recommended for 3+ disks, have $vdev_count"
      fi
      ;;
    raidz2)
      if [[ $vdev_count -lt 4 ]]; then
        log "WARNING: RAIDZ2 recommended for 4+ disks, have $vdev_count"
      fi
      ;;
    raid10)
      if [[ $vdev_count -lt 4 ]] || [[ $((vdev_count % 2)) -ne 0 ]]; then
        log "ERROR: RAID10 requires even number of disks (min 4), have $vdev_count"
        return 1
      fi
      ;;
  esac

  # Build zpool create command based on RAID type
  local pool_cmd="zpool create -f tank"
  case "$ZFS_RAID" in
    single)
      pool_cmd+=" ${vdevs[0]}"
      ;;
    raid0)
      pool_cmd+=" ${vdevs[*]}"
      ;;
    raid1)
      pool_cmd+=" mirror ${vdevs[*]}"
      ;;
    raidz1)
      pool_cmd+=" raidz ${vdevs[*]}"
      ;;
    raidz2)
      pool_cmd+=" raidz2 ${vdevs[*]}"
      ;;
    raid10)
      # RAID10: pair up disks for striped mirrors
      # Example: mirror vdb vdc mirror vdd vde
      pool_cmd+=""
      for ((i = 0; i < vdev_count; i += 2)); do
        pool_cmd+=" mirror ${vdevs[$i]} ${vdevs[$((i + 1))]}"
      done
      ;;
    *)
      log "ERROR: Unknown ZFS_RAID type: $ZFS_RAID"
      return 1
      ;;
  esac

  log "INFO: ZFS pool command: $pool_cmd"

  # Create pool and configure Proxmox storage
  if ! run_remote "Creating ZFS pool 'tank'" "
    set -e

    # Create ZFS pool with specified RAID configuration
    $pool_cmd

    # Set recommended ZFS properties
    zfs set compression=lz4 tank
    zfs set atime=off tank
    zfs set relatime=on tank
    zfs set xattr=sa tank
    zfs set dnodesize=auto tank

    # Create dataset for VM disks
    zfs create tank/vm-disks

    # Add tank pool to Proxmox storage config
    pvesm add zfspool tank --pool tank/vm-disks --content images,rootdir

    # Configure local storage (boot disk ext4) for ISO/templates/backups
    pvesm set local --content iso,vztmpl,backup,snippets

    # Verify pool was created
    if ! zpool list | grep -q '^tank '; then
      echo 'ERROR: ZFS pool tank not found after creation'
      exit 1
    fi
  " "ZFS pool 'tank' created"; then
    log "ERROR: Failed to create ZFS pool 'tank'"
    return 1
  fi

  log "INFO: ZFS pool 'tank' created successfully"
  log "INFO: Proxmox storage configured: tank (VMs), local (ISO/templates/backups)"

  return 0
}
