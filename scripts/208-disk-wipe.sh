# shellcheck shell=bash
# Disk wipe functions - clean disks before installation

# Get all disks selected for installation (boot + pool)
_get_install_disks() {
  local disks=()
  [[ -n $BOOT_DISK ]] && disks+=("$BOOT_DISK")
  for disk in "${ZFS_POOL_DISKS[@]}"; do
    # Avoid duplicates
    local found=false
    for d in "${disks[@]}"; do
      [[ $d == "$disk" ]] && found=true && break
    done
    [[ $found == false ]] && disks+=("$disk")
  done
  printf '%s\n' "${disks[@]}"
}

# Destroy ZFS pools on disk. $1=disk
_wipe_zfs_on_disk() {
  local disk="$1"
  local disk_name
  disk_name=$(basename "$disk")

  command -v zpool &>/dev/null || return 0

  # Find pools using this disk (check both imported and importable)
  local pools_to_destroy=()

  # Check imported pools first
  while IFS= read -r pool; do
    [[ -z $pool ]] && continue
    # Check if pool uses this disk
    if zpool status "$pool" 2>/dev/null | grep -qE "(^|[[:space:]])${disk_name}([p0-9]*)?([[:space:]]|$)"; then
      pools_to_destroy+=("$pool")
    fi
  done < <(zpool list -H -o name 2>/dev/null)

  # Also check importable pools from zpool import output
  local import_output
  import_output=$(zpool import 2>&1) || true
  if [[ -n $import_output && $import_output != *"no pools available"* ]]; then
    local current_pool=""
    local pool_has_disk=false
    while IFS= read -r line; do
      if [[ $line =~ ^[[:space:]]*pool:[[:space:]]*(.+)$ ]]; then
        # Save previous pool if it had our disk
        if [[ $pool_has_disk == true && -n $current_pool ]]; then
          # Check not already in list
          local already=false
          for p in "${pools_to_destroy[@]}"; do
            [[ $p == "$current_pool" ]] && already=true && break
          done
          [[ $already == false ]] && pools_to_destroy+=("$current_pool")
        fi
        current_pool="${BASH_REMATCH[1]}"
        pool_has_disk=false
      elif [[ $line =~ $disk_name ]]; then
        pool_has_disk=true
      fi
    done <<<"$import_output"
    # Don't forget last pool
    if [[ $pool_has_disk == true && -n $current_pool ]]; then
      local already=false
      for p in "${pools_to_destroy[@]}"; do
        [[ $p == "$current_pool" ]] && already=true && break
      done
      [[ $already == false ]] && pools_to_destroy+=("$current_pool")
    fi
  fi

  # Destroy each pool
  for pool in "${pools_to_destroy[@]}"; do
    log "Destroying ZFS pool: $pool (contains $disk)"
    # Try export first (safer), then force destroy
    zpool export -f "$pool" 2>/dev/null || true
    zpool destroy -f "$pool" 2>/dev/null || true
  done

  # Clear ZFS labels from disk and partitions
  for part in "${disk}"*; do
    # shellcheck disable=SC2015 # || true is fallback, not else branch
    [[ -b $part ]] && zpool labelclear -f "$part" 2>/dev/null || true
  done
}

# Remove LVM on disk. $1=disk
_wipe_lvm_on_disk() {
  local disk="$1"

  command -v pvs &>/dev/null || return 0

  # Find PVs on this disk (including partitions)
  local pvs_on_disk=()
  while IFS= read -r pv; do
    [[ -z $pv ]] && continue
    [[ $pv == "${disk}"* ]] && pvs_on_disk+=("$pv")
  done < <(pvs --noheadings -o pv_name 2>/dev/null | tr -d ' ')

  for pv in "${pvs_on_disk[@]}"; do
    # Get VG name for this PV
    local vg
    vg=$(pvs --noheadings -o vg_name "$pv" 2>/dev/null | tr -d ' ')

    if [[ -n $vg ]]; then
      log "Removing LVM VG: $vg (on $pv)"
      # Deactivate all LVs in VG
      vgchange -an "$vg" 2>/dev/null || true
      # Remove VG (also removes LVs)
      vgremove -f "$vg" 2>/dev/null || true
    fi

    # Remove PV
    log "Removing LVM PV: $pv"
    pvremove -f "$pv" 2>/dev/null || true
  done
}

# Stop mdadm arrays on disk. $1=disk
_wipe_mdadm_on_disk() {
  local disk="$1"
  local disk_name
  disk_name=$(basename "$disk")

  command -v mdadm &>/dev/null || return 0

  # Find arrays using this disk
  while IFS= read -r md; do
    [[ -z $md ]] && continue
    if mdadm --detail "$md" 2>/dev/null | grep -q "$disk_name"; then
      log "Stopping mdadm array: $md (contains $disk)"
      mdadm --stop "$md" 2>/dev/null || true
    fi
  done < <(ls /dev/md* 2>/dev/null)

  # Zero superblocks on disk and partitions
  for part in "${disk}"*; do
    # shellcheck disable=SC2015 # || true is fallback, not else branch
    [[ -b $part ]] && mdadm --zero-superblock "$part" 2>/dev/null || true
  done
}

# Wipe partition table and signatures. $1=disk
_wipe_partition_table() {
  local disk="$1"

  log "Wiping partition table: $disk"

  # wipefs removes all filesystem/raid/partition signatures
  if command -v wipefs &>/dev/null; then
    wipefs -a -f "$disk" 2>/dev/null || true
  fi

  # sgdisk --zap-all destroys GPT and MBR structures
  if command -v sgdisk &>/dev/null; then
    sgdisk --zap-all "$disk" 2>/dev/null || true
  fi

  # Zero first and last 1MB (catches MBR, GPT headers, backup GPT)
  dd if=/dev/zero of="$disk" bs=1M count=1 conv=notrunc 2>/dev/null || true
  local disk_size
  disk_size=$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)
  if [[ $disk_size -gt 1048576 ]]; then
    dd if=/dev/zero of="$disk" bs=1M count=1 seek=$((disk_size / 1048576 - 1)) conv=notrunc 2>/dev/null || true
  fi

  # Inform kernel of partition table changes
  partprobe "$disk" 2>/dev/null || true
  blockdev --rereadpt "$disk" 2>/dev/null || true
}

# Wipe single disk completely. $1=disk
_wipe_disk() {
  local disk="$1"

  [[ ! -b $disk ]] && {
    log "WARNING: Disk not found: $disk"
    return 0
  }

  log "Wiping disk: $disk"

  # Order matters: remove higher-level structures first
  _wipe_zfs_on_disk "$disk"
  _wipe_lvm_on_disk "$disk"
  _wipe_mdadm_on_disk "$disk"
  _wipe_partition_table "$disk"
}

# Main wipe function - wipes all selected installation disks
wipe_installation_disks() {
  [[ $WIPE_DISKS != "yes" ]] && {
    log "Disk wipe disabled, skipping"
    return 0
  }

  # Skip wipe if using existing pool (preserve data!)
  [[ $USE_EXISTING_POOL == "yes" ]] && {
    log "Using existing pool, skipping disk wipe"
    return 0
  }

  local disks
  mapfile -t disks < <(_get_install_disks)

  if [[ ${#disks[@]} -eq 0 ]]; then
    log "WARNING: No disks to wipe"
    return 0
  fi

  log "Wiping ${#disks[@]} disk(s): ${disks[*]}"

  for disk in "${disks[@]}"; do
    _wipe_disk "$disk"
  done

  # Sync and wait for kernel to process changes
  sync
  sleep 1

  log "Disk wipe complete"
}
