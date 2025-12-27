# shellcheck shell=bash
# Configuration Wizard - Storage Settings Editors
# wipe_disks, zfs_mode, zfs_arc, existing_pool

# Edits disk wipe setting (full wipe vs keep existing).
# Updates WIPE_DISKS global. Auto-disabled when using existing pool.
_edit_wipe_disks() {
  _wiz_start_edit

  # Auto-disable if using existing pool
  if [[ $USE_EXISTING_POOL == "yes" ]]; then
    _wiz_hide_cursor
    _wiz_description \
      "  {{yellow:⚠ Disk wipe is disabled when using existing pool}}" \
      "" \
      "  Existing pool data must be preserved."
    sleep "${WIZARD_MESSAGE_DELAY:-3}"
    WIPE_DISKS="no"
    return
  fi

  _wiz_description \
    "  Clean disks before installation:" \
    "" \
    "  {{cyan:Yes}}: Wipe all selected disks (removes old partitions," \
    "       LVM, ZFS pools, mdadm arrays). Like fresh drives." \
    "  {{cyan:No}}:  Only release locks, keep existing structures." \
    "" \
    "  {{yellow:WARNING}}: Full wipe DESTROYS all data on selected disks!" \
    ""

  _show_input_footer "filter" 3

  _wiz_choose_mapped "WIPE_DISKS" "Wipe disks before install:" \
    "${WIZ_MAP_WIPE_DISKS[@]}"
}

# Edits existing pool setting (use existing vs create new).
# Updates USE_EXISTING_POOL and EXISTING_POOL_NAME globals.
# Uses DETECTED_POOLS array populated during system detection.
_edit_existing_pool() {
  _wiz_start_edit

  # Use pre-detected pools from DETECTED_POOLS (populated by _detect_pools)
  if [[ ${#DETECTED_POOLS[@]} -eq 0 ]]; then
    _wiz_hide_cursor
    _wiz_description \
      "  {{yellow:⚠ No importable ZFS pools detected}}" \
      "" \
      "  Possible causes:" \
      "    • ZFS not installed (check log for errors)" \
      "    • Pool not exported before reboot" \
      "    • Pool already imported (zpool list)" \
      "    • Pool metadata corrupted" \
      "" \
      "  Try manually: {{cyan:zpool import -d /dev}}"
    sleep "${WIZARD_MESSAGE_DELAY:-4}"
    return
  fi

  _wiz_description \
    "  Preserve existing ZFS pool during reinstall:" \
    "" \
    "  {{cyan:Create new}}: Format pool disks, create fresh ZFS pool" \
    "  {{cyan:Use existing}}: Import pool, preserve all VMs and data" \
    "" \
    "  {{yellow:WARNING}}: Using existing pool skips disk formatting." \
    "  Ensure the pool is healthy before proceeding." \
    ""

  # Build options: "Create new pool" + detected pools
  local options="Create new pool (format disks)"
  for pool_info in "${DETECTED_POOLS[@]}"; do
    local pool_name="${pool_info%%|*}"
    local rest="${pool_info#*|}"
    local pool_state="${rest%%|*}"
    options+=$'\n'"Use existing: ${pool_name} (${pool_state})"
  done

  local item_count
  item_count=$(wc -l <<<"$options")
  _show_input_footer "filter" "$((item_count + 1))"

  local selected
  if ! selected=$(printf '%s\n' "$options" | _wiz_choose --header="Pool mode:"); then
    return
  fi

  if [[ $selected == "Create new pool (format disks)" ]]; then
    USE_EXISTING_POOL=""
    EXISTING_POOL_NAME=""
    EXISTING_POOL_DISKS=()
  elif [[ $selected =~ ^Use\ existing:\ ([^[:space:]]+) ]]; then
    # Check if boot disk is set - required for existing pool mode
    if [[ -z $BOOT_DISK ]]; then
      _wiz_start_edit
      _wiz_hide_cursor
      _wiz_description \
        "  {{red:✗ Cannot use existing pool without separate boot disk}}" \
        "" \
        "  Select a boot disk first, then enable existing pool." \
        "  The boot disk will be formatted for Proxmox system files."
      sleep "${WIZARD_MESSAGE_DELAY:-3}"
      return
    fi

    local pool_name="${BASH_REMATCH[1]}"

    # Get disks for this pool
    local disks_csv
    disks_csv=$(get_pool_disks "$pool_name")
    local pool_disks=()
    IFS=',' read -ra pool_disks <<<"$disks_csv"

    # Check if boot disk is part of this pool (would destroy the pool!)
    local boot_in_pool=false
    for disk in "${pool_disks[@]}"; do
      if [[ $disk == "$BOOT_DISK" ]]; then
        boot_in_pool=true
        break
      fi
    done

    if [[ $boot_in_pool == true ]]; then
      _wiz_start_edit
      _wiz_hide_cursor
      _wiz_description \
        "  {{red:✗ Boot disk conflict!}}" \
        "" \
        "  Boot disk $BOOT_DISK is part of pool '$pool_name'." \
        "  Installing Proxmox on this disk will DESTROY the pool!" \
        "" \
        "  Options:" \
        "    1. Select a different boot disk (not in this pool)" \
        "    2. Create a new pool instead of using existing"
      sleep "${WIZARD_MESSAGE_DELAY:-5}"
      return
    fi

    USE_EXISTING_POOL="yes"
    EXISTING_POOL_NAME="$pool_name"
    EXISTING_POOL_DISKS=("${pool_disks[@]}")

    # Clear pool disks since we won't be creating new pool
    ZFS_POOL_DISKS=()
    ZFS_RAID=""

    log "Selected existing pool: $EXISTING_POOL_NAME with disks: ${EXISTING_POOL_DISKS[*]}"
  fi
}

# Edits ZFS RAID level for data pool.
# Options vary based on pool disk count (single, raid0/1, raidz1/2/3, raid10).
# Updates ZFS_RAID global.
_edit_zfs_mode() {
  _wiz_start_edit

  _wiz_description \
    "  ZFS RAID level for data pool:" \
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
  if ! selected=$(printf '%s\n' "$options" | _wiz_choose --header="ZFS mode (${pool_count} disks in pool):"); then
    return
  fi

  case "$selected" in
    "Single disk") ZFS_RAID="single" ;;
    "RAID-0 (striped)") ZFS_RAID="raid0" ;;
    "RAID-1 (mirror)") ZFS_RAID="raid1" ;;
    "RAID-Z1 (parity)") ZFS_RAID="raidz1" ;;
    "RAID-Z2 (double parity)") ZFS_RAID="raidz2" ;;
    "RAID-Z3 (triple parity)") ZFS_RAID="raidz3" ;;
    "RAID-10 (striped mirrors)") ZFS_RAID="raid10" ;;
  esac
}

# Edits ZFS ARC memory allocation strategy.
# Options: vm-focused (4GB), balanced (25-40%), storage-focused (50%).
# Updates ZFS_ARC_MODE global.
_edit_zfs_arc() {
  _wiz_start_edit

  _wiz_description \
    "  ZFS Adaptive Replacement Cache (ARC) memory allocation:" \
    "" \
    "  {{cyan:VM-focused}}:      Fixed 4GB for ARC (more RAM for VMs)" \
    "  {{cyan:Balanced}}:        25-40% of RAM based on total size" \
    "  {{cyan:Storage-focused}}: 50% of RAM (maximize ZFS caching)" \
    ""

  # 1 header + 3 options
  _show_input_footer "filter" 4

  _wiz_choose_mapped "ZFS_ARC_MODE" "ZFS ARC memory strategy:" \
    "${WIZ_MAP_ZFS_ARC[@]}"
}
