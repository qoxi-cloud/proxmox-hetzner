# shellcheck shell=bash
# =============================================================================
# Input validation functions
# =============================================================================

validate_hostname() {
    local hostname="$1"
    # Hostname: alphanumeric and hyphens, 1-63 chars, cannot start/end with hyphen
    [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

validate_fqdn() {
    local fqdn="$1"
    # FQDN: valid hostname labels separated by dots
    [[ "$fqdn" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

validate_email() {
    local email="$1"
    # Basic email validation
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_password() {
    local password="$1"
    # Password must be at least 8 characters (Proxmox requirement)
    [[ ${#password} -ge 8 ]] && is_ascii_printable "$password"
}

# Check if password contains only ASCII printable characters
# Usage: is_ascii_printable PASSWORD
# Returns: 0 if valid, 1 if contains non-ASCII
is_ascii_printable() {
    LC_ALL=C bash -c '[[ "$1" =~ ^[[:print:]]+$ ]]' _ "$1"
}

# Get password validation error message
# Usage: get_password_error PASSWORD
# Returns: error message string, empty if password is valid
get_password_error() {
    local password="$1"
    if [[ -z "$password" ]]; then
        echo "Password cannot be empty!"
    elif [[ ${#password} -lt 8 ]]; then
        echo "Password must be at least 8 characters long."
    elif ! is_ascii_printable "$password"; then
        echo "Password contains invalid characters (Cyrillic or non-ASCII). Only Latin letters, digits, and special characters are allowed."
    fi
}

# Validate password and print error if invalid
# Usage: validate_password_with_error PASSWORD
# Returns: 0 if valid, 1 if invalid (with error printed)
validate_password_with_error() {
    local password="$1"
    local error
    error=$(get_password_error "$password")
    if [[ -n "$error" ]]; then
        print_error "$error"
        return 1
    fi
    return 0
}

validate_subnet() {
    local subnet="$1"
    # Validate CIDR notation (e.g., 10.0.0.0/24)
    if [[ ! "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]; then
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

    [[ "$octet1" -le 255 && "$octet2" -le 255 && "$octet3" -le 255 && "$octet4" -le 255 ]]
}

validate_timezone() {
    local tz="$1"
    # Check if timezone file exists (preferred validation)
    if [[ -f "/usr/share/zoneinfo/$tz" ]]; then
        return 0
    fi
    # Fallback: In Rescue System, zoneinfo may not be available
    # Validate format (Region/City or Region/Subregion/City)
    if [[ "$tz" =~ ^[A-Za-z_]+/[A-Za-z_]+(/[A-Za-z_]+)?$ ]]; then
        print_warning "Cannot verify timezone in Rescue System, format looks valid."
        return 0
    fi
    return 1
}

# =============================================================================
# Input prompt helpers with validation
# =============================================================================

# Prompt for input with validation, showing success checkmark when valid
# Usage: prompt_with_validation "prompt" "default" "validator" "error_msg" "var_name"
prompt_with_validation() {
    local prompt="$1"
    local default="$2"
    local validator="$3"
    local error_msg="$4"
    local var_name="$5"

    local result
    while true; do
        read -e -p "$prompt" -i "$default" result
        if $validator "$result"; then
            printf "\033[A\r${CLR_GREEN}✓${CLR_RESET} ${prompt}${result}\033[K\n"
            eval "$var_name=\"\$result\""
            return 0
        fi
        print_error "$error_msg"
    done
}

# Prompt for password with validation
# Usage: prompt_password "prompt" "var_name"
# Validate that FQDN resolves to expected IP using public DNS servers
# Usage: validate_dns_resolution "fqdn" "expected_ip"
# Returns: 0 if matches, 1 if no resolution, 2 if wrong IP
# Sets: DNS_RESOLVED_IP with the resolved IP (empty if no resolution)
validate_dns_resolution() {
    local fqdn="$1"
    local expected_ip="$2"
    local resolved_ip=""

    # Determine which DNS tool to use (check once, not in loop)
    local dns_tool=""
    if command -v dig &>/dev/null; then
        dns_tool="dig"
    elif command -v host &>/dev/null; then
        dns_tool="host"
    elif command -v nslookup &>/dev/null; then
        dns_tool="nslookup"
    fi

    # Try each public DNS server until we get a result (use global DNS_SERVERS)
    for dns_server in "${DNS_SERVERS[@]}"; do
        case "$dns_tool" in
            dig)
                resolved_ip=$(dig +short A "$fqdn" "@${dns_server}" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
                ;;
            host)
                resolved_ip=$(host -t A "$fqdn" "$dns_server" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
                ;;
            nslookup)
                resolved_ip=$(nslookup "$fqdn" "$dns_server" 2>/dev/null | awk '/^Address: / {print $2}' | head -1)
                ;;
        esac

        if [[ -n "$resolved_ip" ]]; then
            break
        fi
    done

    # Fallback to system resolver if public DNS fails
    if [[ -z "$resolved_ip" ]]; then
        case "$dns_tool" in
            dig)
                resolved_ip=$(dig +short A "$fqdn" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
                ;;
            *)
                if command -v getent &>/dev/null; then
                    resolved_ip=$(getent ahosts "$fqdn" 2>/dev/null | grep STREAM | head -1 | awk '{print $1}')
                fi
                ;;
        esac
    fi

    if [[ -z "$resolved_ip" ]]; then
        DNS_RESOLVED_IP=""
        return 1  # No resolution
    fi

    DNS_RESOLVED_IP="$resolved_ip"
    if [[ "$resolved_ip" == "$expected_ip" ]]; then
        return 0  # Match
    else
        return 2  # Wrong IP
    fi
}

prompt_password() {
    local prompt="$1"
    local var_name="$2"
    local password

    password=$(read_password "$prompt")
    while [[ -z "$password" ]] || ! validate_password "$password"; do
        if [[ -z "$password" ]]; then
            print_error "Password cannot be empty!"
        elif [[ ${#password} -lt 8 ]]; then
            print_error "Password must be at least 8 characters long."
        else
            print_error "Password contains invalid characters (Cyrillic or non-ASCII)."
            print_error "Only Latin letters, digits, and special characters are allowed."
        fi
        password=$(read_password "$prompt")
    done
    printf "\033[A\r${CLR_GREEN}✓${CLR_RESET} ${prompt}********\033[K\n"
    eval "$var_name=\"\$password\""
}
