# shellcheck shell=bash
# =============================================================================
# QEMU installation and boot functions
# =============================================================================

is_uefi_mode() {
    [[ -d /sys/firmware/efi ]]
}

# Configure QEMU settings (shared between install and boot)
setup_qemu_config() {
    log "Setting up QEMU configuration"

    # UEFI configuration
    if is_uefi_mode; then
        UEFI_OPTS="-bios /usr/share/ovmf/OVMF.fd"
        log "UEFI mode detected"
    else
        UEFI_OPTS=""
        log "Legacy BIOS mode"
    fi

    # KVM or TCG mode
    if [[ "$TEST_MODE" == true ]]; then
        # TCG (software emulation) for testing without KVM
        KVM_OPTS="-accel tcg"
        CPU_OPTS="-cpu qemu64"
        log "Using TCG emulation (test mode)"
    else
        KVM_OPTS="-enable-kvm"
        CPU_OPTS="-cpu host"
        log "Using KVM acceleration"
    fi

    # CPU and RAM configuration
    local available_cores available_ram_mb
    available_cores=$(nproc)
    available_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    log "Available cores: $available_cores, Available RAM: ${available_ram_mb}MB"

    # Use override values if provided, otherwise auto-detect
    if [[ -n "$QEMU_CORES_OVERRIDE" ]]; then
        QEMU_CORES="$QEMU_CORES_OVERRIDE"
        log "Using user-specified cores: $QEMU_CORES"
    else
        QEMU_CORES=$((available_cores / 2))
        [[ $QEMU_CORES -lt $MIN_CPU_CORES ]] && QEMU_CORES=$MIN_CPU_CORES
        [[ $QEMU_CORES -gt $available_cores ]] && QEMU_CORES=$available_cores
        [[ $QEMU_CORES -gt $MAX_QEMU_CORES ]] && QEMU_CORES=$MAX_QEMU_CORES
    fi

    if [[ -n "$QEMU_RAM_OVERRIDE" ]]; then
        QEMU_RAM="$QEMU_RAM_OVERRIDE"
        log "Using user-specified RAM: ${QEMU_RAM}MB"
        # Warn if requested RAM exceeds available
        if [[ $QEMU_RAM -gt $((available_ram_mb - QEMU_MIN_RAM_RESERVE)) ]]; then
            print_warning "Requested QEMU RAM (${QEMU_RAM}MB) may exceed safe limits (available: ${available_ram_mb}MB)"
        fi
    else
        QEMU_RAM=$DEFAULT_QEMU_RAM
        [[ $available_ram_mb -lt $QEMU_LOW_RAM_THRESHOLD ]] && QEMU_RAM=$MIN_QEMU_RAM
    fi

    log "QEMU config: $QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM"

    # Drive configuration - add all detected drives
    DRIVE_ARGS=""
    for drive in "${DRIVES[@]}"; do
        DRIVE_ARGS="$DRIVE_ARGS -drive file=$drive,format=raw,media=disk,if=virtio"
    done
    log "Drive args: $DRIVE_ARGS"
}

# =============================================================================
# Drive release helper functions
# =============================================================================

# Send signal to process if it's running
# Usage: _signal_process PID SIGNAL LOG_MESSAGE
_signal_process() {
    local pid="$1"
    local signal="$2"
    local message="$3"

    if kill -0 "$pid" 2>/dev/null; then
        log "$message"
        kill "-$signal" "$pid" 2>/dev/null || true
    fi
}

# Kill processes by pattern with graceful then forced termination
# Usage: _kill_processes_by_pattern PATTERN
_kill_processes_by_pattern() {
    local pattern="$1"
    local pids

    pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        log "Found processes matching '$pattern': $pids"

        # Graceful shutdown first (SIGTERM)
        for pid in $pids; do
            _signal_process "$pid" "TERM" "Sending TERM to process $pid"
        done
        sleep 3

        # Force kill if still running (SIGKILL)
        for pid in $pids; do
            _signal_process "$pid" "9" "Force killing process $pid"
        done
        sleep 1
    fi

    # Also try pkill as fallback
    pkill -TERM "$pattern" 2>/dev/null || true
    sleep 1
    pkill -9 "$pattern" 2>/dev/null || true
}

# Stop mdadm RAID arrays
_stop_mdadm_arrays() {
    if ! command -v mdadm &>/dev/null; then
        return 0
    fi

    log "Stopping mdadm arrays..."
    mdadm --stop --scan 2>/dev/null || true

    # Stop specific arrays if found
    for md in /dev/md*; do
        if [[ -b "$md" ]]; then
            mdadm --stop "$md" 2>/dev/null || true
        fi
    done
}

# Deactivate LVM volume groups
_deactivate_lvm() {
    if ! command -v vgchange &>/dev/null; then
        return 0
    fi

    log "Deactivating LVM volume groups..."
    vgchange -an 2>/dev/null || true

    # Deactivate specific VGs by name if vgs is available
    if command -v vgs &>/dev/null; then
        while IFS= read -r vg; do
            if [[ -n "$vg" ]]; then vgchange -an "$vg" 2>/dev/null || true; fi
        done < <(vgs --noheadings -o vg_name 2>/dev/null)
    fi
}

# Unmount filesystems on specified drives
_unmount_drive_filesystems() {
    [[ -z "${DRIVES[*]}" ]] && return 0

    log "Unmounting filesystems on target drives..."
    for drive in "${DRIVES[@]}"; do
        # Use findmnt for efficient mount point detection (faster and more reliable)
        if command -v findmnt &>/dev/null; then
            while IFS= read -r mountpoint; do
                [[ -z "$mountpoint" ]] && continue
                log "Unmounting $mountpoint"
                umount -f "$mountpoint" 2>/dev/null || true
            done < <(findmnt -rn -o TARGET "$drive"* 2>/dev/null)
        else
            # Fallback to mount | grep
            local drive_name
            drive_name=$(basename "$drive")
            while IFS= read -r mountpoint; do
                [[ -z "$mountpoint" ]] && continue
                log "Unmounting $mountpoint"
                umount -f "$mountpoint" 2>/dev/null || true
            done < <(mount | grep -E "(^|/)$drive_name" | awk '{print $3}')
        fi
    done
}

# Kill processes holding drives open
_kill_drive_holders() {
    [[ -z "${DRIVES[*]}" ]] && return 0

    log "Checking for processes using drives..."
    for drive in "${DRIVES[@]}"; do
        # Use lsof if available
        if command -v lsof &>/dev/null; then
            while IFS= read -r pid; do
                [[ -z "$pid" ]] && continue
                _signal_process "$pid" "9" "Killing process $pid using $drive"
            done < <(lsof "$drive" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
        fi

        # Use fuser as alternative
        if command -v fuser &>/dev/null; then
            fuser -k "$drive" 2>/dev/null || true
        fi
    done
}

# =============================================================================
# Main drive release function
# =============================================================================

# Release drives from any existing locks
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
    sleep 2

    # Kill any remaining processes holding drives
    _kill_drive_holders

    log "Drives released"
}

# Install Proxmox via QEMU
install_proxmox() {
    setup_qemu_config

    # Verify ISO exists
    if [[ ! -f "./pve-autoinstall.iso" ]]; then
        print_error "Autoinstall ISO not found!"
        exit 1
    fi

    # Show message immediately so user knows installation is starting
    local install_msg="Installing Proxmox VE (${QEMU_CORES} vCPUs, ${QEMU_RAM}MB RAM)"
    printf "${CLR_YELLOW}%s %s${CLR_RESET}" "${SPINNER_CHARS[0]}" "$install_msg"

    # Release any locks on drives before QEMU starts
    release_drives

    # Run QEMU in background with error logging
    # shellcheck disable=SC2086
    qemu-system-x86_64 $KVM_OPTS $UEFI_OPTS \
        $CPU_OPTS -smp "$QEMU_CORES" -m "$QEMU_RAM" \
        -boot d -cdrom ./pve-autoinstall.iso \
        $DRIVE_ARGS -no-reboot -display none > qemu_install.log 2>&1 &

    local qemu_pid=$!

    # Give QEMU a moment to start or fail
    sleep 2

    # Check if QEMU is still running
    if ! kill -0 $qemu_pid 2>/dev/null; then
        printf "\r\e[K"
        log "ERROR: QEMU failed to start"
        log "QEMU install log:"
        cat qemu_install.log >> "$LOG_FILE" 2>&1
        exit 1
    fi

    show_progress $qemu_pid "$install_msg" "Proxmox VE installed"
    local exit_code=$?

    # Verify installation completed (QEMU exited cleanly)
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: QEMU installation failed with exit code $exit_code"
        log "QEMU install log:"
        cat qemu_install.log >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

# Boot installed Proxmox with SSH port forwarding
boot_proxmox_with_port_forwarding() {
    setup_qemu_config
    
    # Check if port is already in use
    if ! check_port_available "$SSH_PORT"; then
        print_error "Port $SSH_PORT is already in use"
        log "ERROR: Port $SSH_PORT is already in use"
        exit 1
    fi

    # shellcheck disable=SC2086
    nohup qemu-system-x86_64 $KVM_OPTS $UEFI_OPTS \
        $CPU_OPTS -device e1000,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::5555-:22 \
        -smp "$QEMU_CORES" -m "$QEMU_RAM" \
        $DRIVE_ARGS -display none \
        > qemu_output.log 2>&1 &

    QEMU_PID=$!

    # Wait for port to be open first (quick check)
    wait_with_progress "Booting installed Proxmox" 300 "(echo >/dev/tcp/localhost/5555)" 3 "Proxmox booted, port open"

    # Wait for SSH to be fully ready (handles key exchange timing)
    wait_for_ssh_ready 120 || {
        log "ERROR: SSH connection failed"
        log "QEMU output log:"
        cat qemu_output.log >> "$LOG_FILE" 2>&1
        return 1
    }
}
