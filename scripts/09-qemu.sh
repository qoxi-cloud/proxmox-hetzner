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

# Release NVMe drives from any existing locks
release_drives() {
    # Kill any existing QEMU processes
    pkill -9 qemu-system-x86 2>/dev/null || true

    # Stop mdadm arrays that might use NVMe drives
    if command -v mdadm &>/dev/null; then
        mdadm --stop --scan 2>/dev/null || true
    fi

    # Deactivate LVM volume groups on NVMe
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

    # Release any locks on NVMe drives (in background of spinner)
    release_drives

    # Clear the line for fresh progress
    printf "\r\e[K"

    # Run QEMU in background with error logging
    qemu-system-x86_64 -enable-kvm $UEFI_OPTS \
        -cpu host -smp $QEMU_CORES -m $QEMU_RAM \
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

    nohup qemu-system-x86_64 -enable-kvm $UEFI_OPTS \
        -cpu host -device e1000,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::5555-:22 \
        -smp $QEMU_CORES -m $QEMU_RAM \
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
