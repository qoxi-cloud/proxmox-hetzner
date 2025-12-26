# shellcheck shell=bash
# Drive release functions for QEMU

# Send signal to process if running. $1=pid, $2=signal, $3=log_msg
_signal_process() {
  local pid="$1"
  local signal="$2"
  local message="$3"

  if kill -0 "$pid" 2>/dev/null; then
    log "$message"
    kill "-$signal" "$pid" 2>/dev/null || true
  fi
}

# Kill processes by pattern. $1=pattern
_kill_processes_by_pattern() {
  local pattern="$1"
  local pids

  pids=$(pgrep -f "$pattern" 2>/dev/null || true)
  if [[ -n $pids ]]; then
    log "Found processes matching '$pattern': $pids"

    # Graceful shutdown first (SIGTERM)
    for pid in $pids; do
      _signal_process "$pid" "TERM" "Sending TERM to process $pid"
    done
    sleep "${WIZARD_MESSAGE_DELAY:-3}"

    # Force kill if still running (SIGKILL)
    for pid in $pids; do
      _signal_process "$pid" "9" "Force killing process $pid"
    done
    sleep "${PROCESS_KILL_WAIT:-1}"
  fi

  # Also try pkill as fallback
  pkill -TERM "$pattern" 2>/dev/null || true
  sleep "${PROCESS_KILL_WAIT:-1}"
  pkill -9 "$pattern" 2>/dev/null || true
}

# Stops all mdadm RAID arrays to release drive locks.
# Iterates over /dev/md* devices if mdadm is available.
_stop_mdadm_arrays() {
  if ! command -v mdadm &>/dev/null; then
    return 0
  fi

  log "Stopping mdadm arrays..."
  mdadm --stop --scan 2>/dev/null || true

  # Stop specific arrays if found
  for md in /dev/md*; do
    if [[ -b $md ]]; then
      mdadm --stop "$md" 2>/dev/null || true
    fi
  done
}

# Deactivates all LVM volume groups to release drive locks.
# Uses vgchange -an to deactivate all VGs.
_deactivate_lvm() {
  if ! command -v vgchange &>/dev/null; then
    return 0
  fi

  log "Deactivating LVM volume groups..."
  vgchange -an &>/dev/null || true

  # Deactivate specific VGs by name if vgs is available
  if command -v vgs &>/dev/null; then
    while IFS= read -r vg; do
      if [[ -n $vg ]]; then vgchange -an "$vg" &>/dev/null || true; fi
    done < <(vgs --noheadings -o vg_name 2>/dev/null)
  fi
}

# Unmounts all filesystems on target drives (DRIVES global).
# Uses findmnt for efficient mount point detection.
_unmount_drive_filesystems() {
  [[ -z ${DRIVES[*]} ]] && return 0

  log "Unmounting filesystems on target drives..."
  for drive in "${DRIVES[@]}"; do
    # Use findmnt for efficient mount point detection (faster and more reliable)
    if command -v findmnt &>/dev/null; then
      while IFS= read -r mountpoint; do
        [[ -z $mountpoint ]] && continue
        log "Unmounting $mountpoint"
        umount -f "$mountpoint" 2>/dev/null || true
      done < <(findmnt -rn -o TARGET "$drive"* 2>/dev/null)
    else
      # Fallback to mount | grep
      local drive_name
      drive_name=$(basename "$drive")
      while IFS= read -r mountpoint; do
        [[ -z $mountpoint ]] && continue
        log "Unmounting $mountpoint"
        umount -f "$mountpoint" 2>/dev/null || true
      done < <(mount | grep -E "(^|/)$drive_name" | awk '{print $3}')
    fi
  done
}

# Kills processes holding drives open using lsof/fuser.
# Iterates over DRIVES global array.
_kill_drive_holders() {
  [[ -z ${DRIVES[*]} ]] && return 0

  log "Checking for processes using drives..."
  for drive in "${DRIVES[@]}"; do
    # Use lsof if available
    if command -v lsof &>/dev/null; then
      while IFS= read -r pid; do
        [[ -z $pid ]] && continue
        _signal_process "$pid" "9" "Killing process $pid using $drive"
      done < <(lsof "$drive" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
    fi

    # Use fuser as alternative
    if command -v fuser &>/dev/null; then
      fuser -k "$drive" 2>/dev/null || true
    fi
  done
}

# Main drive release function

# Release drives from locks (RAID, LVM, mounts, holders) before QEMU
release_drives() {
  log "Releasing drives from locks..."

  # Kill QEMU processes
  _kill_processes_by_pattern "qemu-system-x86"

  # Stop RAID arrays
  _stop_mdadm_arrays

  # Deactivate LVM
  _deactivate_lvm

  # Unmount filesystems
  _unmount_drive_filesystems

  # Additional pause for locks to release
  sleep "${RETRY_DELAY_SECONDS:-2}"

  # Kill any remaining processes holding drives
  _kill_drive_holders

  log "Drives released"
}
