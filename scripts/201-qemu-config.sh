# shellcheck shell=bash
# QEMU configuration

# Check if UEFI mode. Returns 0=UEFI, 1=BIOS
is_uefi_mode() {
  [[ -d /sys/firmware/efi ]]
}

# Configure QEMU settings. Sets UEFI_OPTS, KVM_OPTS, QEMU_CORES/RAM, DRIVE_ARGS.
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

  # KVM acceleration
  KVM_OPTS="-enable-kvm"
  CPU_OPTS="-cpu host"
  log "Using KVM acceleration"

  # CPU and RAM configuration
  local available_cores available_ram_mb
  available_cores=$(nproc)
  available_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
  log "Available cores: $available_cores, Available RAM: ${available_ram_mb}MB"

  # Use override values if provided, otherwise auto-detect
  if [[ -n $QEMU_CORES_OVERRIDE ]]; then
    QEMU_CORES="$QEMU_CORES_OVERRIDE"
    log "Using user-specified cores: $QEMU_CORES"
  else
    # Use all available cores for QEMU
    QEMU_CORES=$available_cores
    [[ $QEMU_CORES -lt $MIN_CPU_CORES ]] && QEMU_CORES=$MIN_CPU_CORES
  fi

  if [[ -n $QEMU_RAM_OVERRIDE ]]; then
    QEMU_RAM="$QEMU_RAM_OVERRIDE"
    log "Using user-specified RAM: ${QEMU_RAM}MB"
    # Warn if requested RAM exceeds available
    if [[ $QEMU_RAM -gt $((available_ram_mb - QEMU_MIN_RAM_RESERVE)) ]]; then
      print_warning "Requested QEMU RAM (${QEMU_RAM}MB) may exceed safe limits (available: ${available_ram_mb}MB)"
    fi
  else
    # Use all available RAM minus reserve for host
    QEMU_RAM=$((available_ram_mb - QEMU_MIN_RAM_RESERVE))
    [[ $QEMU_RAM -lt $MIN_QEMU_RAM ]] && QEMU_RAM=$MIN_QEMU_RAM
  fi

  log "QEMU config: $QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM"

  # Load virtio mapping (created by make_answer_toml)
  if ! load_virtio_mapping; then
    log "ERROR: Failed to load virtio mapping"
    return 1
  fi

  # Validate VIRTIO_MAP is not empty before proceeding
  if [[ ${#VIRTIO_MAP[@]} -eq 0 ]]; then
    log "ERROR: VIRTIO_MAP is empty - no disks mapped for QEMU"
    print_error "No disks available for QEMU. Check disk detection."
    return 1
  fi

  # Build DRIVE_ARGS from virtio mapping (iterate over all mapped disks)
  # This avoids relying on ZFS_POOL_DISKS array which isn't available in backgrounded subshells
  DRIVE_ARGS=""

  # Get all disks from VIRTIO_MAP keys (sorted by virtio device for consistent ordering)
  local disk
  for disk in "${!VIRTIO_MAP[@]}"; do
    # Validate disk exists before adding to QEMU args
    if [[ ! -b $disk ]]; then
      log "ERROR: Disk $disk does not exist or is not a block device"
      return 1
    fi
    DRIVE_ARGS="$DRIVE_ARGS -drive file=$disk,format=raw,media=disk,if=virtio"
  done

  if [[ -z $DRIVE_ARGS ]]; then
    log "ERROR: No drive arguments built - QEMU would start without disks"
    return 1
  fi

  log "Drive args: $DRIVE_ARGS"
}
