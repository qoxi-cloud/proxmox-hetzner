# shellcheck shell=bash
# Security validation functions (SSH key, Tailscale, disk space)

# Validate SSH public key format and security. $1=key
validate_ssh_key_secure() {
  local key="$1"

  # Validate it's a proper OpenSSH public key
  if ! echo "$key" | ssh-keygen -l -f - >/dev/null 2>&1; then
    log "ERROR: Invalid SSH public key format"
    return 1
  fi

  # Check key type is secure (no DSA/RSA <2048)
  local key_type
  key_type=$(echo "$key" | awk '{print $1}')

  case "$key_type" in
    ssh-ed25519)
      log "INFO: SSH key validated (ED25519)"
      return 0
      ;;
    ecdsa-*)
      # ECDSA keys report curve size (256, 384, 521), not RSA-equivalent bits
      # ECDSA-256 is equivalent to ~3072-bit RSA, so all standard curves are secure
      local bits
      bits=$(echo "$key" | ssh-keygen -l -f - 2>/dev/null | awk '{print $1}')
      if [[ $bits -ge 256 ]]; then
        log "INFO: SSH key validated ($key_type, $bits bits)"
        return 0
      fi
      log "ERROR: ECDSA key curve too small (current: $bits)"
      return 1
      ;;
    ssh-rsa)
      local bits
      bits=$(echo "$key" | ssh-keygen -l -f - 2>/dev/null | awk '{print $1}')
      if [[ $bits -ge 2048 ]]; then
        log "INFO: SSH key validated ($key_type, $bits bits)"
        return 0
      fi
      log "ERROR: RSA key must be >= 2048 bits (current: $bits)"
      return 1
      ;;
    *)
      log "ERROR: Unsupported key type: $key_type"
      return 1
      ;;
  esac
}

# Disk space validation

# Validate disk space. $1=path, $2=min_mb. Sets DISK_SPACE_MB global.
validate_disk_space() {
  local path="${1:-/root}"
  local min_required_mb="${2:-${MIN_DISK_SPACE_MB}}"
  local available_mb

  # Get available space in MB
  available_mb=$(df -m "$path" 2>/dev/null | awk 'NR==2 {print $4}')

  if [[ -z $available_mb ]]; then
    log "ERROR: Could not determine disk space for $path"
    return 1
  fi

  DISK_SPACE_MB=$available_mb

  if [[ $available_mb -lt $min_required_mb ]]; then
    log "ERROR: Insufficient disk space: ${available_mb}MB available, ${min_required_mb}MB required"
    return 1
  fi

  log "INFO: Disk space OK: ${available_mb}MB available (${min_required_mb}MB required)"
  return 0
}

# Validate Tailscale auth key format. $1=key
validate_tailscale_key() {
  local key="$1"

  [[ -z $key ]] && return 1

  # Must start with tskey-auth- or tskey-client-
  # Followed by alphanumeric ID, dash, and alphanumeric secret
  if [[ $key =~ ^tskey-(auth|client)-[a-zA-Z0-9]+-[a-zA-Z0-9]+$ ]]; then
    return 0
  fi

  return 1
}
