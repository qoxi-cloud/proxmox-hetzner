# shellcheck shell=bash
# Proxmox ISO download and version management

# Cache for ISO list (populated by prefetch_proxmox_iso_info)
_ISO_LIST_CACHE=""

# Cache for SHA256SUMS content
_CHECKSUM_CACHE=""

# Prefetch ISO list and checksums to cache
prefetch_proxmox_iso_info() {
  _ISO_LIST_CACHE=$(curl -s "$PROXMOX_ISO_BASE_URL" 2>/dev/null | grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | sort -uV) || true
  _CHECKSUM_CACHE=$(curl -s "$PROXMOX_CHECKSUM_URL" 2>/dev/null) || true
}

# Get available Proxmox ISOs (v9+). $1=count (default 5) → stdout
get_available_proxmox_isos() {
  local count="${1:-5}"
  # Filter to versions 9+ (matches 9, 10, 11, etc.)
  printf '%s\n' "$_ISO_LIST_CACHE" | grep -E '^proxmox-ve_(9|[1-9][0-9]+)\.' | tail -n "$count" | tac
}

# Get full ISO URL. $1=filename → stdout
get_proxmox_iso_url() {
  local iso_filename="$1"
  printf '%s\n' "${PROXMOX_ISO_BASE_URL}${iso_filename}"
}

# Extract version from ISO filename. $1=filename → stdout
get_iso_version() {
  local iso_filename="$1"
  printf '%s\n' "$iso_filename" | sed -E 's/proxmox-ve_([0-9]+\.[0-9]+-[0-9]+)\.iso/\1/'
}

# Download Proxmox ISO with fallback (aria2c→curl→wget) and verify checksum
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
    expected_checksum=$(printf '%s\n' "$_CHECKSUM_CACHE" | grep "$ISO_FILENAME" | awk '{print $1}')
  fi
  log "Expected checksum: ${expected_checksum:-not available}"

  # Download with fallback chain: aria2c → curl → wget
  log "Downloading ISO: $ISO_FILENAME"
  local method_file
  method_file=$(mktemp)
  register_temp_file "$method_file"

  _download_iso_with_fallback "$PROXMOX_ISO_URL" "pve.iso" "$expected_checksum" "$method_file" &
  show_progress $! "Downloading $ISO_FILENAME" "$ISO_FILENAME downloaded"
  wait $!
  local exit_code=$?
  DOWNLOAD_METHOD=$(cat "$method_file" 2>/dev/null)
  rm -f "$method_file"

  if [[ $exit_code -ne 0 ]] || [[ ! -s "pve.iso" ]]; then
    log "ERROR: All download methods failed for Proxmox ISO"
    rm -f pve.iso
    exit 1
  fi

  log "Download successful via $DOWNLOAD_METHOD"

  local iso_size
  iso_size=$(stat -c%s pve.iso 2>/dev/null) || iso_size=0
  log "ISO file size: $(printf '%s\n' "$iso_size" | awk '{printf "%.1fG", $1/1024/1024/1024}')"

  # Verify checksum (if not already verified by aria2c)
  if [[ -n $expected_checksum ]]; then
    # Skip manual verification if aria2c already validated
    if [[ $DOWNLOAD_METHOD == "aria2c" ]]; then
      log "Checksum already verified by aria2c"
      # Add live log subtask for aria2c auto-verification
      if type live_log_subtask &>/dev/null 2>&1; then
        live_log_subtask "SHA256: OK (verified by aria2c)"
      fi
    else
      log "Verifying ISO checksum"
      local actual_checksum
      (actual_checksum=$(sha256sum pve.iso | awk '{print $1}') && printf '%s\n' "$actual_checksum" >/tmp/checksum_result) &
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
