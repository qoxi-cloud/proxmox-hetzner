# shellcheck shell=bash
# =============================================================================
# Configure ZFS ARC memory allocation
# =============================================================================

configure_zfs_arc() {
  log "INFO: Configuring ZFS ARC memory allocation (mode: $ZFS_ARC_MODE)"

  # Calculate ARC size locally (we know RAM from rescue system)
  local total_ram_mb
  total_ram_mb=$(free -m | awk 'NR==2 {print $2}')

  local arc_max_mb
  case "$ZFS_ARC_MODE" in
    vm-focused)
      # Fixed 4GB for servers where VMs are primary workload
      arc_max_mb=4096
      ;;
    balanced)
      # Conservative ARC sizing based on RAM:
      # < 16GB: 25% of RAM
      # 16-64GB: 40% of RAM
      # > 64GB: 50% of RAM
      if [[ $total_ram_mb -lt 16384 ]]; then
        arc_max_mb=$((total_ram_mb * 25 / 100))
      elif [[ $total_ram_mb -lt 65536 ]]; then
        arc_max_mb=$((total_ram_mb * 40 / 100))
      else
        arc_max_mb=$((total_ram_mb / 2))
      fi
      ;;
    storage-focused)
      # Use 50% of RAM (ZFS default behavior)
      arc_max_mb=$((total_ram_mb / 2))
      ;;
    *)
      log "ERROR: Invalid ZFS_ARC_MODE: $ZFS_ARC_MODE"
      return 1
      ;;
  esac

  local arc_max_bytes=$((arc_max_mb * 1024 * 1024))

  log "INFO: ZFS ARC: ${arc_max_mb}MB (Total RAM: ${total_ram_mb}MB, Mode: $ZFS_ARC_MODE)"

  # Apply configuration via SSH
  run_remote "Configuring ZFS ARC memory" "
    # Set ZFS ARC limit in modprobe config (persistent across reboots)
    echo 'options zfs zfs_arc_max=$arc_max_bytes' >/etc/modprobe.d/zfs.conf

    # Apply limit to currently running kernel module (if ZFS loaded)
    if [[ -f /sys/module/zfs/parameters/zfs_arc_max ]]; then
      echo '$arc_max_bytes' >/sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || true
    fi
  "

  log "INFO: ZFS ARC memory limit configured: ${arc_max_mb}MB"
}

# =============================================================================
# Configure ZFS scrub scheduling
# =============================================================================

configure_zfs_scrub() {
  log "INFO: Configuring ZFS scrub schedule"

  # Deploy systemd service and timer templates
  deploy_template "zfs-scrub.service" "/etc/systemd/system/zfs-scrub@.service"
  deploy_template "zfs-scrub.timer" "/etc/systemd/system/zfs-scrub@.timer"

  run_remote "Enabling ZFS scrub timers" "
    systemctl daemon-reload

    # Enable scrub timer for rpool (boot/system pool)
    if zpool list rpool &>/dev/null; then
      systemctl enable --now zfs-scrub@rpool.timer
      echo 'Enabled scrub timer for rpool'
    fi

    # Enable scrub timer for tank (data pool) if exists
    if zpool list tank &>/dev/null; then
      systemctl enable --now zfs-scrub@tank.timer
      echo 'Enabled scrub timer for tank'
    fi
  "

  log "INFO: ZFS scrub schedule configured (monthly, 1st Sunday at 2:00 AM)"
}
