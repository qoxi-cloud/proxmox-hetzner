# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Disk Selection
# boot_disk, pool_disks
# =============================================================================

# Edits boot disk selection for ext4 system partition.
# Options: none (all in rpool) or select specific disk.
# Updates BOOT_DISK global and rebuilds pool disk list.
_edit_boot_disk() {
  _wiz_start_edit

  # Show description about boot disk modes
  _wiz_description \
    " Separate boot disk selection (auto-detected by disk size):" \
    "" \
    "  {{cyan:None}}: All disks in ZFS rpool (system + VMs)" \
    "  {{cyan:Disk}}: Boot disk uses ext4 (system + ISO/templates)" \
    "       Pool disks use ZFS tank (VMs only)" \
    ""

  # Options: "None (all in pool)" + all drives
  local options="None (all in pool)"
  for i in "${!DRIVES[@]}"; do
    local disk_name="${DRIVE_NAMES[$i]}"
    local disk_size="${DRIVE_SIZES[$i]}"
    local disk_model="${DRIVE_MODELS[$i]:0:25}"
    options+=$'\n'"${disk_name} - ${disk_size}  ${disk_model}"
  done

  _show_input_footer "filter" "$((DRIVE_COUNT + 2))"

  local selected
  if ! selected=$(printf '%s' "$options" | _wiz_choose --header="Boot disk:"); then
    return
  fi

  if [[ -n $selected ]]; then
    local old_boot_disk="$BOOT_DISK"
    if [[ $selected == "None (all in pool)" ]]; then
      BOOT_DISK=""
    else
      local disk_name="${selected%% -*}"
      BOOT_DISK="/dev/${disk_name}"
    fi
    _rebuild_pool_disks

    # Validate that pool is not empty after rebuild
    if [[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]]; then
      _wiz_start_edit
      _wiz_hide_cursor
      _wiz_error "✗ Cannot use this boot disk: No disks left for ZFS pool"
      _wiz_blank_line
      _wiz_dim "At least one disk must remain for the ZFS pool."
      _wiz_blank_line
      _wiz_dim "Press any key to continue..."
      read -r -n 1
      # Restore previous boot disk selection
      BOOT_DISK="$old_boot_disk"
      _rebuild_pool_disks
    fi
  fi
}

# Edits ZFS pool disk selection via multi-select checkbox.
# Excludes boot disk if set. Requires at least one disk.
# Updates ZFS_POOL_DISKS array and adjusts ZFS_RAID if needed.
_edit_pool_disks() {
  # Pool disk selection with retry loop (like other editors)
  while true; do
    _wiz_start_edit

    _wiz_description \
      " Select disks for ZFS storage pool:" \
      "" \
      "  These disks will store VMs, containers, and data." \
      "  RAID level is auto-selected based on disk count." \
      ""

    # Build options (exclude boot if set) and preselected items
    local options=""
    local preselected=()
    for i in "${!DRIVES[@]}"; do
      if [[ -z $BOOT_DISK || ${DRIVES[$i]} != "$BOOT_DISK" ]]; then
        local disk_name="${DRIVE_NAMES[$i]}"
        local disk_size="${DRIVE_SIZES[$i]}"
        local disk_model="${DRIVE_MODELS[$i]:0:25}"
        local disk_label="${disk_name} - ${disk_size}  ${disk_model}"
        [[ -n $options ]] && options+=$'\n'
        options+="${disk_label}"

        # Check if this disk is already in pool
        for pool_disk in "${ZFS_POOL_DISKS[@]}"; do
          if [[ $pool_disk == "/dev/${disk_name}" ]]; then
            preselected+=("$disk_label")
            break
          fi
        done
      fi
    done

    local available_count
    if [[ -n $BOOT_DISK ]]; then
      available_count=$((DRIVE_COUNT - 1))
    else
      available_count=$DRIVE_COUNT
    fi
    _show_input_footer "checkbox" "$((available_count + 1))"

    local gum_args=(--header="ZFS pool disks (min 1):")
    for item in "${preselected[@]}"; do
      gum_args+=(--selected "$item")
    done

    local selected
    local gum_exit_code=0
    selected=$(printf '%s\n' "$options" | _wiz_choose_multi "${gum_args[@]}") || gum_exit_code=$?

    # ESC/cancel (any non-zero exit) - keep existing selection
    if [[ $gum_exit_code -ne 0 ]]; then
      return 0
    fi

    # User pressed Enter with nothing selected - show error only if no existing selection
    if [[ -z $selected ]]; then
      if [[ ${#ZFS_POOL_DISKS[@]} -gt 0 ]]; then
        # Has existing selection, treat as cancel
        return 0
      fi
      show_validation_error "✗ At least one disk must be selected for ZFS pool"
      continue
    fi

    # Valid selection - update and exit
    ZFS_POOL_DISKS=()
    while IFS= read -r line; do
      local disk_name="${line%% -*}"
      ZFS_POOL_DISKS+=("/dev/${disk_name}")
    done <<<"$selected"
    _update_zfs_mode_options
    break
  done
}

# Rebuilds ZFS_POOL_DISKS array after boot disk change.
# Includes all drives except the selected boot disk.
# Side effects: Updates ZFS_POOL_DISKS, calls _update_zfs_mode_options
_rebuild_pool_disks() {
  ZFS_POOL_DISKS=()
  for drive in "${DRIVES[@]}"; do
    [[ -z $BOOT_DISK || $drive != "$BOOT_DISK" ]] && ZFS_POOL_DISKS+=("$drive")
  done
  _update_zfs_mode_options
}

# Resets ZFS_RAID if current mode is incompatible with pool disk count.
# Called after pool disk changes to ensure valid RAID selection.
# Side effects: May clear ZFS_RAID global if invalid
_update_zfs_mode_options() {
  local pool_count=${#ZFS_POOL_DISKS[@]}
  # Reset ZFS_RAID if incompatible
  case "$ZFS_RAID" in
    single) [[ $pool_count -ne 1 ]] && ZFS_RAID="" ;;
    raid1 | raid0) [[ $pool_count -lt 2 ]] && ZFS_RAID="" ;;
    raid5 | raidz1) [[ $pool_count -lt 3 ]] && ZFS_RAID="" ;;
    raid10 | raidz2) [[ $pool_count -lt 4 ]] && ZFS_RAID="" ;;
    raidz3) [[ $pool_count -lt 5 ]] && ZFS_RAID="" ;;
  esac
}
