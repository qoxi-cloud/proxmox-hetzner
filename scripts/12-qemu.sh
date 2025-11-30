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
        [[ $QEMU_CORES -lt 2 ]] && QEMU_CORES=2
        [[ $QEMU_CORES -gt $available_cores ]] && QEMU_CORES=$available_cores
        [[ $QEMU_CORES -gt 16 ]] && QEMU_CORES=16
    fi

    if [[ -n "$QEMU_RAM_OVERRIDE" ]]; then
        QEMU_RAM="$QEMU_RAM_OVERRIDE"
        log "Using user-specified RAM: ${QEMU_RAM}MB"
        # Warn if requested RAM exceeds available
        if [[ $QEMU_RAM -gt $((available_ram_mb - 2048)) ]]; then
            print_warning "Requested QEMU RAM (${QEMU_RAM}MB) may exceed safe limits (available: ${available_ram_mb}MB)"
        fi
    else
        QEMU_RAM=8192
        [[ $available_ram_mb -lt 16384 ]] && QEMU_RAM=4096
    fi

    log "QEMU config: $QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM"

    # Drive configuration - add all detected drives
    DRIVE_ARGS=""
    for drive in "${DRIVES[@]}"; do
        DRIVE_ARGS="$DRIVE_ARGS -drive file=$drive,format=raw,media=disk,if=virtio"
    done
    log "Drive args: $DRIVE_ARGS"
}

# Release drives from any existing locks
release_drives() {
    # Kill any existing QEMU processes
    pkill -9 qemu-system-x86 2>/dev/null || true

    # Stop mdadm arrays that might use the drives
    if command -v mdadm &>/dev/null; then
        mdadm --stop --scan 2>/dev/null || true
    fi

    # Deactivate LVM volume groups
    if command -v vgchange &>/dev/null; then
        vgchange -an 2>/dev/null || true
    fi

    # Give system time to release locks
    sleep 2
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
    printf "${CLR_YELLOW}⠋ %s${CLR_RESET}" "$install_msg"

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
        print_error "QEMU failed to start! Check qemu_install.log:"
        cat qemu_install.log
        exit 1
    fi

    show_progress $qemu_pid "$install_msg" "Proxmox VE installed"

    # Verify installation completed (QEMU exited cleanly)
    wait $qemu_pid
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "QEMU installation failed with exit code $exit_code"
        print_error "Check qemu_install.log for details"
        cat qemu_install.log
        exit 1
    fi
}

# Boot installed Proxmox with SSH port forwarding
boot_proxmox_with_port_forwarding() {
    setup_qemu_config

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

    # Show immediate feedback before SSH ready check
    printf "${CLR_YELLOW}⠋ Waiting for SSH to be ready...${CLR_RESET}"

    # Wait for SSH to be fully ready (handles key exchange timing)
    printf "\r\e[K"
    wait_for_ssh_ready 60 || {
        print_error "SSH connection failed. Check qemu_output.log for details."
        return 1
    }
}
