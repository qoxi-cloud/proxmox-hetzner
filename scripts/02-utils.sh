# shellcheck shell=bash
# =============================================================================
# General utilities
# =============================================================================

# Download files with retry
download_file() {
    local output_file="$1"
    local url="$2"
    local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"
    local retry_delay="${DOWNLOAD_RETRY_DELAY:-2}"
    local retry_count=0

    while [ "$retry_count" -lt "$max_retries" ]; do
        if wget -q -O "$output_file" "$url"; then
            if [ -s "$output_file" ]; then
                return 0
            else
                print_error "Downloaded file is empty: $output_file"
            fi
        else
            print_warning "Download failed (attempt $((retry_count + 1))/$max_retries): $url"
        fi
        retry_count=$((retry_count + 1))
        [ "$retry_count" -lt "$max_retries" ] && sleep "$retry_delay"
    done

    log "ERROR: Failed to download $url after $max_retries attempts"
    exit 1
}

# =============================================================================
# Template processing utilities
# =============================================================================

# Apply template variable substitutions to a file
# Usage: apply_template_vars FILE [VAR1=VALUE1] [VAR2=VALUE2] ...
apply_template_vars() {
    local file="$1"
    shift

    if [[ ! -f "$file" ]]; then
        log "ERROR: Template file not found: $file"
        return 1
    fi

    # Build sed command with all substitutions
    local sed_args=()

    if [[ $# -gt 0 ]]; then
        # Use provided VAR=VALUE pairs
        for pair in "$@"; do
            local var="${pair%%=*}"
            local value="${pair#*=}"
            # Escape special characters in value for sed
            value="${value//\\/\\\\}"
            value="${value//&/\\&}"
            value="${value//|/\\|}"
            sed_args+=(-e "s|{{${var}}}|${value}|g")
        done
    fi

    if [[ ${#sed_args[@]} -gt 0 ]]; then
        sed -i "${sed_args[@]}" "$file"
    fi
}

# Apply common template variables to a file using global variables
# Usage: apply_common_template_vars FILE
apply_common_template_vars() {
    local file="$1"

    apply_template_vars "$file" \
        "MAIN_IPV4=${MAIN_IPV4:-}" \
        "MAIN_IPV4_GW=${MAIN_IPV4_GW:-}" \
        "MAIN_IPV6=${MAIN_IPV6:-}" \
        "FIRST_IPV6_CIDR=${FIRST_IPV6_CIDR:-}" \
        "FQDN=${FQDN:-}" \
        "HOSTNAME=${PVE_HOSTNAME:-}" \
        "INTERFACE_NAME=${INTERFACE_NAME:-}" \
        "PRIVATE_IP_CIDR=${PRIVATE_IP_CIDR:-}" \
        "PRIVATE_SUBNET=${PRIVATE_SUBNET:-}" \
        "DNS_PRIMARY=${DNS_PRIMARY:-1.1.1.1}" \
        "DNS_SECONDARY=${DNS_SECONDARY:-1.0.0.1}" \
        "DNS_TERTIARY=${DNS_TERTIARY:-8.8.8.8}" \
        "DNS_QUATERNARY=${DNS_QUATERNARY:-8.8.4.4}"
}

# Download template from GitHub repository
# Usage: download_template LOCAL_PATH [REMOTE_FILENAME]
# REMOTE_FILENAME defaults to basename of LOCAL_PATH
download_template() {
    local local_path="$1"
    local remote_file="${2:-$(basename "$local_path")}"
    local url="${GITHUB_BASE_URL}/templates/${remote_file}"

    download_file "$local_path" "$url"
}

# Generate a secure random password
# Usage: generate_password [length]
generate_password() {
    local length="${1:-16}"
    # Use /dev/urandom with base64, filter to alphanumeric + some special chars
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
}

# Function to read password with asterisks shown for each character
read_password() {
    local prompt="$1"
    local password=""
    local char=""

    # Output prompt to stderr so it's visible when stdout is captured
    echo -n "$prompt" >&2

    while IFS= read -r -s -n1 char; do
        if [[ -z "$char" ]]; then
            break
        fi
        if [[ "$char" == $'\x7f' || "$char" == $'\x08' ]]; then
            if [[ -n "$password" ]]; then
                password="${password%?}"
                echo -ne "\b \b" >&2
            fi
        else
            password+="$char"
            echo -n "*" >&2
        fi
    done

    # Newline to stderr for display
    echo "" >&2
    # Password to stdout for capture
    echo "$password"
}

# Prompt with validation loop
prompt_validated() {
    local prompt="$1"
    local default="$2"
    local validator="$3"
    local error_msg="$4"
    local result=""

    while true; do
        read -e -p "$prompt" -i "$default" result
        if $validator "$result"; then
            echo "$result"
            return 0
        fi
        print_error "$error_msg"
    done
}

# =============================================================================
# Progress indicators
# =============================================================================

# Spinner characters for progress display
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

# Progress indicator with spinner
# Waits for process to complete, shows success or failure
# Usage: show_progress PID "message" ["done_message"] [--silent]
# --silent: clear line on success instead of showing done message
show_progress() {
    local pid=$1
    local message="${2:-Processing}"
    local done_message="${3:-$message}"
    local silent=false
    [[ "${3:-}" == "--silent" || "${4:-}" == "--silent" ]] && silent=true
    [[ "${3:-}" == "--silent" ]] && done_message="$message"
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r\e[K${CLR_YELLOW}${SPINNER_CHARS:i++%${#SPINNER_CHARS}:1} %s${CLR_RESET}" "$message"
        sleep 0.2
    done

    # Wait for exit code (process already finished, this just gets the code)
    wait "$pid" 2>/dev/null
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        if [[ "$silent" == true ]]; then
            printf "\r\e[K"
        else
            printf "\r\e[K${CLR_GREEN}✓ %s${CLR_RESET}\n" "$done_message"
        fi
    else
        printf "\r\e[K${CLR_RED}✗ %s${CLR_RESET}\n" "$message"
    fi

    return $exit_code
}

# Wait for condition with progress
wait_with_progress() {
    local message="$1"
    local timeout="$2"
    local check_cmd="$3"
    local interval="${4:-5}"
    local done_message="${5:-$message}"
    local start_time
    start_time=$(date +%s)
    local i=0

    while true; do
        local elapsed=$(($(date +%s) - start_time))

        if eval "$check_cmd" 2>/dev/null; then
            printf "\r\e[K${CLR_GREEN}✓ %s${CLR_RESET}\n" "$done_message"
            return 0
        fi

        if [ $elapsed -ge $timeout ]; then
            printf "\r\e[K${CLR_RED}✗ %s timed out${CLR_RESET}\n" "$message"
            return 1
        fi

        printf "\r\e[K${CLR_YELLOW}${SPINNER_CHARS:i++%${#SPINNER_CHARS}:1} %s${CLR_RESET}" "$message"
        sleep "$interval"
    done
}

# Format time duration
format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m ${secs}s"
    else
        echo "${minutes}m ${secs}s"
    fi
}
