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
  # Hostname: alphanumeric and hyphens, 1-63 chars, cannot start/end with hyphen
  [[ $hostname =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
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

# Validates password meets minimum requirements (8+ chars, ASCII).
# Parameters:
#   $1 - Password to validate
# Returns: 0 if valid, 1 otherwise
validate_password() {
  local password="$1"
  # Password must be at least 8 characters (Proxmox requirement)
  [[ ${#password} -ge 8 ]] && is_ascii_printable "$password"
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
    echo "Password cannot be empty!"
  elif [[ ${#password} -lt 8 ]]; then
    echo "Password must be at least 8 characters long."
  elif ! is_ascii_printable "$password"; then
    echo "Password contains invalid characters (Cyrillic or non-ASCII). Only Latin letters, digits, and special characters are allowed."
  fi
}

# Validates password and prints error if invalid.
# Parameters:
#   $1 - Password to validate
# Returns: 0 if valid, 1 if invalid (with error printed)
validate_password_with_error() {
  local password="$1"
  local error
  error=$(get_password_error "$password")
  if [[ -n $error ]]; then
    print_error "$error"
    return 1
  fi
  return 0
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

# Validates IPv6 prefix length (48-128).
# Parameters:
#   $1 - Prefix length to validate
# Returns: 0 if valid, 1 otherwise
validate_ipv6_prefix_length() {
  local prefix="$1"

  [[ ! $prefix =~ ^[0-9]+$ ]] && return 1
  # Typical values: 48 (site), 56 (organization), 64 (subnet), 80 (small subnet)
  [[ $prefix -lt 48 || $prefix -gt 128 ]] && return 1

  return 0
}

# Checks if IPv6 address is link-local (fe80::/10).
# Parameters:
#   $1 - IPv6 address to check
# Returns: 0 if link-local, 1 otherwise
is_ipv6_link_local() {
  local ipv6="$1"
  [[ $ipv6 =~ ^[fF][eE]8[0-9a-fA-F]: ]] || [[ $ipv6 =~ ^[fF][eE][89aAbB][0-9a-fA-F]: ]]
}

# Checks if IPv6 address is ULA (fc00::/7).
# Parameters:
#   $1 - IPv6 address to check
# Returns: 0 if ULA, 1 otherwise
is_ipv6_ula() {
  local ipv6="$1"
  [[ $ipv6 =~ ^[fF][cCdD] ]]
}

# Checks if IPv6 address is global unicast (2000::/3).
# Parameters:
#   $1 - IPv6 address to check
# Returns: 0 if global unicast, 1 otherwise
is_ipv6_global() {
  local ipv6="$1"
  [[ $ipv6 =~ ^[23] ]]
}

# Validates timezone string format and existence.
# Parameters:
#   $1 - Timezone to validate (e.g., Europe/London)
# Returns: 0 if valid, 1 otherwise
validate_timezone() {
  local tz="$1"
  # Check if timezone file exists (preferred validation)
  if [[ -f "/usr/share/zoneinfo/$tz" ]]; then
    return 0
  fi
  # Fallback: In Rescue System, zoneinfo may not be available
  # Validate format (Region/City or Region/Subregion/City)
  if [[ $tz =~ ^[A-Za-z_]+/[A-Za-z_]+(/[A-Za-z_]+)?$ ]]; then
    print_warning "Cannot verify timezone in Rescue System, format looks valid."
    return 0
  fi
  return 1
}

# =============================================================================
# Input prompt helpers with validation
# =============================================================================

# Prompts for input with validation, showing success checkmark when valid.
# Parameters:
#   $1 - Prompt text
#   $2 - Default value
#   $3 - Validator function name
#   $4 - Error message for invalid input
#   $5 - Variable name to store result
#   $6 - Optional confirmation label
# Side effects: Sets variable named by $5
prompt_with_validation() {
  local prompt="$1"
  local default="$2"
  local validator="$3"
  local error_msg="$4"
  local var_name="$5"
  local confirm_label="${6:-$prompt}"

  local result
  while true; do
    read -r -e -p "$prompt" -i "$default" result
    if $validator "$result"; then
      printf "\033[A\r%s✓%s %s%s%s%s\033[K\n" "${CLR_CYAN}" "${CLR_RESET}" "$confirm_label" "${CLR_CYAN}" "$result" "${CLR_RESET}"
      # Use printf -v for safe variable assignment (avoids eval)
      printf -v "$var_name" '%s' "$result"
      return 0
    fi
    print_error "$error_msg"
  done
}

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
        resolved_ip=$(timeout "$dns_timeout" nslookup -timeout=3 "$fqdn" "$dns_server" 2>/dev/null | awk '/^Address: / {print $2}' | head -1)
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

  if [[ -z $resolved_ip ]]; then
    DNS_RESOLVED_IP=""
    return 1 # No resolution
  fi

  DNS_RESOLVED_IP="$resolved_ip"
  if [[ $resolved_ip == "$expected_ip" ]]; then
    return 0 # Match
  else
    return 2 # Wrong IP
  fi
}

# Prompts for password with validation and masked display.
# Parameters:
#   $1 - Prompt text
#   $2 - Variable name to store result
# Side effects: Sets variable named by $2
prompt_password() {
  local prompt="$1"
  local var_name="$2"
  local password
  local error

  password=$(read_password "$prompt")
  error=$(get_password_error "$password")
  while [[ -n $error ]]; do
    print_error "$error"
    password=$(read_password "$prompt")
    error=$(get_password_error "$password")
  done
  printf "\033[A\r%s✓%s %s********\033[K\n" "${CLR_CYAN}" "${CLR_RESET}" "$prompt"
  # Use printf -v for safe variable assignment (avoids eval)
  printf -v "$var_name" '%s' "$password"
}
