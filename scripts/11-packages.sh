# shellcheck shell=bash
# =============================================================================
# Package preparation and ISO download
# =============================================================================

prepare_packages() {
    log "Starting package preparation"

    # Check repository availability before proceeding
    log "Checking Proxmox repository availability"
    if ! curl -fsSL --max-time 10 "https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg" > /dev/null 2>&1; then
        print_error "Cannot reach Proxmox repository"
        log "ERROR: Cannot reach Proxmox repository"
        exit 1
    fi

    log "Adding Proxmox repository"
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve.list

    # Download Proxmox GPG key
    log "Downloading Proxmox GPG key"
    curl -fsSL -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg >> "$LOG_FILE" 2>&1 &
    show_progress $! "Downloading Proxmox GPG key" "Proxmox GPG key downloaded"
    wait $!
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: Failed to download Proxmox GPG key"
        exit 1
    fi
    log "Proxmox GPG key downloaded successfully"

    # Update package lists
    log "Updating package lists"
    apt clean >> "$LOG_FILE" 2>&1
    apt update >> "$LOG_FILE" 2>&1 &
    show_progress $! "Updating package lists" "Package lists updated"
    wait $!
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: Failed to update package lists"
        exit 1
    fi
    log "Package lists updated successfully"

    # Install packages
    log "Installing required packages: proxmox-auto-install-assistant xorriso ovmf wget sshpass"
    apt install -yq proxmox-auto-install-assistant xorriso ovmf wget sshpass >> "$LOG_FILE" 2>&1 &
    show_progress $! "Installing required packages" "Required packages installed"
    wait $!
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: Failed to install required packages"
        exit 1
    fi
    log "Required packages installed successfully"
}

# Cache for ISO list (avoid multiple HTTP requests)
_ISO_LIST_CACHE=""

# Fetch ISO list from Proxmox repository (cached)
_fetch_iso_list() {
    if [[ -z "$_ISO_LIST_CACHE" ]]; then
        _ISO_LIST_CACHE=$(curl -s "$PROXMOX_ISO_BASE_URL" | grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | sort -uV)
    fi
    echo "$_ISO_LIST_CACHE"
}

# Fetch available Proxmox VE ISO versions (last N versions)
# Returns array of ISO filenames, newest first
get_available_proxmox_isos() {
    local count="${1:-5}"
    _fetch_iso_list | tail -n "$count" | tac
}

# Fetch latest Proxmox VE ISO URL
get_latest_proxmox_ve_iso() {
    local latest_iso
    latest_iso=$(_fetch_iso_list | tail -n1)

    if [[ -n "$latest_iso" ]]; then
        echo "${PROXMOX_ISO_BASE_URL}${latest_iso}"
    else
        echo "No Proxmox VE ISO found." >&2
        return 1
    fi
}

# Get ISO URL by filename
get_proxmox_iso_url() {
    local iso_filename="$1"
    echo "${PROXMOX_ISO_BASE_URL}${iso_filename}"
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
        exit 1
    fi
    log "Found ISO URL: $PROXMOX_ISO_URL"

    ISO_FILENAME=$(basename "$PROXMOX_ISO_URL")

    # Download checksum first (needed for aria2c verification)
    log "Downloading checksum file"
    curl -sS -o SHA256SUMS "$PROXMOX_CHECKSUM_URL" >> "$LOG_FILE" 2>&1 || true
    local expected_checksum=""
    if [[ -f "SHA256SUMS" ]]; then
        expected_checksum=$(grep "$ISO_FILENAME" SHA256SUMS | awk '{print $1}')
        log "Expected checksum: $expected_checksum"
    fi

    # Download ISO using aria2c (parallel connections for faster download)
    log "Downloading ISO: $ISO_FILENAME using aria2c"
    local aria2_args=(
        -x 8                    # 8 connections per server
        -s 8                    # 8 splits
        -k 1M                   # 1MB minimum split size
        --allow-overwrite=true
        --auto-file-renaming=false
        -o pve.iso
        --console-log-level=error
        --summary-interval=0
    )

    # Add checksum verification if available
    if [[ -n "$expected_checksum" ]]; then
        aria2_args+=(--checksum=sha-256="$expected_checksum")
        log "aria2c will verify checksum automatically"
    fi

    aria2c "${aria2_args[@]}" "$PROXMOX_ISO_URL" >> "$LOG_FILE" 2>&1 &
    show_progress $! "Downloading $ISO_FILENAME (8 connections)" "$ISO_FILENAME downloaded"
    wait $!
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: Failed to download Proxmox ISO (aria2c exit code: $exit_code)"
        rm -f pve.iso SHA256SUMS
        exit 1
    fi
    log "ISO downloaded successfully"

    if [[ ! -s "pve.iso" ]]; then
        log "ERROR: Downloaded ISO file is empty or corrupted"
        rm -f pve.iso SHA256SUMS
        exit 1
    fi
    log "ISO file size: $(stat -c%s pve.iso | awk '{printf "%.1fG", $1/1024/1024/1024}')"

    # Verify checksum if aria2c didn't do it (checksum wasn't available)
    if [[ -z "$expected_checksum" ]] && [[ -f "SHA256SUMS" ]]; then
        expected_checksum=$(grep "$ISO_FILENAME" SHA256SUMS | awk '{print $1}')
    fi

    if [[ -n "$expected_checksum" ]]; then
        # aria2c already verified if checksum was provided, but double-check if needed
        log "Checksum verification passed (verified by aria2c)"
    else
        log "WARNING: Could not find checksum for $ISO_FILENAME"
        print_warning "Could not find checksum for $ISO_FILENAME"
    fi

    rm -f SHA256SUMS
}

# Validate answer.toml has required fields
validate_answer_toml() {
    local file="$1"
    local required_fields=("fqdn" "mailto" "timezone" "root_password")

    for field in "${required_fields[@]}"; do
        if ! grep -q "^\s*${field}\s*=" "$file" 2>/dev/null; then
            log "ERROR: Missing required field in answer.toml: $field"
            return 1
        fi
    done

    if ! grep -q "\[global\]" "$file" 2>/dev/null; then
        log "ERROR: Missing [global] section in answer.toml"
        return 1
    fi

    return 0
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
    log "Using ZFS raid: $zfs_raid_value"

    # Download and process answer.toml template
    download_template "./answer.toml" "answer.toml"

    # Apply variable substitutions
    apply_template_vars "./answer.toml" \
        "FQDN=$FQDN" \
        "EMAIL=$EMAIL" \
        "TIMEZONE=$TIMEZONE" \
        "ROOT_PASSWORD=$NEW_ROOT_PASSWORD" \
        "ZFS_RAID=$zfs_raid_value" \
        "DISK_LIST=$DISK_LIST"

    # Validate the generated file
    if ! validate_answer_toml "./answer.toml"; then
        log "ERROR: answer.toml validation failed"
        exit 1
    fi

    log "answer.toml created and validated:"
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
        exit 1
    fi

    log "Autoinstall ISO created successfully: $(ls -lh pve-autoinstall.iso 2>/dev/null | awk '{print $5}')"

    # Remove original ISO to save disk space (only autoinstall ISO is needed)
    log "Removing original ISO to save disk space"
    rm -f pve.iso
}
