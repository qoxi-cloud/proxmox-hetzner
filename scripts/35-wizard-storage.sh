# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Storage Settings Editors
# zfs_mode
# =============================================================================

_edit_zfs_mode() {
  _wiz_start_edit

  # Use pool disk count, not total DRIVE_COUNT
  local pool_count=${#ZFS_POOL_DISKS[@]}

  # Build options based on pool count
  local options=""
  if [[ $pool_count -eq 1 ]]; then
    options="Single disk"
  elif [[ $pool_count -eq 2 ]]; then
    options="RAID-0 (striped)\nRAID-1 (mirror)"
  elif [[ $pool_count -eq 3 ]]; then
    options="RAID-0 (striped)\nRAID-1 (mirror)\nRAID-Z1 (parity)"
  elif [[ $pool_count -ge 4 ]]; then
    options="RAID-0 (striped)\nRAID-1 (mirror)\nRAID-Z1 (parity)\nRAID-Z2 (double parity)\nRAID-10 (striped mirrors)"
  fi

  local item_count
  item_count=$(echo -e "$options" | wc -l)
  _show_input_footer "filter" "$((item_count + 1))"

  local selected
  selected=$(echo -e "$options" | gum choose \
    --header="ZFS mode (${pool_count} disks in pool):" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  if [[ -n $selected ]]; then
    case "$selected" in
      "Single disk") ZFS_RAID="single" ;;
      "RAID-0 (striped)") ZFS_RAID="raid0" ;;
      "RAID-1 (mirror)") ZFS_RAID="raid1" ;;
      "RAID-Z1 (parity)") ZFS_RAID="raidz1" ;;
      "RAID-Z2 (double parity)") ZFS_RAID="raidz2" ;;
      "RAID-10 (striped mirrors)") ZFS_RAID="raid10" ;;
    esac
  fi
}
