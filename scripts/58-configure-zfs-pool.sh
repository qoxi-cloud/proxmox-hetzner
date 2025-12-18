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
  if ! load_virtio_mapping; then
    log "ERROR: Failed to load virtio mapping"
    return 1
  fi

  # Build vdev list from ZFS_POOL_DISKS using virtio mapping
  local vdevs_str
  vdevs_str=$(map_disks_to_virtio "space_separated" "${ZFS_POOL_DISKS[@]}")
  if [[ -z $vdevs_str ]]; then
    log "ERROR: Failed to map pool disks to virtio devices"
    return 1
  fi
  read -ra vdevs <<<"$vdevs_str"

  log "INFO: Pool disks: ${vdevs[*]} (RAID: $ZFS_RAID)"

  # Validate disk count vs RAID type
  local vdev_count=${#vdevs[@]}
  if ! validate_zfs_raid_disk_count "$ZFS_RAID" "$vdev_count"; then
    log "ERROR: Invalid RAID configuration for ZFS pool: $ZFS_RAID with $vdev_count disk(s)"
    return 1
  fi

  # Build zpool create command based on RAID type
  local pool_cmd
  pool_cmd=$(build_zpool_command "tank" "$ZFS_RAID" "${vdevs[@]}")
  if [[ -z $pool_cmd ]]; then
    log "ERROR: Failed to build zpool create command"
    return 1
  fi

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
