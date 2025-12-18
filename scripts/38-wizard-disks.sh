# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Disk Selection
# boot_disk, pool_disks
# =============================================================================

_edit_boot_disk() {
  _wiz_start_edit

  # Show description about boot disk modes
  _wiz_dim "Separate boot disk selection (auto-detected by disk size):"
  _wiz_blank_line
  _wiz_dim "  ${CLR_CYAN}None${CLR_RESET}: All disks in ZFS rpool (system + VMs)"
  _wiz_dim "  ${CLR_CYAN}Disk${CLR_RESET}: Boot disk uses ext4 (system + ISO/templates)"
  _wiz_dim "       Pool disks use ZFS tank (VMs only)"
  _wiz_blank_line

  # Options: "None (all in pool)" + all drives
  local options="None (all in pool)"
  for i in "${!DRIVES[@]}"; do
    local disk_name="${DRIVE_NAMES[$i]}"
    local disk_size="${DRIVE_SIZES[$i]}"
    local disk_model="${DRIVE_MODELS[$i]:0:25}"
    options+="\n${disk_name} - ${disk_size}  ${disk_model}"
  done

  _show_input_footer "filter" "$((DRIVE_COUNT + 2))"

  local selected
  selected=$(
    echo -e "$options" | _wiz_choose \
      --header="Boot disk:"
  )

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

_edit_pool_disks() {
  _wiz_start_edit

  # Build options (exclude boot if set) and preselected items
  local options=""
  local preselected=()
  for i in "${!DRIVES[@]}"; do
    if [[ -z $BOOT_DISK || ${DRIVES[$i]} != "$BOOT_DISK" ]]; then
      local disk_name="${DRIVE_NAMES[$i]}"
      local disk_size="${DRIVE_SIZES[$i]}"
      local disk_model="${DRIVE_MODELS[$i]:0:25}"
      local disk_label="${disk_name} - ${disk_size}  ${disk_model}"
      options+="${disk_label}\n"

      # Check if this disk is already in pool
      for pool_disk in "${ZFS_POOL_DISKS[@]}"; do
        if [[ $pool_disk == "/dev/${disk_name}" ]]; then
          preselected+=("$disk_label")
          break
        fi
      done
    fi
  done
  options="${options%\\n}"

  local available_count
  if [[ -n $BOOT_DISK ]]; then
    available_count=$((DRIVE_COUNT - 1))
  else
    available_count=$DRIVE_COUNT
  fi
  _show_input_footer "checkbox" "$((available_count + 1))"

  # Build _wiz_choose args with features-style formatting
  local gum_args=(
    --no-limit
    --header="ZFS pool disks (min 1):"
    --header.foreground "$HEX_CYAN"
    --cursor "${CLR_ORANGE}›${CLR_RESET} "
    --cursor.foreground "$HEX_NONE"
    --cursor-prefix "◦ "
    --selected.foreground "$HEX_WHITE"
    --selected-prefix "${CLR_CYAN}✓${CLR_RESET} "
    --unselected-prefix "◦ "
    --no-show-help
  )

  # Add preselected items if any
  for item in "${preselected[@]}"; do
    gum_args+=(--selected "$item")
  done

  local selected
  selected=$(echo -e "$options" | _wiz_choose "${gum_args[@]}")

  if [[ -z $selected ]]; then
    _wiz_start_edit
    _wiz_hide_cursor
    _wiz_error "✗ At least one disk must be selected for ZFS pool"
    _wiz_blank_line
    _wiz_dim "Press any key to select disks..."
    read -r -n 1
    return 1
  fi

  ZFS_POOL_DISKS=()
  while IFS= read -r line; do
    local disk_name="${line%% -*}"
    ZFS_POOL_DISKS+=("/dev/${disk_name}")
  done <<<"$selected"
  _update_zfs_mode_options
}

# Helper: rebuild pool disks after boot disk change
_rebuild_pool_disks() {
  ZFS_POOL_DISKS=()
  for drive in "${DRIVES[@]}"; do
    [[ -z $BOOT_DISK || $drive != "$BOOT_DISK" ]] && ZFS_POOL_DISKS+=("$drive")
  done
  _update_zfs_mode_options
}

# Helper: adjust ZFS_RAID if current mode incompatible with pool disk count
_update_zfs_mode_options() {
  local pool_count=${#ZFS_POOL_DISKS[@]}
  # Reset ZFS_RAID if incompatible
  case "$ZFS_RAID" in
    single) [[ $pool_count -ne 1 ]] && ZFS_RAID="" ;;
    raid1 | raid0) [[ $pool_count -lt 2 ]] && ZFS_RAID="" ;;
    raid5 | raidz1) [[ $pool_count -lt 3 ]] && ZFS_RAID="" ;;
    raid10 | raidz2) [[ $pool_count -lt 4 ]] && ZFS_RAID="" ;;
  esac
}
