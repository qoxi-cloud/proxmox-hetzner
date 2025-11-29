# =============================================================================
# QEMU installation and boot functions
# =============================================================================

is_uefi_mode() {
    [[ -d /sys/firmware/efi ]]
}

# Configure QEMU settings (shared between install and boot)
setup_qemu_config() {
    # UEFI configuration
    if is_uefi_mode; then
        UEFI_OPTS="-bios /usr/share/ovmf/OVMF.fd"
    else
        UEFI_OPTS=""
    fi

    # CPU and RAM configuration
    local available_cores=$(nproc)
    local available_ram_mb=$(free -m | awk '/^Mem:/{print $2}')

    QEMU_CORES=$((available_cores / 2))
    [[ $QEMU_CORES -lt 2 ]] && QEMU_CORES=2
    [[ $QEMU_CORES -gt $available_cores ]] && QEMU_CORES=$available_cores
    [[ $QEMU_CORES -gt 16 ]] && QEMU_CORES=16

    QEMU_RAM=8192
    [[ $available_ram_mb -lt 16384 ]] && QEMU_RAM=4096

    # Drive configuration
    DRIVE_ARGS="-drive file=$NVME_DRIVE_1,format=raw,media=disk,if=virtio"
    [[ -n "$NVME_DRIVE_2" ]] && DRIVE_ARGS="$DRIVE_ARGS -drive file=$NVME_DRIVE_2,format=raw,media=disk,if=virtio"
}

# Install Proxmox via QEMU
install_proxmox() {
    setup_qemu_config

    # Run QEMU in background and show progress
    qemu-system-x86_64 -enable-kvm $UEFI_OPTS \
        -cpu host -smp $QEMU_CORES -m $QEMU_RAM \
        -boot d -cdrom ./pve-autoinstall.iso \
        $DRIVE_ARGS -no-reboot -display none > /dev/null 2>&1 &

    show_progress $! "Installing Proxmox VE (${QEMU_CORES} vCPUs, ${QEMU_RAM}MB RAM)" "Proxmox VE installed"
}

# Boot installed Proxmox with SSH port forwarding
boot_proxmox_with_port_forwarding() {
    setup_qemu_config

    nohup qemu-system-x86_64 -enable-kvm $UEFI_OPTS \
        -cpu host -device e1000,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::5555-:22 \
        -smp $QEMU_CORES -m $QEMU_RAM \
        $DRIVE_ARGS -display none \
        > qemu_output.log 2>&1 &

    QEMU_PID=$!

    # Wait for SSH with progress indicator (timeout 5 minutes)
    wait_with_progress "Booting installed Proxmox" 300 "(echo >/dev/tcp/localhost/5555)" 3 "Proxmox booted, SSH available"
}
