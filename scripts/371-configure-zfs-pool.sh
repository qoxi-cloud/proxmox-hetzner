# shellcheck shell=bash
# Configure separate ZFS pool for VMs

# Imports existing ZFS pool and configures Proxmox storage.
# Uses EXISTING_POOL_NAME global variable.
# Import existing ZFS pool, find/create vm-disks dataset
_config_import_existing_pool() {
  local pool_name="$EXISTING_POOL_NAME"
  log "INFO: Importing existing ZFS pool '$pool_name'"

  # Import pool with force flag (may have been used by different system)
  if ! remote_run "Importing ZFS pool '$pool_name'" \
    "zpool import -f '$pool_name' 2>/dev/null || zpool import -f -d /dev '$pool_name'" \
    "ZFS pool '$pool_name' imported"; then
    log "ERROR: Failed to import ZFS pool '$pool_name'"
    return 1
  fi

  # Configure Proxmox storage - find or create vm-disks dataset
  # shellcheck disable=SC2016
  if ! remote_run "Configuring Proxmox storage for '$pool_name'" '
    if zfs list "'"$pool_name"'/vm-disks" >/dev/null 2>&1; then ds="'"$pool_name"'/vm-disks"
    else ds=$(zfs list -H -o name -r "'"$pool_name"'" 2>/dev/null | grep -v "^'"$pool_name"'\$" | head -1)
      [[ -z $ds ]] && { zfs create "'"$pool_name"'/vm-disks"; ds="'"$pool_name"'/vm-disks"; }
    fi
    pvesm status "'"$pool_name"'" >/dev/null 2>&1 || pvesm add zfspool "'"$pool_name"'" --pool "$ds" --content images,rootdir
    pvesm set local --content iso,vztmpl,backup,snippets
  ' "Proxmox storage configured for '$pool_name'"; then
    log "ERROR: Failed to configure Proxmox storage for '$pool_name'"
    return 1
  fi

  log "INFO: Existing ZFS pool '$pool_name' imported and configured"
  return 0
}

# Creates new ZFS pool 'tank' from ZFS_POOL_DISKS.
# Uses ZFS_RAID global for RAID configuration.
# Create new ZFS pool with optimal settings
_config_create_new_pool() {
  log "INFO: Creating separate ZFS pool 'tank' from pool disks"

  # Load virtio mapping from QEMU setup
  if ! load_virtio_mapping; then
    log "ERROR: Failed to load virtio mapping"
    return 1
  fi

  # Map physical disks to virtio devices
  local vdevs_str
  vdevs_str=$(map_disks_to_virtio "space_separated" "${ZFS_POOL_DISKS[@]}")
  if [[ -z $vdevs_str ]]; then
    log "ERROR: Failed to map pool disks to virtio devices"
    return 1
  fi
  read -ra vdevs <<<"$vdevs_str"
  log "INFO: Pool disks: ${vdevs[*]} (RAID: $ZFS_RAID)"

  # Build zpool create command based on RAID type
  local pool_cmd
  pool_cmd=$(build_zpool_command "tank" "$ZFS_RAID" "${vdevs[@]}")
  if [[ -z $pool_cmd ]]; then
    log "ERROR: Failed to build zpool create command"
    return 1
  fi
  log "INFO: ZFS pool command: $pool_cmd"

  # Create pool, set properties, configure Proxmox storage
  if ! remote_run "Creating ZFS pool 'tank'" "
    $pool_cmd
    zfs set compression=lz4 tank && zfs set atime=off tank && zfs set xattr=sa tank && zfs set dnodesize=auto tank
    zfs create tank/vm-disks && pvesm add zfspool tank --pool tank/vm-disks --content images,rootdir
    pvesm set local --content iso,vztmpl,backup,snippets
  " "ZFS pool 'tank' created"; then
    log "ERROR: Failed to create ZFS pool 'tank'"
    return 1
  fi

  log "INFO: ZFS pool 'tank' created successfully"
  return 0
}

# Main entry point - creates or imports ZFS pool based on configuration.
# Only runs when BOOT_DISK is set (ext4 install mode).
# When BOOT_DISK is empty, all disks are in ZFS rpool (existing behavior).
_config_zfs_pool() {
  if [[ -z $BOOT_DISK ]]; then
    log "INFO: BOOT_DISK not set, skipping separate ZFS pool (all-ZFS mode)"
    return 0
  fi

  if [[ $USE_EXISTING_POOL == "yes" ]]; then
    _config_import_existing_pool
  else
    _config_create_new_pool
  fi
}

# Public wrapper

# Creates or imports ZFS pool when BOOT_DISK is set.
# Modes: USE_EXISTING_POOL=yes imports existing pool, otherwise creates new 'tank'.
# Configures Proxmox storage: pool for VMs, local for ISO/templates.
configure_zfs_pool() {
  _config_zfs_pool
}
