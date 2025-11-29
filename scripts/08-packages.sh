# =============================================================================
# Package preparation and ISO download
# =============================================================================

prepare_packages() {
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve.list

    # Download Proxmox GPG key
    curl -fsSL -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg &
    show_progress $! "Downloading Proxmox GPG key" "Proxmox GPG key downloaded"
    wait $!
    if [[ $? -ne 0 ]]; then
        print_error "Failed to download Proxmox GPG key! Exiting."
        exit 1
    fi

    # Update package lists
    apt clean > /dev/null 2>&1
    apt update > /dev/null 2>&1 &
    show_progress $! "Updating package lists" "Package lists updated"
    wait $!
    if [[ $? -ne 0 ]]; then
        print_error "Failed to update package lists! Exiting."
        exit 1
    fi

    # Install packages
    apt install -yq proxmox-auto-install-assistant xorriso ovmf wget sshpass > /dev/null 2>&1 &
    show_progress $! "Installing required packages" "Required packages installed"
    wait $!
    if [[ $? -ne 0 ]]; then
        print_error "Failed to install required packages! Exiting."
        exit 1
    fi
}

# Fetch latest Proxmox VE ISO
get_latest_proxmox_ve_iso() {
    local base_url="https://enterprise.proxmox.com/iso/"
    local latest_iso=$(curl -s "$base_url" | grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | sort -V | tail -n1)

    if [[ -n "$latest_iso" ]]; then
        echo "${base_url}${latest_iso}"
    else
        echo "No Proxmox VE ISO found." >&2
        return 1
    fi
}

download_proxmox_iso() {
    if [[ -f "pve.iso" ]]; then
        print_success "Proxmox ISO already exists, skipping download"
        return 0
    fi

    PROXMOX_ISO_URL=$(get_latest_proxmox_ve_iso)
    if [[ -z "$PROXMOX_ISO_URL" ]]; then
        print_error "Failed to retrieve Proxmox ISO URL! Exiting."
        exit 1
    fi

    ISO_FILENAME=$(basename "$PROXMOX_ISO_URL")
    CHECKSUM_URL="https://enterprise.proxmox.com/iso/SHA256SUMS"

    # Download ISO with progress spinner (silent wget)
    wget -q -O pve.iso "$PROXMOX_ISO_URL" 2>/dev/null &
    show_progress $! "Downloading $ISO_FILENAME" "$ISO_FILENAME downloaded"
    wait $!
    if [[ $? -ne 0 ]]; then
        print_error "Failed to download Proxmox ISO! Exiting."
        exit 1
    fi

    if [[ ! -s "pve.iso" ]]; then
        print_error "Downloaded ISO file is empty or corrupted! Exiting."
        rm -f pve.iso
        exit 1
    fi

    # Download ISO checksum
    wget -q -O SHA256SUMS "$CHECKSUM_URL" 2>/dev/null

    if [[ -f "SHA256SUMS" ]]; then
        EXPECTED_CHECKSUM=$(grep "$ISO_FILENAME" SHA256SUMS | awk '{print $1}')
        if [[ -n "$EXPECTED_CHECKSUM" ]]; then
            sha256sum pve.iso > /tmp/iso_checksum.txt 2>/dev/null &
            show_progress $! "Verifying ISO checksum" "ISO checksum verified"
            wait $!
            ACTUAL_CHECKSUM=$(cat /tmp/iso_checksum.txt | awk '{print $1}')
            rm -f /tmp/iso_checksum.txt

            if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
                print_error "ISO checksum verification FAILED!"
                print_error "Expected: $EXPECTED_CHECKSUM"
                print_error "Actual:   $ACTUAL_CHECKSUM"
                rm -f pve.iso SHA256SUMS
                exit 1
            fi
        else
            print_warning "Could not find checksum for $ISO_FILENAME"
        fi
        rm -f SHA256SUMS
    else
        print_warning "Could not download checksum file"
    fi
}

make_answer_toml() {
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
    zfs.raid = "$ZFS_RAID"
    disk_list = $DISK_LIST

EOF
}

make_autoinstall_iso() {
    proxmox-auto-install-assistant prepare-iso pve.iso --fetch-from iso --answer-file answer.toml --output pve-autoinstall.iso > /dev/null 2>&1 &
    show_progress $! "Creating autoinstall ISO" "Autoinstall ISO created"

    # Remove original ISO to save disk space (only autoinstall ISO is needed)
    rm -f pve.iso
}
