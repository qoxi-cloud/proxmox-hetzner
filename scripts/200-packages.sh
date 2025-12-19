# shellcheck shell=bash
# =============================================================================
# Package preparation and ISO download
# =============================================================================

# Prepares system packages for Proxmox installation.
# Adds Proxmox repository, downloads GPG key, installs required packages.
# Side effects: Modifies apt sources, installs packages
prepare_packages() {
  log "Starting package preparation"

  log "Adding Proxmox repository"
  echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >/etc/apt/sources.list.d/pve.list

  # Download Proxmox GPG key
  log "Downloading Proxmox GPG key"
  curl -fsSL -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg >>"$LOG_FILE" 2>&1 &
  show_progress $! "Adding Proxmox repository" "Proxmox repository added"
  wait $!
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Failed to download Proxmox GPG key"
    print_error "Cannot reach Proxmox repository"
    exit 1
  fi
  log "Proxmox GPG key downloaded successfully"

  # Add live log subtask after completion
  if type live_log_subtask &>/dev/null 2>&1; then
    live_log_subtask "Configuring APT sources"
  fi

  # Update package lists
  log "Updating package lists"
  apt clean >>"$LOG_FILE" 2>&1
  apt update >>"$LOG_FILE" 2>&1 &
  show_progress $! "Updating package lists" "Package lists updated"
  wait $!
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Failed to update package lists"
    exit 1
  fi
  log "Package lists updated successfully"

  # Add live log subtask after completion
  if type live_log_subtask &>/dev/null 2>&1; then
    live_log_subtask "Downloading package lists"
  fi

  # Install packages
  log "Installing required packages: proxmox-auto-install-assistant xorriso ovmf wget sshpass"
  apt install -yq proxmox-auto-install-assistant xorriso ovmf wget sshpass >>"$LOG_FILE" 2>&1 &
  show_progress $! "Installing required packages" "Required packages installed"
  wait $!
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Failed to install required packages"
    exit 1
  fi
  log "Required packages installed successfully"

  # Add live log subtasks after completion
  if type live_log_subtask &>/dev/null 2>&1; then
    live_log_subtask "Installing proxmox-auto-install-assistant"
    live_log_subtask "Installing xorriso and ovmf"
  fi
}

# Cache for ISO list (populated by prefetch_proxmox_iso_info)
_ISO_LIST_CACHE=""

# Cache for SHA256SUMS content
_CHECKSUM_CACHE=""

# Prefetches ISO list and checksums.
# Call this early to cache data for later use.
# Side effects: Populates _ISO_LIST_CACHE and _CHECKSUM_CACHE
prefetch_proxmox_iso_info() {
  _ISO_LIST_CACHE=$(curl -s "$PROXMOX_ISO_BASE_URL" 2>/dev/null | grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | sort -uV) || true
  _CHECKSUM_CACHE=$(curl -s "$PROXMOX_CHECKSUM_URL" 2>/dev/null) || true
}

# Returns available Proxmox VE ISO versions (last N versions).
# Parameters:
#   $1 - Number of versions to return (default: 5)
# Returns: ISO filenames via stdout, newest first
get_available_proxmox_isos() {
  local count="${1:-5}"
  echo "$_ISO_LIST_CACHE" | tail -n "$count" | tac
}

# Constructs full ISO URL from filename.
# Parameters:
#   $1 - ISO filename
# Returns: Full URL via stdout
get_proxmox_iso_url() {
  local iso_filename="$1"
  echo "${PROXMOX_ISO_BASE_URL}${iso_filename}"
}

# Extracts version from ISO filename.
# Parameters:
#   $1 - ISO filename (e.g., "proxmox-ve_8.3-1.iso")
# Returns: Version string (e.g., "8.3-1") via stdout
get_iso_version() {
  local iso_filename="$1"
  echo "$iso_filename" | sed -E 's/proxmox-ve_([0-9]+\.[0-9]+-[0-9]+)\.iso/\1/'
}

# Internal: downloads ISO using curl with retry support.
# Parameters:
#   $1 - URL to download
#   $2 - Output filename
# Returns: Exit code from curl
_download_iso_curl() {
  local url="$1"
  local output="$2"
  local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"
  local retry_delay="${DOWNLOAD_RETRY_DELAY:-5}"

  log "Downloading with curl (single connection, resume-enabled)"
  curl -fSL \
    --retry "$max_retries" \
    --retry-delay "$retry_delay" \
    --retry-connrefused \
    -C - \
    -o "$output" \
    "$url" >>"$LOG_FILE" 2>&1
}

# Internal: downloads ISO using wget with retry support.
# Parameters:
#   $1 - URL to download
#   $2 - Output filename
# Returns: Exit code from wget
_download_iso_wget() {
  local url="$1"
  local output="$2"
  local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"

  log "Downloading with wget (single connection, resume-enabled)"
  wget -q \
    --tries="$max_retries" \
    --continue \
    --timeout=60 \
    --waitretry=5 \
    -O "$output" \
    "$url" >>"$LOG_FILE" 2>&1
}

# Internal: downloads ISO using aria2c with conservative settings.
# Parameters:
#   $1 - URL to download
#   $2 - Output filename
#   $3 - Optional SHA256 checksum for verification
# Returns: Exit code from aria2c
_download_iso_aria2c() {
  local url="$1"
  local output="$2"
  local checksum="$3"
  local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"

  log "Downloading with aria2c (2 connections, with retries)"
  local aria2_args=(
    -x 2  # 2 connections (conservative to avoid rate limiting)
    -s 2  # 2 splits
    -k 4M # 4MB minimum split size
    --max-tries="$max_retries"
    --retry-wait=5
    --timeout=60
    --connect-timeout=30
    --max-connection-per-server=2
    --allow-overwrite=true
    --auto-file-renaming=false
    -o "$output"
    --console-log-level=error
    --summary-interval=0
  )

  # Add checksum verification if available
  if [[ -n $checksum ]]; then
    aria2_args+=(--checksum=sha-256="$checksum")
    log "aria2c will verify checksum automatically"
  fi

  aria2c "${aria2_args[@]}" "$url" >>"$LOG_FILE" 2>&1
}

# Internal: downloads ISO using parallel downloaders (first wins).
# Starts all available downloaders simultaneously, uses first successful result.
# Parameters:
#   $1 - URL to download
#   $2 - Output filename
#   $3 - Optional SHA256 checksum
# Returns: 0 on success (sets DOWNLOAD_METHOD), 1 on all failures
# Side effects: Creates output file, cleans up temp files
_download_iso_parallel() {
  local url="$1"
  local output="$2"
  local checksum="$3"
  local temp_dir
  temp_dir=$(mktemp -d)
  local pids=()
  local methods=()

  log "Starting parallel download race"

  # Cleanup function
  _cleanup_parallel_download() {
    # Kill remaining processes immediately (no waiting needed)
    for pid in "${pids[@]}"; do
      kill "$pid" 2>/dev/null || true
    done
    # Remove temp files
    rm -rf "$temp_dir"
    rm -f "${output}.aria2" "${output}.curl" "${output}.wget" 2>/dev/null
  }

  # Start aria2c if available
  if command -v aria2c &>/dev/null; then
    (
      _download_iso_aria2c "$url" "$temp_dir/iso.aria2" "$checksum" \
        && [[ -s "$temp_dir/iso.aria2" ]] \
        && mv "$temp_dir/iso.aria2" "$temp_dir/done.aria2"
    ) 2>/dev/null &
    pids+=($!)
    methods+=("aria2c")
    log "Started aria2c downloader (PID: $!)"
  fi

  # Start curl
  (
    _download_iso_curl "$url" "$temp_dir/iso.curl" \
      && [[ -s "$temp_dir/iso.curl" ]] \
      && mv "$temp_dir/iso.curl" "$temp_dir/done.curl"
  ) 2>/dev/null &
  pids+=($!)
  methods+=("curl")
  log "Started curl downloader (PID: $!)"

  # Start wget if available
  if command -v wget &>/dev/null; then
    (
      _download_iso_wget "$url" "$temp_dir/iso.wget" \
        && [[ -s "$temp_dir/iso.wget" ]] \
        && mv "$temp_dir/iso.wget" "$temp_dir/done.wget"
    ) 2>/dev/null &
    pids+=($!)
    methods+=("wget")
    log "Started wget downloader (PID: $!)"
  fi

  # Wait for first success
  while true; do
    # Check for completed downloads
    for ext in aria2 curl wget; do
      if [[ -f "$temp_dir/done.$ext" ]] && [[ -s "$temp_dir/done.$ext" ]]; then
        log "Download completed by $ext"
        mv "$temp_dir/done.$ext" "$output"

        # Set method for caller
        case "$ext" in
          aria2) DOWNLOAD_METHOD="aria2c" ;;
          *) DOWNLOAD_METHOD="$ext" ;;
        esac

        _cleanup_parallel_download
        return 0
      fi
    done

    # Check if all processes have exited
    local all_dead=true
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        all_dead=false
        break
      fi
    done

    if $all_dead; then
      log "All download methods failed"
      _cleanup_parallel_download
      return 1
    fi

    sleep 1
  done
}

# Downloads Proxmox ISO with parallel downloaders and checksum verification.
# Requires PROXMOX_ISO_VERSION to be set (user selects version in wizard).
# Runs aria2c, curl, wget in parallel - first to finish wins.
# Side effects: Creates pve.iso file, exits on failure
download_proxmox_iso() {
  log "Starting Proxmox ISO download"

  if [[ -f "pve.iso" ]]; then
    log "Proxmox ISO already exists, skipping download"
    print_success "Proxmox ISO:" "already exists, skipping download"
    return 0
  fi

  if [[ -z $PROXMOX_ISO_VERSION ]]; then
    log "ERROR: PROXMOX_ISO_VERSION not set"
    exit 1
  fi

  log "Using selected ISO: $PROXMOX_ISO_VERSION"
  PROXMOX_ISO_URL=$(get_proxmox_iso_url "$PROXMOX_ISO_VERSION")
  log "Found ISO URL: $PROXMOX_ISO_URL"

  ISO_FILENAME=$(basename "$PROXMOX_ISO_URL")

  # Get checksum from cache (populated by prefetch_proxmox_iso_info)
  local expected_checksum=""
  if [[ -n $_CHECKSUM_CACHE ]]; then
    expected_checksum=$(echo "$_CHECKSUM_CACHE" | grep "$ISO_FILENAME" | awk '{print $1}')
  fi
  log "Expected checksum: ${expected_checksum:-not available}"

  # Download with parallel race: aria2c, curl, wget simultaneously
  log "Downloading ISO: $ISO_FILENAME (parallel mode)"
  DOWNLOAD_METHOD=""

  _download_iso_parallel "$PROXMOX_ISO_URL" "pve.iso" "$expected_checksum" &
  show_progress $! "Downloading $ISO_FILENAME" "$ISO_FILENAME downloaded"
  wait $!
  local exit_code=$?

  if [[ $exit_code -ne 0 ]] || [[ ! -s "pve.iso" ]]; then
    log "ERROR: All download methods failed for Proxmox ISO"
    rm -f pve.iso
    exit 1
  fi

  log "Download successful via $DOWNLOAD_METHOD"

  local iso_size
  iso_size=$(stat -c%s pve.iso 2>/dev/null) || iso_size=0
  log "ISO file size: $(echo "$iso_size" | awk '{printf "%.1fG", $1/1024/1024/1024}')"

  # Verify checksum (if not already verified by aria2c)
  if [[ -n $expected_checksum ]]; then
    # Skip manual verification if aria2c already validated
    if [[ $DOWNLOAD_METHOD == "aria2c" ]]; then
      log "Checksum already verified by aria2c"
      # Add live log for aria2c auto-verification
      if type live_log_subtask &>/dev/null 2>&1; then
        live_log_subtask "SHA256: OK (verified by aria2c)"
      fi
    else
      log "Verifying ISO checksum"
      local actual_checksum
      (actual_checksum=$(sha256sum pve.iso | awk '{print $1}') && echo "$actual_checksum" >/tmp/checksum_result) &
      local checksum_pid=$!
      if type show_progress &>/dev/null 2>&1; then
        show_progress $checksum_pid "Verifying checksum" "Checksum verified"
      else
        wait $checksum_pid
      fi
      actual_checksum=$(cat /tmp/checksum_result 2>/dev/null)
      rm -f /tmp/checksum_result
      if [[ $actual_checksum != "$expected_checksum" ]]; then
        log "ERROR: Checksum mismatch! Expected: $expected_checksum, Got: $actual_checksum"
        if type live_log_subtask &>/dev/null 2>&1; then
          live_log_subtask "SHA256: FAILED"
        fi
        rm -f pve.iso
        exit 1
      fi
      log "Checksum verification passed"
      if type live_log_subtask &>/dev/null 2>&1; then
        live_log_subtask "SHA256: OK"
      fi
    fi
  else
    log "WARNING: Could not find checksum for $ISO_FILENAME"
    print_warning "Could not find checksum for $ISO_FILENAME"
  fi

  # Clean up /tmp to free memory (rescue system uses tmpfs)
  log "Cleaning up temporary files in /tmp"
  rm -rf /tmp/tmp.* /tmp/pve-* /tmp/checksum_result 2>/dev/null || true
  log "Temporary files cleaned"
}

# Validates answer.toml has all required fields and correct format.
# Parameters:
#   $1 - Path to answer.toml file
# Returns: 0 if valid, 1 if validation fails
validate_answer_toml() {
  local file="$1"

  # Basic field validation
  # Note: Use kebab-case keys (root-password, not root_password)
  local required_fields=("fqdn" "mailto" "timezone" "root-password")
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

  # Validate using Proxmox auto-install assistant if available
  if command -v proxmox-auto-install-assistant &>/dev/null; then
    log "Validating answer.toml with proxmox-auto-install-assistant"
    if ! proxmox-auto-install-assistant validate-answer "$file" >>"$LOG_FILE" 2>&1; then
      log "ERROR: answer.toml validation failed"
      # Show validation errors in log
      proxmox-auto-install-assistant validate-answer "$file" >>"$LOG_FILE" 2>&1 || true
      return 1
    fi
    log "answer.toml validation passed"
  else
    log "WARNING: proxmox-auto-install-assistant not found, skipping advanced validation"
  fi

  return 0
}

# Creates answer.toml for Proxmox autoinstall.
# Downloads template and applies configuration variables.
# Side effects: Creates answer.toml file, exits on failure
make_answer_toml() {
  log "Creating answer.toml for autoinstall"
  log "ZFS_RAID=$ZFS_RAID, BOOT_DISK=$BOOT_DISK"
  log "ZFS_POOL_DISKS=(${ZFS_POOL_DISKS[*]})"

  # Create virtio mapping in background (pass values as args since arrays can't be exported)
  (
    create_virtio_mapping "$BOOT_DISK" "${ZFS_POOL_DISKS[@]}"
  ) &
  show_progress $! "Creating disk mapping" "Disk mapping created"

  # Load mapping into current shell
  load_virtio_mapping || {
    log "ERROR: Failed to load virtio mapping"
    exit 1
  }

  # Determine filesystem and disk list based on BOOT_DISK mode:
  # - BOOT_DISK set: ext4 on boot disk only, ZFS pool created post-install
  # - BOOT_DISK empty: ZFS on all disks (existing behavior)
  local FILESYSTEM
  local all_disks=()

  if [[ -n $BOOT_DISK ]]; then
    # Separate boot disk mode: ext4 on boot disk, ZFS pool created later
    FILESYSTEM="ext4"
    all_disks=("$BOOT_DISK")

    # Validate we have pool disks for post-install ZFS creation
    if [[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]]; then
      log "ERROR: BOOT_DISK set but no pool disks for ZFS tank creation"
      exit 1
    fi

    log "Boot disk mode: ext4 on boot disk, ZFS 'tank' pool will be created from ${#ZFS_POOL_DISKS[@]} pool disk(s)"
  else
    # All-ZFS mode: all disks in ZFS rpool
    FILESYSTEM="zfs"
    all_disks=("${ZFS_POOL_DISKS[@]}")

    log "All-ZFS mode: ${#all_disks[@]} disk(s) in ZFS rpool (${ZFS_RAID})"
  fi

  # Build DISK_LIST from all_disks using virtio mapping
  DISK_LIST=$(map_disks_to_virtio "toml_array" "${all_disks[@]}")
  if [[ -z $DISK_LIST ]]; then
    log "ERROR: Failed to map disks to virtio devices"
    exit 1
  fi

  log "FILESYSTEM=$FILESYSTEM, DISK_LIST=$DISK_LIST"

  # Generate answer.toml dynamically based on filesystem type
  # This allows conditional sections (ZFS vs LVM parameters)
  log "Generating answer.toml for autoinstall"

  # Prepare SSH keys array (TOML multiline array format)
  # Note: Use kebab-case for TOML keys (root-ssh-keys, not root_ssh_keys)
  local ssh_keys_toml=""
  if [[ -n $SSH_PUBLIC_KEY ]]; then
    # Escape the SSH key for TOML (escape backslashes and quotes)
    local escaped_key="${SSH_PUBLIC_KEY//\\/\\\\}"
    escaped_key="${escaped_key//\"/\\\"}"
    ssh_keys_toml="root-ssh-keys = [\"$escaped_key\"]"
  fi

  # Escape password for TOML (critical for user-entered passwords)
  local escaped_password="${NEW_ROOT_PASSWORD//\\/\\\\}" # Escape backslashes first
  escaped_password="${escaped_password//\"/\\\"}"        # Then escape quotes

  # Generate [global] section
  # IMPORTANT: Use kebab-case for all keys (root-password, reboot-on-error)
  cat >./answer.toml <<EOF
[global]
    keyboard = "$KEYBOARD"
    country = "$COUNTRY"
    fqdn = "$FQDN"
    mailto = "$EMAIL"
    timezone = "$TIMEZONE"
    root-password = "$escaped_password"
    reboot-on-error = false
EOF

  # Add SSH keys if available
  if [[ -n $ssh_keys_toml ]]; then
    echo "    $ssh_keys_toml" >>./answer.toml
  fi

  # Generate [network] section
  cat >>./answer.toml <<EOF

[network]
    source = "from-dhcp"

[disk-setup]
    filesystem = "$FILESYSTEM"
    disk-list = $DISK_LIST
EOF

  # Add filesystem-specific parameters
  if [[ $FILESYSTEM == "zfs" ]]; then
    # Map ZFS_RAID to answer.toml format
    local zfs_raid_value
    zfs_raid_value=$(map_raid_to_toml "$ZFS_RAID")
    log "Using ZFS raid: $zfs_raid_value"

    # Add ZFS parameters
    cat >>./answer.toml <<EOF
    zfs.raid = "$zfs_raid_value"
    zfs.compress = "lz4"
    zfs.checksum = "on"
EOF
  elif [[ $FILESYSTEM == "ext4" ]] || [[ $FILESYSTEM == "xfs" ]]; then
    # Add LVM parameters for ext4/xfs
    # swapsize: Use 0 for no swap (rely on zswap for memory compression)
    # maxvz: Omit to let Proxmox allocate remaining space for data volume (/var/lib/vz)
    #        This is where ISO images, CT templates, and backups are stored
    cat >>./answer.toml <<EOF
    lvm.swapsize = 0
EOF
  fi

  # Validate the generated file
  if ! validate_answer_toml "./answer.toml"; then
    log "ERROR: answer.toml validation failed"
    exit 1
  fi

  log "answer.toml created and validated:"
  cat answer.toml >>"$LOG_FILE"

  # Add subtasks for live log display
  if type live_log_subtask &>/dev/null 2>&1; then
    local total_disks=${#ZFS_POOL_DISKS[@]}
    [[ -n $BOOT_DISK ]] && ((total_disks++))
    live_log_subtask "Mapped $total_disks disk(s) to virtio"
    live_log_subtask "Generated answer.toml ($FILESYSTEM)"
  fi
}

# Creates autoinstall ISO from Proxmox ISO and answer.toml.
# Side effects: Creates pve-autoinstall.iso, removes pve.iso
make_autoinstall_iso() {
  log "Creating autoinstall ISO"
  log "Input: pve.iso exists: $(test -f pve.iso && echo 'yes' || echo 'no')"
  log "Input: answer.toml exists: $(test -f answer.toml && echo 'yes' || echo 'no')"
  log "Current directory: $(pwd)"
  log "Files in current directory:"
  ls -la >>"$LOG_FILE" 2>&1

  # Run ISO creation with full logging
  proxmox-auto-install-assistant prepare-iso pve.iso --fetch-from iso --answer-file answer.toml --output pve-autoinstall.iso >>"$LOG_FILE" 2>&1 &
  show_progress $! "Creating autoinstall ISO" "Autoinstall ISO created"
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: proxmox-auto-install-assistant exited with code $exit_code"
  fi

  # Verify ISO was created
  if [[ ! -f "./pve-autoinstall.iso" ]]; then
    log "ERROR: Autoinstall ISO not found after creation attempt"
    log "Files in current directory after attempt:"
    ls -la >>"$LOG_FILE" 2>&1
    exit 1
  fi

  log "Autoinstall ISO created successfully: $(stat -c%s pve-autoinstall.iso 2>/dev/null | awk '{printf "%.1fM", $1/1024/1024}')"

  # Add live log subtasks after completion
  if type live_log_subtask &>/dev/null 2>&1; then
    live_log_subtask "Packed ISO with xorriso"
  fi

  # Remove original ISO to save disk space (only autoinstall ISO is needed)
  log "Removing original ISO to save disk space"
  rm -f pve.iso
}
