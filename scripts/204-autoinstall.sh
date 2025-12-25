# shellcheck shell=bash
# =============================================================================
# Autoinstall ISO creation for Proxmox
# =============================================================================

# Validates answer.toml has all required fields and correct format.
# Parameters:
#   $1 - Path to answer.toml file
# Returns: 0 if valid, 1 if validation fails
validate_answer_toml() {
  local file="$1"

  # Basic field validation
  # Note: Use kebab-case keys (root-password, not root_password)
  local required_fields=("fqdn" "mailto" "timezone" "root-password")
  for field in "${required_fields[@]}"; do
    if ! grep -q "^\s*${field}\s*=" "$file" 2>/dev/null; then
      log "ERROR: Missing required field in answer.toml: $field"
      return 1
    fi
  done

  if ! grep -q "\[global\]" "$file" 2>/dev/null; then
    log "ERROR: Missing [global] section in answer.toml"
    return 1
  fi

  # Validate using Proxmox auto-install assistant if available
  if command -v proxmox-auto-install-assistant &>/dev/null; then
    log "Validating answer.toml with proxmox-auto-install-assistant"
    if ! proxmox-auto-install-assistant validate-answer "$file" >>"$LOG_FILE" 2>&1; then
      log "ERROR: answer.toml validation failed"
      # Show validation errors in log
      proxmox-auto-install-assistant validate-answer "$file" >>"$LOG_FILE" 2>&1 || true
      return 1
    fi
    log "answer.toml validation passed"
  else
    log "WARNING: proxmox-auto-install-assistant not found, skipping advanced validation"
  fi

  return 0
}

# Creates answer.toml for Proxmox autoinstall.
# Downloads template and applies configuration variables.
# Side effects: Creates answer.toml file, exits on failure
make_answer_toml() {
  log "Creating answer.toml for autoinstall"
  log "ZFS_RAID=$ZFS_RAID, BOOT_DISK=$BOOT_DISK"
  log "ZFS_POOL_DISKS=(${ZFS_POOL_DISKS[*]})"
  log "USE_EXISTING_POOL=$USE_EXISTING_POOL, EXISTING_POOL_NAME=$EXISTING_POOL_NAME"
  log "EXISTING_POOL_DISKS=(${EXISTING_POOL_DISKS[*]})"

  # Determine which disks to pass to QEMU
  # - For existing pool: pass existing pool disks (needed for zpool import)
  # - For new pool: pass ZFS_POOL_DISKS
  # Note: These disks are passed to QEMU but NOT included in answer.toml disk-list,
  #       so the installer won't format them - only the boot disk gets formatted
  local virtio_pool_disks=()
  if [[ $USE_EXISTING_POOL == "yes" ]]; then
    log "Using existing pool mode - existing pool disks will be passed to QEMU for import"
    # Filter to only include disks that actually exist on the host
    # (pool metadata may contain stale virtio device names from previous installations)
    for disk in "${EXISTING_POOL_DISKS[@]}"; do
      if [[ -b $disk ]]; then
        virtio_pool_disks+=("$disk")
      else
        log "WARNING: Pool disk $disk does not exist on host, skipping"
      fi
    done
  else
    virtio_pool_disks=("${ZFS_POOL_DISKS[@]}")
  fi

  # Create virtio mapping in background (pass values as args since arrays can't be exported)
  run_with_progress "Creating disk mapping" "Disk mapping created" \
    create_virtio_mapping "$BOOT_DISK" "${virtio_pool_disks[@]}"

  # Load mapping into current shell
  load_virtio_mapping || {
    log "ERROR: Failed to load virtio mapping"
    exit 1
  }

  # Determine filesystem and disk list based on BOOT_DISK mode:
  # - BOOT_DISK set: ext4 on boot disk only, ZFS pool created post-install
  # - BOOT_DISK empty: ZFS on all disks (existing behavior)
  local FILESYSTEM
  local all_disks=()

  if [[ -n $BOOT_DISK ]]; then
    # Separate boot disk mode: ext4 on boot disk, ZFS pool created/imported later
    FILESYSTEM="ext4"
    all_disks=("$BOOT_DISK")

    if [[ $USE_EXISTING_POOL == "yes" ]]; then
      # Validate existing pool name is set
      if [[ -z $EXISTING_POOL_NAME ]]; then
        log "ERROR: USE_EXISTING_POOL=yes but EXISTING_POOL_NAME is empty"
        exit 1
      fi
      log "Boot disk mode: ext4 on boot disk, existing pool '$EXISTING_POOL_NAME' will be imported"
    else
      # Validate we have pool disks for post-install ZFS creation
      if [[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]]; then
        log "ERROR: BOOT_DISK set but no pool disks for ZFS tank creation"
        exit 1
      fi
      log "Boot disk mode: ext4 on boot disk, ZFS 'tank' pool will be created from ${#ZFS_POOL_DISKS[@]} pool disk(s)"
    fi
  else
    # All-ZFS mode: all disks in ZFS rpool
    FILESYSTEM="zfs"
    all_disks=("${ZFS_POOL_DISKS[@]}")

    log "All-ZFS mode: ${#all_disks[@]} disk(s) in ZFS rpool (${ZFS_RAID})"
  fi

  # Build DISK_LIST from all_disks using virtio mapping
  DISK_LIST=$(map_disks_to_virtio "toml_array" "${all_disks[@]}")
  if [[ -z $DISK_LIST ]]; then
    log "ERROR: Failed to map disks to virtio devices"
    exit 1
  fi

  log "FILESYSTEM=$FILESYSTEM, DISK_LIST=$DISK_LIST"

  # Generate answer.toml dynamically based on filesystem type
  # This allows conditional sections (ZFS vs LVM parameters)
  log "Generating answer.toml for autoinstall"

  # NOTE: SSH key is NOT added to answer.toml anymore.
  # SSH key is deployed directly to the admin user in 302-configure-admin.sh
  # Root login is disabled for both SSH and Proxmox UI.

  # Escape password for TOML (critical for user-entered passwords)
  local escaped_password="${NEW_ROOT_PASSWORD//\\/\\\\}" # Escape backslashes first
  escaped_password="${escaped_password//\"/\\\"}"        # Then escape quotes

  # Generate [global] section
  # IMPORTANT: Use kebab-case for all keys (root-password, reboot-on-error)
  cat >./answer.toml <<EOF
[global]
    keyboard = "$KEYBOARD"
    country = "$COUNTRY"
    fqdn = "$FQDN"
    mailto = "$EMAIL"
    timezone = "$TIMEZONE"
    root-password = "$escaped_password"
    reboot-on-error = false

[network]
    source = "from-dhcp"

[disk-setup]
    filesystem = "$FILESYSTEM"
    disk-list = $DISK_LIST
EOF

  # Add filesystem-specific parameters
  if [[ $FILESYSTEM == "zfs" ]]; then
    # Map ZFS_RAID to answer.toml format
    local zfs_raid_value
    zfs_raid_value=$(map_raid_to_toml "$ZFS_RAID")
    log "Using ZFS raid: $zfs_raid_value"

    # Add ZFS parameters
    cat >>./answer.toml <<EOF
    zfs.raid = "$zfs_raid_value"
    zfs.compress = "lz4"
    zfs.checksum = "on"
EOF
  elif [[ $FILESYSTEM == "ext4" ]] || [[ $FILESYSTEM == "xfs" ]]; then
    # Add LVM parameters for ext4/xfs
    # swapsize: Use 0 for no swap (rely on zswap for memory compression)
    # maxvz: Omit to let Proxmox allocate remaining space for data volume (/var/lib/vz)
    #        This is where ISO images, CT templates, and backups are stored
    cat >>./answer.toml <<EOF
    lvm.swapsize = 0
EOF
  fi

  # Validate the generated file
  if ! validate_answer_toml "./answer.toml"; then
    log "ERROR: answer.toml validation failed"
    exit 1
  fi

  log "answer.toml created and validated:"
  cat answer.toml >>"$LOG_FILE"

  # Add subtasks for live log display
  if type live_log_subtask &>/dev/null 2>&1; then
    local total_disks=${#ZFS_POOL_DISKS[@]}
    [[ -n $BOOT_DISK ]] && ((total_disks++))
    live_log_subtask "Mapped $total_disks disk(s) to virtio"
    live_log_subtask "Generated answer.toml ($FILESYSTEM)"
  fi
}

# Creates autoinstall ISO from Proxmox ISO and answer.toml.
# Side effects: Creates pve-autoinstall.iso, removes pve.iso
make_autoinstall_iso() {
  log "Creating autoinstall ISO"
  log "Input: pve.iso exists: $(test -f pve.iso && echo 'yes' || echo 'no')"
  log "Input: answer.toml exists: $(test -f answer.toml && echo 'yes' || echo 'no')"
  log "Current directory: $(pwd)"
  log "Files in current directory:"
  ls -la >>"$LOG_FILE" 2>&1

  # Run ISO creation with full logging
  proxmox-auto-install-assistant prepare-iso pve.iso --fetch-from iso --answer-file answer.toml --output pve-autoinstall.iso >>"$LOG_FILE" 2>&1 &
  show_progress $! "Creating autoinstall ISO" "Autoinstall ISO created"
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: proxmox-auto-install-assistant exited with code $exit_code"
  fi

  # Verify ISO was created
  if [[ ! -f "./pve-autoinstall.iso" ]]; then
    log "ERROR: Autoinstall ISO not found after creation attempt"
    log "Files in current directory after attempt:"
    ls -la >>"$LOG_FILE" 2>&1
    exit 1
  fi

  log "Autoinstall ISO created successfully: $(stat -c%s pve-autoinstall.iso 2>/dev/null | awk '{printf "%.1fM", $1/1024/1024}')"

  # Add live log subtasks after completion
  if type live_log_subtask &>/dev/null 2>&1; then
    live_log_subtask "Packed ISO with xorriso"
  fi

  # Remove original ISO to save disk space (only autoinstall ISO is needed)
  log "Removing original ISO to save disk space"
  rm -f pve.iso
}
