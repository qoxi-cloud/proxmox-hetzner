# shellcheck shell=bash
# =============================================================================
# SSH helper functions
# =============================================================================

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
SSH_PORT="5555"

# Wait for SSH to be fully ready (not just port open)
wait_for_ssh_ready() {
    local max_attempts="${1:-60}"
    local attempt=0
    local i=0

    # Clear any stale known_hosts entries
    ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

    while [[ $attempt -lt $max_attempts ]]; do
        # Try actual SSH connection with echo command
        # Use SSHPASS env var to avoid password exposure in process list
        # shellcheck disable=SC2086
        if SSHPASS="$NEW_ROOT_PASSWORD" sshpass -e ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "echo ready" >/dev/null 2>&1; then
            printf "\r\e[K${CLR_GREEN}✓ SSH connection established${CLR_RESET}\n"
            return 0
        fi
        printf "\r${CLR_YELLOW}${SPINNER_CHARS:i++%${#SPINNER_CHARS}:1} Waiting for SSH to be ready (attempt $((attempt+1))/${max_attempts})${CLR_RESET}"
        sleep 2
        ((attempt++))
    done

    printf "\r\e[K${CLR_RED}✗ SSH connection failed after ${max_attempts} attempts${CLR_RESET}\n"
    return 1
}

remote_exec() {
    # Use SSHPASS env var to avoid password exposure in process list
    # shellcheck disable=SC2086
    SSHPASS="$NEW_ROOT_PASSWORD" sshpass -e ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "$@"
}

remote_exec_script() {
    # shellcheck disable=SC2086
    SSHPASS="$NEW_ROOT_PASSWORD" sshpass -e ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s'
}

# Execute remote script with progress indicator (logs output to file, shows spinner)
remote_exec_with_progress() {
    local message="$1"
    local script="$2"
    local done_message="${3:-$message}"

    log "remote_exec_with_progress: $message"
    log "--- Script start ---"
    echo "$script" >> "$LOG_FILE"
    log "--- Script end ---"

    # shellcheck disable=SC2086
    echo "$script" | SSHPASS="$NEW_ROOT_PASSWORD" sshpass -e ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s' >> "$LOG_FILE" 2>&1 &
    local pid=$!
    show_progress $pid "$message" "$done_message"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log "remote_exec_with_progress: FAILED with exit code $exit_code"
    else
        log "remote_exec_with_progress: completed successfully"
    fi

    return $exit_code
}

# Execute remote script with progress, exit on failure
# Usage: run_remote "message" 'script' ["done_message"]
run_remote() {
    local message="$1"
    local script="$2"
    local done_message="${3:-$message}"

    if ! remote_exec_with_progress "$message" "$script" "$done_message"; then
        print_error "$message failed"
        echo "       Check log file: $LOG_FILE"
        exit 1
    fi
}

remote_copy() {
    local src="$1"
    local dst="$2"
    # shellcheck disable=SC2086
    SSHPASS="$NEW_ROOT_PASSWORD" sshpass -e scp -P "$SSH_PORT" $SSH_OPTS "$src" "root@localhost:$dst"
}

# =============================================================================
# SSH key utilities
# =============================================================================

# Parse SSH public key into components
# Sets: SSH_KEY_TYPE, SSH_KEY_DATA, SSH_KEY_COMMENT, SSH_KEY_SHORT
parse_ssh_key() {
    local key="$1"

    # Reset variables
    SSH_KEY_TYPE=""
    SSH_KEY_DATA=""
    SSH_KEY_COMMENT=""
    SSH_KEY_SHORT=""

    if [[ -z "$key" ]]; then
        return 1
    fi

    # Parse: type base64data [comment]
    SSH_KEY_TYPE=$(echo "$key" | awk '{print $1}')
    SSH_KEY_DATA=$(echo "$key" | awk '{print $2}')
    SSH_KEY_COMMENT=$(echo "$key" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')

    # Create shortened version of key data (first 20 + last 10 chars)
    if [[ ${#SSH_KEY_DATA} -gt 35 ]]; then
        SSH_KEY_SHORT="${SSH_KEY_DATA:0:20}...${SSH_KEY_DATA: -10}"
    else
        SSH_KEY_SHORT="$SSH_KEY_DATA"
    fi

    return 0
}

# Validate SSH public key format
validate_ssh_key() {
    local key="$1"
    [[ "$key" =~ ^ssh-(rsa|ed25519|ecdsa)[[:space:]] ]]
}

# Get SSH key from rescue system authorized_keys
get_rescue_ssh_key() {
    if [[ -f /root/.ssh/authorized_keys ]]; then
        grep -E "^ssh-(rsa|ed25519|ecdsa)" /root/.ssh/authorized_keys 2>/dev/null | head -1
    fi
}
