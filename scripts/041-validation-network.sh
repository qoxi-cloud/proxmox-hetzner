# shellcheck shell=bash
# Network validation functions (subnet, IPv6)

# Validate subnet CIDR. $1=subnet
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

  # Use 10# prefix to force base-10 interpretation (prevents 08/09 octal errors)
  # shellcheck disable=SC2309 # arithmetic comparison is intentional
  [[ 10#$octet1 -le 255 && 10#$octet2 -le 255 && 10#$octet3 -le 255 && 10#$octet4 -le 255 ]]
}

# IPv6 validation functions

# Validate IPv6 address. $1=ipv6
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

# Validate IPv6/CIDR. $1=ipv6_cidr
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

# Validate IPv6 gateway (empty, "auto", or IPv6). $1=gateway
validate_ipv6_gateway() {
  local gateway="$1"

  # Empty is valid (no IPv6 gateway)
  [[ -z $gateway ]] && return 0

  # Special value "auto" means use link-local
  [[ $gateway == "auto" ]] && return 0

  # Validate as IPv6 address
  validate_ipv6 "$gateway"
}
