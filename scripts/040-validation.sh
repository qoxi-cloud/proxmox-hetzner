# shellcheck shell=bash
# =============================================================================
# Input validation functions
# =============================================================================

# Validates hostname format (alphanumeric, hyphens, 1-63 chars).
# Parameters:
#   $1 - Hostname to validate
# Returns: 0 if valid, 1 otherwise
validate_hostname() {
  local hostname="$1"
  # Reject reserved hostname "localhost"
  [[ ${hostname,,} == "localhost" ]] && return 1
  # Hostname: alphanumeric and hyphens, 1-63 chars, cannot start/end with hyphen
  [[ $hostname =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

# Validates admin username format for Linux systems.
# Must be lowercase, start with letter, 1-32 chars.
# Blocks reserved system usernames.
# Parameters:
#   $1 - Username to validate
# Returns: 0 if valid, 1 otherwise
validate_admin_username() {
  local username="$1"

  # Must be lowercase alphanumeric, can contain underscore/hyphen, 1-32 chars
  # Must start with a letter
  [[ ! $username =~ ^[a-z][a-z0-9_-]{0,31}$ ]] && return 1

  # Block reserved system usernames
  case "$username" in
    root | nobody | daemon | bin | sys | sync | games | man | lp | mail | \
      news | uucp | proxy | www-data | backup | list | irc | gnats | \
      sshd | systemd-network | systemd-resolve | messagebus | \
      polkitd | postfix | syslog | _apt | tss | uuidd | avahi | colord | \
      cups-pk-helper | dnsmasq | geoclue | hplip | kernoops | lightdm | \
      nm-openconnect | nm-openvpn | pulse | rtkit | saned | speech-dispatcher | \
      whoopsie | admin | administrator | operator | guest)
      return 1
      ;;
  esac

  return 0
}

# Validates fully qualified domain name format.
# Parameters:
#   $1 - FQDN to validate
# Returns: 0 if valid, 1 otherwise
validate_fqdn() {
  local fqdn="$1"
  # FQDN: valid hostname labels separated by dots
  [[ $fqdn =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

# Validates email address format (basic check).
# Parameters:
#   $1 - Email address to validate
# Returns: 0 if valid, 1 otherwise
validate_email() {
  local email="$1"
  # Basic email validation
  [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

# Checks if string contains only ASCII printable characters.
# Parameters:
#   $1 - String to check
# Returns: 0 if all ASCII printable, 1 otherwise
is_ascii_printable() {
  LC_ALL=C bash -c '[[ "$1" =~ ^[[:print:]]+$ ]]' _ "$1"
}

# Returns descriptive error message for invalid password.
# Parameters:
#   $1 - Password to check
# Returns: Error message via stdout, empty if valid
get_password_error() {
  local password="$1"
  if [[ -z $password ]]; then
    printf '%s\n' "Password cannot be empty!"
  elif [[ ${#password} -lt 8 ]]; then
    printf '%s\n' "Password must be at least 8 characters long."
  elif ! is_ascii_printable "$password"; then
    printf '%s\n' "Password contains invalid characters (Cyrillic or non-ASCII). Only Latin letters, digits, and special characters are allowed."
  fi
}

# Validates subnet in CIDR notation (e.g., 10.0.0.0/24).
# Parameters:
#   $1 - Subnet to validate
# Returns: 0 if valid, 1 otherwise
validate_subnet() {
  local subnet="$1"
  # Validate CIDR notation (e.g., 10.0.0.0/24)
  if [[ ! $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]; then
    return 1
  fi
  # Validate each octet is 0-255 using parameter expansion
  local ip="${subnet%/*}"
  local octet1 octet2 octet3 octet4 temp
  octet1="${ip%%.*}"
  temp="${ip#*.}"
  octet2="${temp%%.*}"
  temp="${temp#*.}"
  octet3="${temp%%.*}"
  octet4="${temp#*.}"

  [[ $octet1 -le 255 && $octet2 -le 255 && $octet3 -le 255 && $octet4 -le 255 ]]
}

# =============================================================================
# IPv6 validation functions
# =============================================================================

# Validates IPv6 address (full, compressed, or mixed format).
# Parameters:
#   $1 - IPv6 address to validate (without prefix)
# Returns: 0 if valid, 1 otherwise
validate_ipv6() {
  local ipv6="$1"

  # Empty check
  [[ -z $ipv6 ]] && return 1

  # Remove zone ID if present (e.g., %eth0)
  ipv6="${ipv6%%\%*}"

  # Check for valid characters
  [[ ! $ipv6 =~ ^[0-9a-fA-F:]+$ ]] && return 1

  # Cannot start or end with single colon (but :: is valid)
  [[ $ipv6 =~ ^:[^:] ]] && return 1
  [[ $ipv6 =~ [^:]:$ ]] && return 1

  # Reject three or more consecutive colons (invalid)
  [[ $ipv6 =~ ::: ]] && return 1

  # Cannot have more than one :: sequence
  local double_colon_count
  double_colon_count=$(grep -o '::' <<<"$ipv6" | wc -l)
  [[ $double_colon_count -gt 1 ]] && return 1

  # Count groups (split by :, accounting for ::)
  local groups
  if [[ $ipv6 == *"::"* ]]; then
    # With :: compression, count actual groups
    local left="${ipv6%%::*}"
    local right="${ipv6##*::}"
    local left_count=0 right_count=0
    [[ -n $left ]] && left_count=$(tr ':' '\n' <<<"$left" | grep -c .)
    [[ -n $right ]] && right_count=$(tr ':' '\n' <<<"$right" | grep -c .)
    groups=$((left_count + right_count))
    # Total groups must be less than 8 (:: fills the rest)
    [[ $groups -ge 8 ]] && return 1
  else
    # Without compression, must have exactly 8 groups
    groups=$(tr ':' '\n' <<<"$ipv6" | grep -c .)
    [[ $groups -ne 8 ]] && return 1
  fi

  # Validate each group (1-4 hex digits)
  local group
  for group in $(tr ':' ' ' <<<"$ipv6"); do
    [[ -z $group ]] && continue
    [[ ${#group} -gt 4 ]] && return 1
    [[ ! $group =~ ^[0-9a-fA-F]+$ ]] && return 1
  done

  return 0
}

# Validates IPv6 address with CIDR prefix (e.g., 2001:db8::1/64).
# Parameters:
#   $1 - IPv6 with CIDR notation
# Returns: 0 if valid, 1 otherwise
validate_ipv6_cidr() {
  local ipv6_cidr="$1"

  # Check for CIDR format
  [[ ! $ipv6_cidr =~ ^.+/[0-9]+$ ]] && return 1

  local ipv6="${ipv6_cidr%/*}"
  local prefix="${ipv6_cidr##*/}"

  # Validate prefix length (0-128)
  [[ ! $prefix =~ ^[0-9]+$ ]] && return 1
  [[ $prefix -lt 0 || $prefix -gt 128 ]] && return 1

  # Validate IPv6 address
  validate_ipv6 "$ipv6"
}

# Validates IPv6 gateway address (accepts empty, "auto", or valid IPv6).
# Parameters:
#   $1 - Gateway address to validate
# Returns: 0 if valid, 1 otherwise
validate_ipv6_gateway() {
  local gateway="$1"

  # Empty is valid (no IPv6 gateway)
  [[ -z $gateway ]] && return 0

  # Special value "auto" means use link-local
  [[ $gateway == "auto" ]] && return 0

  # Validate as IPv6 address
  validate_ipv6 "$gateway"
}

# =============================================================================
# DNS validation
# =============================================================================

# Validates that FQDN resolves to expected IP using public DNS servers.
# Parameters:
#   $1 - FQDN to resolve
#   $2 - Expected IP address
# Returns: 0 if matches, 1 if no resolution, 2 if wrong IP
# Side effects: Sets DNS_RESOLVED_IP global
validate_dns_resolution() {
  local fqdn="$1"
  local expected_ip="$2"
  local resolved_ip=""
  local dns_timeout="${DNS_LOOKUP_TIMEOUT:-5}" # Default 5 second timeout
  local retry_delay="${DNS_RETRY_DELAY:-10}"   # Default 10 second delay between retries
  local max_attempts=3

  # Determine which DNS tool to use (check once, not in loop)
  local dns_tool=""
  if command -v dig &>/dev/null; then
    dns_tool="dig"
  elif command -v host &>/dev/null; then
    dns_tool="host"
  elif command -v nslookup &>/dev/null; then
    dns_tool="nslookup"
  fi

  # If no DNS tool available, log warning and return no resolution
  if [[ -z $dns_tool ]]; then
    log "WARNING: No DNS lookup tool available (dig, host, or nslookup)"
    DNS_RESOLVED_IP=""
    return 1
  fi

  # Retry loop for DNS resolution
  for attempt in $(seq 1 "$max_attempts"); do
    resolved_ip=""

    # Try each public DNS server until we get a result (use global DNS_SERVERS)
    for dns_server in "${DNS_SERVERS[@]}"; do
      case "$dns_tool" in
        dig)
          # dig supports +time for timeout
          resolved_ip=$(timeout "$dns_timeout" dig +short +time=3 +tries=1 A "$fqdn" "@${dns_server}" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
          ;;
        host)
          # host supports -W for timeout
          resolved_ip=$(timeout "$dns_timeout" host -W 3 -t A "$fqdn" "$dns_server" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
          ;;
        nslookup)
          # nslookup doesn't have timeout option, use timeout command
          # Filter out server's Address line (has #port) to get resolved IP
          resolved_ip=$(timeout "$dns_timeout" nslookup -timeout=3 "$fqdn" "$dns_server" 2>/dev/null | awk '/^Address:/ && !/#/ {print $2; exit}')
          ;;
      esac

      if [[ -n $resolved_ip ]]; then
        break
      fi
    done

    # Fallback to system resolver if public DNS fails
    if [[ -z $resolved_ip ]]; then
      case "$dns_tool" in
        dig)
          resolved_ip=$(timeout "$dns_timeout" dig +short +time=3 +tries=1 A "$fqdn" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
          ;;
        *)
          if command -v getent &>/dev/null; then
            resolved_ip=$(timeout "$dns_timeout" getent ahosts "$fqdn" 2>/dev/null | grep STREAM | head -1 | awk '{print $1}')
          fi
          ;;
      esac
    fi

    # If we got a result, process it
    if [[ -n $resolved_ip ]]; then
      DNS_RESOLVED_IP="$resolved_ip"
      if [[ $resolved_ip == "$expected_ip" ]]; then
        return 0 # Match
      else
        return 2 # Wrong IP
      fi
    fi

    # No resolution on this attempt
    if [[ $attempt -lt $max_attempts ]]; then
      log "WARN: DNS lookup for $fqdn failed (attempt $attempt/$max_attempts), retrying in ${retry_delay}s..."
      sleep "$retry_delay"
    fi
  done

  # All attempts failed
  log "ERROR: Failed to resolve $fqdn after $max_attempts attempts"
  DNS_RESOLVED_IP=""
  return 1 # No resolution
}

# Validates SSH public key format and security requirements.
# Ensures key is proper OpenSSH format and meets security standards.
# Uses ssh-keygen for validation and checks key strength.
# Parameters:
#   $1 - SSH public key to validate
# Returns: 0 if valid, 1 otherwise
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

# =============================================================================
# Disk space validation
# =============================================================================

# Validates available disk space meets minimum requirements.
# Parameters:
#   $1 - Path to check (default: /root)
#   $2 - Minimum required space in MB (default: MIN_DISK_SPACE_MB)
# Returns: 0 if sufficient, 1 otherwise
# Side effects: Sets DISK_SPACE_MB global with available space
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

# Validates Tailscale authentication key format.
# Format: tskey-auth-<id>-<secret> or tskey-client-<id>-<secret>
# Example: tskey-auth-kpaPEJ2wwN11CNTRL-UsWiT9N81EjmVTyBKVj5Ej23Pwkp2KUN
# Parameters:
#   $1 - Tailscale auth key to validate
# Returns: 0 if valid, 1 otherwise
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
