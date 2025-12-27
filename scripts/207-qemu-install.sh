# shellcheck shell=bash
# QEMU installation and boot functions

# Install Proxmox via QEMU with autoinstall ISO
install_proxmox() {
  # Run preparation in background to show progress immediately
  local qemu_config_file
  qemu_config_file=$(mktemp)
  register_temp_file "$qemu_config_file"

  (
    # Setup QEMU configuration - exit on failure
    if ! setup_qemu_config; then
      log "ERROR: QEMU configuration failed"
      exit 1
    fi

    # Save config for parent shell (including all QEMU variables)
    cat >"$qemu_config_file" <<EOF
QEMU_CORES=$QEMU_CORES
QEMU_RAM=$QEMU_RAM
UEFI_MODE=$(is_uefi_mode && echo "yes" || echo "no")
KVM_OPTS='$KVM_OPTS'
UEFI_OPTS='$UEFI_OPTS'
CPU_OPTS='$CPU_OPTS'
DRIVE_ARGS='$DRIVE_ARGS'
EOF

    # Verify ISO exists
    if [[ ! -f "./pve-autoinstall.iso" ]]; then
      print_error "Autoinstall ISO not found!"
      exit 1
    fi

    # Release any locks on drives before QEMU starts
    release_drives
  ) &
  local prep_pid=$!

  # Wait for config file to be ready
  local timeout=10
  while [[ ! -s $qemu_config_file ]] && ((timeout > 0)); do
    sleep 0.1
    ((timeout--))
  done

  # Load QEMU configuration
  if [[ -s $qemu_config_file ]]; then
    # shellcheck disable=SC1090
    source "$qemu_config_file"
    rm -f "$qemu_config_file"
  fi

  show_progress $prep_pid "Starting QEMU (${QEMU_CORES} vCPUs, ${QEMU_RAM}MB RAM)" "QEMU started (${QEMU_CORES} vCPUs, ${QEMU_RAM}MB RAM)"

  # Add subtasks after preparation completes
  if [[ $UEFI_MODE == "yes" ]]; then
    live_log_subtask "UEFI mode detected"
  else
    live_log_subtask "Legacy BIOS mode"
  fi
  live_log_subtask "KVM acceleration enabled"
  live_log_subtask "Configured ${QEMU_CORES} vCPUs, ${QEMU_RAM}MB RAM"

  # Now start QEMU in parent process (not in subshell) - this is KEY!
  # shellcheck disable=SC2086
  qemu-system-x86_64 $KVM_OPTS $UEFI_OPTS \
    $CPU_OPTS -smp "$QEMU_CORES" -m "$QEMU_RAM" \
    -boot d -cdrom ./pve-autoinstall.iso \
    $DRIVE_ARGS -no-reboot -display none >qemu_install.log 2>&1 &

  local qemu_pid=$!

  # Give QEMU a moment to start or fail
  sleep "${RETRY_DELAY_SECONDS:-2}"

  # Check if QEMU is still running
  if ! kill -0 $qemu_pid 2>/dev/null; then
    log "ERROR: QEMU failed to start"
    log "QEMU install log:"
    cat qemu_install.log >>"$LOG_FILE" 2>&1
    exit 1
  fi

  show_progress "$qemu_pid" "Installing Proxmox VE" "Proxmox VE installed"
  local exit_code=$?

  # Verify installation completed (QEMU exited cleanly)
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: QEMU installation failed with exit code $exit_code"
    log "QEMU install log:"
    cat qemu_install.log >>"$LOG_FILE" 2>&1
    exit 1
  fi
}

# Boot Proxmox with SSH port forwarding. Sets QEMU_PID.
boot_proxmox_with_port_forwarding() {
  # Deactivate any LVM auto-activated by udev after install
  _deactivate_lvm

  if ! setup_qemu_config; then
    log "ERROR: QEMU configuration failed in boot_proxmox_with_port_forwarding"
    return 1
  fi

  # Check if port is already in use
  if ! check_port_available "$SSH_PORT"; then
    print_error "Port $SSH_PORT is already in use"
    log "ERROR: Port $SSH_PORT is already in use"
    exit 1
  fi

  # shellcheck disable=SC2086
  nohup qemu-system-x86_64 $KVM_OPTS $UEFI_OPTS \
    $CPU_OPTS -device e1000,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT_QEMU}-:22 \
    -smp "$QEMU_CORES" -m "$QEMU_RAM" \
    $DRIVE_ARGS -display none \
    >qemu_output.log 2>&1 &

  QEMU_PID=$!

  # Wait for port to be open first (in background for show_progress)
  local timeout="${QEMU_BOOT_TIMEOUT:-300}"
  local check_interval="${QEMU_PORT_CHECK_INTERVAL:-3}"
  (
    local elapsed=0
    while ((elapsed < timeout)); do
      # Suppress all connection errors by redirecting to /dev/null
      if exec 3<>/dev/tcp/localhost/"${SSH_PORT_QEMU}" 2>/dev/null; then
        exec 3<&- # Close the file descriptor
        exit 0
      fi 2>/dev/null
      sleep "$check_interval"
      ((elapsed += check_interval))
    done
    exit 1
  ) 2>/dev/null &
  local wait_pid=$!

  show_progress $wait_pid "Booting installed Proxmox" "Proxmox booted"
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Timeout waiting for SSH port"
    log "QEMU output log:"
    cat qemu_output.log >>"$LOG_FILE" 2>&1
    return 1
  fi

  # Wait for SSH to be fully ready (handles key exchange timing)
  wait_for_ssh_ready "${QEMU_SSH_READY_TIMEOUT:-120}" || {
    log "ERROR: SSH connection failed"
    log "QEMU output log:"
    cat qemu_output.log >>"$LOG_FILE" 2>&1
    return 1
  }
}
