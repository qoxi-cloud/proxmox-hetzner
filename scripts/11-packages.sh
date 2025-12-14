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

# Downloads Proxmox ISO with fallback chain and checksum verification.
# Requires PROXMOX_ISO_VERSION to be set (user selects version in wizard).
# Tries: aria2c → curl → wget
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

  # Download with fallback chain: aria2c (conservative) -> curl -> wget
  log "Downloading ISO: $ISO_FILENAME"
  local download_success=false
  local download_method=""

  # Try aria2c first with conservative settings (2 connections instead of 8)
  local exit_code
  if command -v aria2c &>/dev/null; then
    log "Attempting download with aria2c (conservative mode)"
    _download_iso_aria2c "$PROXMOX_ISO_URL" "pve.iso" "$expected_checksum" &
    show_progress $! "Downloading $ISO_FILENAME (aria2c)" "$ISO_FILENAME downloaded"
    wait $!
    exit_code=$?
    if [[ $exit_code -eq 0 ]] && [[ -s "pve.iso" ]]; then
      download_success=true
      download_method="aria2c"
      log "aria2c download successful"
    else
      log "aria2c failed (exit code: $exit_code), trying curl fallback"
      rm -f pve.iso
    fi
  fi

  # Fallback to curl (most stable, single connection)
  if [[ $download_success != "true" ]]; then
    log "Attempting download with curl"
    _download_iso_curl "$PROXMOX_ISO_URL" "pve.iso" &
    show_progress $! "Downloading $ISO_FILENAME (curl)" "$ISO_FILENAME downloaded"
    wait $!
    exit_code=$?
    if [[ $exit_code -eq 0 ]] && [[ -s "pve.iso" ]]; then
      download_success=true
      download_method="curl"
      log "curl download successful"
    else
      log "curl failed (exit code: $exit_code), trying wget fallback"
      rm -f pve.iso
    fi
  fi

  # Final fallback to wget
  if [[ $download_success != "true" ]] && command -v wget &>/dev/null; then
    log "Attempting download with wget"
    _download_iso_wget "$PROXMOX_ISO_URL" "pve.iso" &
    show_progress $! "Downloading $ISO_FILENAME (wget)" "$ISO_FILENAME downloaded"
    wait $!
    exit_code=$?
    if [[ $exit_code -eq 0 ]] && [[ -s "pve.iso" ]]; then
      download_success=true
      download_method="wget"
      log "wget download successful"
    else
      rm -f pve.iso
    fi
  fi

  if [[ $download_success != "true" ]]; then
    log "ERROR: All download methods failed for Proxmox ISO"
    rm -f pve.iso
    exit 1
  fi

  local iso_size
  iso_size=$(stat -c%s pve.iso 2>/dev/null) || iso_size=0
  log "ISO file size: $(echo "$iso_size" | awk '{printf "%.1fG", $1/1024/1024/1024}')"

  # Verify checksum (if not already verified by aria2c)
  if [[ -n $expected_checksum ]]; then
    # Skip manual verification if aria2c already validated
    if [[ $download_method == "aria2c" ]]; then
      log "Checksum already verified by aria2c"
      # Add live log for aria2c auto-verification
      if type live_log_subtask &>/dev/null 2>&1; then
        live_log_subtask "SHA256: OK (verified by aria2c)"
      fi
    else
      log "Verifying ISO checksum"
      sha256sum pve.iso | awk '{print $1}' >/dev/null &
      if type show_progress &>/dev/null 2>&1; then
        show_progress $! "Verifying checksum" "Checksum verified"
      else
        wait $!
      fi
      local actual_checksum
      actual_checksum=$(sha256sum pve.iso | awk '{print $1}')
      if [[ $actual_checksum != "$expected_checksum" ]]; then
        log "ERROR: Checksum mismatch! Expected: $expected_checksum, Got: $actual_checksum"
        rm -f pve.iso
        exit 1
      fi
      log "Checksum verification passed"
      # Add live log for successful verification
      if type live_log_subtask &>/dev/null 2>&1; then
        live_log_subtask "SHA256: OK"
      fi
    fi
  else
    log "WARNING: Could not find checksum for $ISO_FILENAME"
    print_warning "Could not find checksum for $ISO_FILENAME"
  fi
}

# Validates answer.toml has all required fields.
# Parameters:
#   $1 - Path to answer.toml file
# Returns: 0 if valid, 1 if missing required fields
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

# Creates answer.toml for Proxmox autoinstall.
# Downloads template and applies configuration variables.
# Side effects: Creates answer.toml file, exits on failure
make_answer_toml() {
  log "Creating answer.toml for autoinstall"
  log "ZFS_RAID=$ZFS_RAID, DRIVE_COUNT=$DRIVE_COUNT"

  # Build disk_list based on ZFS_RAID mode (using vda/vdb for QEMU virtio)
  case "$ZFS_RAID" in
    single)
      DISK_LIST='["/dev/vda"]'
      ;;
    raid0 | raid1)
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
  if [[ $DRIVE_COUNT -ge 2 && -n $ZFS_RAID && $ZFS_RAID != "single" ]]; then
    zfs_raid_value="$ZFS_RAID"
  else
    # Single disk or single mode selected - must use raid0 (single disk stripe)
    zfs_raid_value="raid0"
  fi
  log "Using ZFS raid: $zfs_raid_value"

  # Download and process answer.toml template
  if ! download_template "./answer.toml" "answer.toml"; then
    log "ERROR: Failed to download answer.toml template"
    exit 1
  fi

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
  cat answer.toml >>"$LOG_FILE"
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
  wait $!
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
    live_log_subtask "Creating answer.toml"
    live_log_subtask "Packing ISO with xorriso"
  fi

  # Remove original ISO to save disk space (only autoinstall ISO is needed)
  log "Removing original ISO to save disk space"
  rm -f pve.iso
}
