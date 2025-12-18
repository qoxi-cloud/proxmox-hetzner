# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Storage Settings Editors
# zfs_mode, zfs_arc
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
  elif [[ $pool_count -eq 4 ]]; then
    options="RAID-0 (striped)\nRAID-1 (mirror)\nRAID-Z1 (parity)\nRAID-Z2 (double parity)\nRAID-10 (striped mirrors)"
  elif [[ $pool_count -ge 5 ]]; then
    options="RAID-0 (striped)\nRAID-1 (mirror)\nRAID-Z1 (parity)\nRAID-Z2 (double parity)\nRAID-Z3 (triple parity)\nRAID-10 (striped mirrors)"
  fi

  local item_count
  item_count=$(echo -e "$options" | wc -l)
  _show_input_footer "filter" "$((item_count + 1))"

  local selected
  selected=$(
    echo -e "$options" | _wiz_choose \
      --header="ZFS mode (${pool_count} disks in pool):"
  )

  if [[ -n $selected ]]; then
    case "$selected" in
      "Single disk") ZFS_RAID="single" ;;
      "RAID-0 (striped)") ZFS_RAID="raid0" ;;
      "RAID-1 (mirror)") ZFS_RAID="raid1" ;;
      "RAID-Z1 (parity)") ZFS_RAID="raidz1" ;;
      "RAID-Z2 (double parity)") ZFS_RAID="raidz2" ;;
      "RAID-Z3 (triple parity)") ZFS_RAID="raidz3" ;;
      "RAID-10 (striped mirrors)") ZFS_RAID="raid10" ;;
    esac
  fi
}

_edit_zfs_arc() {
  _wiz_start_edit

  # 1 header + 3 options
  _show_input_footer "filter" 4

  local selected
  selected=$(
    echo "$WIZ_ZFS_ARC_MODES" | _wiz_choose \
      --header="ZFS ARC memory strategy:"
  )

  if [[ -n $selected ]]; then
    case "$selected" in
      "VM-focused (4GB fixed)") ZFS_ARC_MODE="vm-focused" ;;
      "Balanced (25-40% of RAM)") ZFS_ARC_MODE="balanced" ;;
      "Storage-focused (50% of RAM)") ZFS_ARC_MODE="storage-focused" ;;
    esac
  fi
}
