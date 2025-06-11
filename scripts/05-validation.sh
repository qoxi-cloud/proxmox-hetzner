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
    # Password must contain only ASCII printable characters (no Cyrillic or other non-ASCII)
    # Allowed: Latin letters, digits, and special characters (ASCII 32-126)
    # Using LC_ALL=C ensures only ASCII characters match [:print:]
    LC_ALL=C bash -c '[[ "$1" =~ ^[[:print:]]+$ ]]' _ "$password"
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
prompt_password() {
    local prompt="$1"
    local var_name="$2"
    local password

    password=$(read_password "$prompt")
    while [[ -z "$password" ]] || ! validate_password "$password"; do
        if [[ -z "$password" ]]; then
            print_error "Password cannot be empty!"
        else
            print_error "Password contains invalid characters (Cyrillic or non-ASCII)."
            print_error "Only Latin letters, digits, and special characters are allowed."
        fi
        password=$(read_password "$prompt")
    done
    printf "\033[A\r${CLR_GREEN}✓${CLR_RESET} ${prompt}********\033[K\n"
    eval "$var_name=\"\$password\""
}
