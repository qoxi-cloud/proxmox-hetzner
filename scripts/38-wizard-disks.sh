# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Disk Selection
# boot_disk, pool_disks
# =============================================================================

_edit_boot_disk() {
  _wiz_start_edit

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
  selected=$(echo -e "$options" | gum choose \
    --header="Boot disk:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  if [[ -n $selected ]]; then
    if [[ $selected == "None (all in pool)" ]]; then
      BOOT_DISK=""
    else
      local disk_name="${selected%% -*}"
      BOOT_DISK="/dev/${disk_name}"
    fi
    _rebuild_pool_disks
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

  # Build gum choose args with features-style formatting
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
  selected=$(echo -e "$options" | gum choose "${gum_args[@]}")

  if [[ -n $selected ]]; then
    ZFS_POOL_DISKS=()
    while IFS= read -r line; do
      local disk_name="${line%% -*}"
      ZFS_POOL_DISKS+=("/dev/${disk_name}")
    done <<<"$selected"
    _update_zfs_mode_options
  fi
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
