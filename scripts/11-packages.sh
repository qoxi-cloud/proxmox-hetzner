# shellcheck shell=bash
# =============================================================================
# Package preparation and ISO download
# =============================================================================

prepare_packages() {
    log "Starting package preparation"

    log "Adding Proxmox repository"
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve.list

    # Download Proxmox GPG key
    log "Downloading Proxmox GPG key"
    curl -fsSL -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg >> "$LOG_FILE" 2>&1 &
    show_progress $! "Downloading Proxmox GPG key" "Proxmox GPG key downloaded"
    wait $!
    if [[ $? -ne 0 ]]; then
        log "ERROR: Failed to download Proxmox GPG key"
        print_error "Failed to download Proxmox GPG key! Exiting."
        exit 1
    fi
    log "Proxmox GPG key downloaded successfully"

    # Update package lists
    log "Updating package lists"
    apt clean >> "$LOG_FILE" 2>&1
    apt update >> "$LOG_FILE" 2>&1 &
    show_progress $! "Updating package lists" "Package lists updated"
    wait $!
    if [[ $? -ne 0 ]]; then
        log "ERROR: Failed to update package lists"
        print_error "Failed to update package lists! Exiting."
        exit 1
    fi
    log "Package lists updated successfully"

    # Install packages
    log "Installing required packages: proxmox-auto-install-assistant xorriso ovmf wget sshpass"
    apt install -yq proxmox-auto-install-assistant xorriso ovmf wget sshpass >> "$LOG_FILE" 2>&1 &
    show_progress $! "Installing required packages" "Required packages installed"
    wait $!
    if [[ $? -ne 0 ]]; then
        log "ERROR: Failed to install required packages"
        print_error "Failed to install required packages! Exiting."
        exit 1
    fi
    log "Required packages installed successfully"
}

# Fetch available Proxmox VE ISO versions (last N versions)
# Returns array of ISO filenames, newest first
get_available_proxmox_isos() {
    local count="${1:-5}"
    local base_url="https://enterprise.proxmox.com/iso/"

    curl -s "$base_url" | grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | sort -uV | tail -n "$count" | tac
}

# Fetch latest Proxmox VE ISO URL
get_latest_proxmox_ve_iso() {
    local base_url="https://enterprise.proxmox.com/iso/"
    local latest_iso
    latest_iso=$(curl -s "$base_url" | grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | sort -V | tail -n1)

    if [[ -n "$latest_iso" ]]; then
        echo "${base_url}${latest_iso}"
    else
        echo "No Proxmox VE ISO found." >&2
        return 1
    fi
}

# Get ISO URL by filename
get_proxmox_iso_url() {
    local iso_filename="$1"
    echo "https://enterprise.proxmox.com/iso/${iso_filename}"
}

# Extract version from ISO filename (e.g., "8.3-1" from "proxmox-ve_8.3-1.iso")
get_iso_version() {
    local iso_filename="$1"
    echo "$iso_filename" | sed -E 's/proxmox-ve_([0-9]+\.[0-9]+-[0-9]+)\.iso/\1/'
}

download_proxmox_iso() {
    log "Starting Proxmox ISO download"

    if [[ -f "pve.iso" ]]; then
        log "Proxmox ISO already exists, skipping download"
        print_success "Proxmox ISO already exists, skipping download"
        return 0
    fi

    # Use selected ISO or fetch latest
    if [[ -n "$PROXMOX_ISO_VERSION" ]]; then
        log "Using user-selected ISO: $PROXMOX_ISO_VERSION"
        PROXMOX_ISO_URL=$(get_proxmox_iso_url "$PROXMOX_ISO_VERSION")
    else
        log "Fetching latest Proxmox ISO URL"
        PROXMOX_ISO_URL=$(get_latest_proxmox_ve_iso)
    fi

    if [[ -z "$PROXMOX_ISO_URL" ]]; then
        log "ERROR: Failed to retrieve Proxmox ISO URL"
        print_error "Failed to retrieve Proxmox ISO URL! Exiting."
        exit 1
    fi
    log "Found ISO URL: $PROXMOX_ISO_URL"

    ISO_FILENAME=$(basename "$PROXMOX_ISO_URL")
    CHECKSUM_URL="https://enterprise.proxmox.com/iso/SHA256SUMS"

    # Download ISO with progress spinner (silent wget)
    log "Downloading ISO: $ISO_FILENAME"
    wget -q -O pve.iso "$PROXMOX_ISO_URL" >> "$LOG_FILE" 2>&1 &
    show_progress $! "Downloading $ISO_FILENAME" "$ISO_FILENAME downloaded"
    wait $!
    if [[ $? -ne 0 ]]; then
        log "ERROR: Failed to download Proxmox ISO"
        print_error "Failed to download Proxmox ISO! Exiting."
        exit 1
    fi
    log "ISO downloaded successfully"

    if [[ ! -s "pve.iso" ]]; then
        log "ERROR: Downloaded ISO file is empty or corrupted"
        print_error "Downloaded ISO file is empty or corrupted! Exiting."
        rm -f pve.iso
        exit 1
    fi
    log "ISO file size: $(ls -lh pve.iso | awk '{print $5}')"

    # Download ISO checksum
    log "Downloading checksum file"
    wget -q -O SHA256SUMS "$CHECKSUM_URL" >> "$LOG_FILE" 2>&1

    if [[ -f "SHA256SUMS" ]]; then
        EXPECTED_CHECKSUM=$(grep "$ISO_FILENAME" SHA256SUMS | awk '{print $1}')
        log "Expected checksum: $EXPECTED_CHECKSUM"
        if [[ -n "$EXPECTED_CHECKSUM" ]]; then
            sha256sum pve.iso > /tmp/iso_checksum.txt 2>/dev/null &
            show_progress $! "Verifying ISO checksum" "ISO checksum verified"
            wait $!
            ACTUAL_CHECKSUM=$(cat /tmp/iso_checksum.txt | awk '{print $1}')
            log "Actual checksum: $ACTUAL_CHECKSUM"
            rm -f /tmp/iso_checksum.txt

            if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
                log "ERROR: ISO checksum verification FAILED"
                print_error "ISO checksum verification FAILED!"
                print_error "Expected: $EXPECTED_CHECKSUM"
                print_error "Actual:   $ACTUAL_CHECKSUM"
                rm -f pve.iso SHA256SUMS
                exit 1
            fi
            log "Checksum verification passed"
        else
            log "WARNING: Could not find checksum for $ISO_FILENAME"
            print_warning "Could not find checksum for $ISO_FILENAME"
        fi
        rm -f SHA256SUMS
    else
        log "WARNING: Could not download checksum file"
        print_warning "Could not download checksum file"
    fi
}

make_answer_toml() {
    log "Creating answer.toml for autoinstall"
    log "ZFS_RAID=$ZFS_RAID, DRIVE_COUNT=$DRIVE_COUNT"

    # Build disk_list based on ZFS_RAID mode (using vda/vdb for QEMU virtio)
    case "$ZFS_RAID" in
        single)
            DISK_LIST='["/dev/vda"]'
            ;;
        raid0|raid1)
            DISK_LIST='["/dev/vda", "/dev/vdb"]'
            ;;
        *)
            # Default to raid1 for 2 drives
            DISK_LIST='["/dev/vda", "/dev/vdb"]'
            ;;
    esac
    log "DISK_LIST=$DISK_LIST"

    # Determine ZFS raid level - always required for ZFS filesystem
    local zfs_raid_value
    if [[ "$DRIVE_COUNT" -ge 2 && -n "$ZFS_RAID" && "$ZFS_RAID" != "single" ]]; then
        zfs_raid_value="$ZFS_RAID"
    else
        # Single disk or single mode selected - must use raid0 (single disk stripe)
        zfs_raid_value="raid0"
    fi
    local zfs_raid_line="    zfs.raid = \"$zfs_raid_value\""
    log "Using ZFS raid: $zfs_raid_value"

    cat <<EOF > answer.toml
[global]
    keyboard = "en-us"
    country = "us"
    fqdn = "$FQDN"
    mailto = "$EMAIL"
    timezone = "$TIMEZONE"
    root_password = "$NEW_ROOT_PASSWORD"
    reboot_on_error = false

[network]
    source = "from-dhcp"

[disk-setup]
    filesystem = "zfs"
${zfs_raid_line}
    disk_list = $DISK_LIST

EOF

    log "answer.toml created:"
    cat answer.toml >> "$LOG_FILE"
}

make_autoinstall_iso() {
    log "Creating autoinstall ISO"
    log "Input: pve.iso exists: $(test -f pve.iso && echo 'yes' || echo 'no')"
    log "Input: answer.toml exists: $(test -f answer.toml && echo 'yes' || echo 'no')"
    log "Current directory: $(pwd)"
    log "Files in current directory:"
    ls -la >> "$LOG_FILE" 2>&1

    # Run ISO creation with full logging
    proxmox-auto-install-assistant prepare-iso pve.iso --fetch-from iso --answer-file answer.toml --output pve-autoinstall.iso >> "$LOG_FILE" 2>&1 &
    show_progress $! "Creating autoinstall ISO" "Autoinstall ISO created"

    # Verify ISO was created
    if [[ ! -f "./pve-autoinstall.iso" ]]; then
        log "ERROR: Autoinstall ISO not found after creation attempt"
        log "Files in current directory after attempt:"
        ls -la >> "$LOG_FILE" 2>&1
        print_error "Autoinstall ISO not found!"
        print_error "Check log file: $LOG_FILE"
        exit 1
    fi

    log "Autoinstall ISO created successfully: $(ls -lh pve-autoinstall.iso 2>/dev/null | awk '{print $5}')"

    # Remove original ISO to save disk space (only autoinstall ISO is needed)
    log "Removing original ISO to save disk space"
    rm -f pve.iso
}
