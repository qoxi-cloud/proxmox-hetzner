# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Storage Settings Editors
# zfs_mode, zfs_arc
# =============================================================================

_edit_zfs_mode() {
  _wiz_start_edit

  _wiz_description \
    "ZFS RAID level for data pool:" \
    "" \
    "  {{cyan:RAID-0}}:  Max capacity, no redundancy (all disks)" \
    "  {{cyan:RAID-1}}:  Mirror, 50% capacity (2+ disks)" \
    "  {{cyan:RAID-Z1}}: Single parity, N-1 capacity (3+ disks)" \
    "  {{cyan:RAID-Z2}}: Double parity, N-2 capacity (4+ disks)" \
    "  {{cyan:RAID-10}}: Striped mirrors (4+ disks, even count)" \
    ""

  # Use pool disk count, not total DRIVE_COUNT
  local pool_count=${#ZFS_POOL_DISKS[@]}

  # Build options based on pool count
  local options=""
  if [[ $pool_count -eq 1 ]]; then
    options="Single disk"
  elif [[ $pool_count -eq 2 ]]; then
    options="RAID-0 (striped)
RAID-1 (mirror)"
  elif [[ $pool_count -eq 3 ]]; then
    options="RAID-0 (striped)
RAID-1 (mirror)
RAID-Z1 (parity)"
  elif [[ $pool_count -eq 4 ]]; then
    options="RAID-0 (striped)
RAID-1 (mirror)
RAID-Z1 (parity)
RAID-Z2 (double parity)
RAID-10 (striped mirrors)"
  elif [[ $pool_count -ge 5 ]]; then
    options="RAID-0 (striped)
RAID-1 (mirror)
RAID-Z1 (parity)
RAID-Z2 (double parity)
RAID-Z3 (triple parity)
RAID-10 (striped mirrors)"
  fi

  local item_count
  item_count=$(wc -l <<<"$options")
  _show_input_footer "filter" "$((item_count + 1))"

  local selected
  selected=$(
    printf '%s\n' "$options" | _wiz_choose \
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

  _wiz_description \
    "ZFS Adaptive Replacement Cache (ARC) memory allocation:" \
    "" \
    "  {{cyan:VM-focused}}:      Fixed 4GB for ARC (more RAM for VMs)" \
    "  {{cyan:Balanced}}:        25-40% of RAM based on total size" \
    "  {{cyan:Storage-focused}}: 50% of RAM (maximize ZFS caching)" \
    ""

  # 1 header + 3 options
  _show_input_footer "filter" 4

  local selected
  selected=$(
    printf '%s\n' "$WIZ_ZFS_ARC_MODES" | _wiz_choose \
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
