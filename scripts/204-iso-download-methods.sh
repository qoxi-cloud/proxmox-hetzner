# shellcheck shell=bash
# Proxmox ISO download methods
# Fallback chain: aria2c → curl → wget

# Download ISO via curl. $1=url, $2=output
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

# Download ISO via wget. $1=url, $2=output
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

# Download ISO via aria2c. $1=url, $2=output, $3=checksum (optional)
_download_iso_aria2c() {
  local url="$1"
  local output="$2"
  local checksum="$3"
  local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"

  log "Downloading with aria2c (4 connections, with retries)"
  local aria2_args=(
    -x 4  # 4 connections (optimal for Proxmox server)
    -s 4  # 4 splits
    -k 4M # 4MB minimum split size
    --max-tries="$max_retries"
    --retry-wait=5
    --timeout=60
    --connect-timeout=30
    --max-connection-per-server=4
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

# Download ISO with fallback (aria2c→curl→wget). $1=url, $2=output, $3=checksum, $4=method_file
_download_iso_with_fallback() {
  local url="$1"
  local output="$2"
  local checksum="$3"
  local method_file="${4:-}"

  # Try aria2c first (fastest - uses parallel connections)
  if command -v aria2c &>/dev/null; then
    log "Trying aria2c (parallel download)..."
    if _download_iso_aria2c "$url" "$output" "$checksum" && [[ -s "$output" ]]; then
      [[ -n $method_file ]] && printf '%s\n' "aria2c" >"$method_file"
      return 0
    fi
    log "aria2c failed, trying fallback..."
    rm -f "$output" 2>/dev/null
  fi

  # Fallback to curl
  log "Trying curl..."
  if _download_iso_curl "$url" "$output" && [[ -s "$output" ]]; then
    [[ -n $method_file ]] && printf '%s\n' "curl" >"$method_file"
    return 0
  fi
  log "curl failed, trying fallback..."
  rm -f "$output" 2>/dev/null

  # Fallback to wget
  if command -v wget &>/dev/null; then
    log "Trying wget..."
    if _download_iso_wget "$url" "$output" && [[ -s "$output" ]]; then
      [[ -n $method_file ]] && printf '%s\n' "wget" >"$method_file"
      return 0
    fi
    rm -f "$output" 2>/dev/null
  fi

  log "All download methods failed"
  return 1
}
