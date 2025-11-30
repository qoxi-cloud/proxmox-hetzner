# shellcheck shell=bash
# =============================================================================
# SSH helper functions
# =============================================================================

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
SSH_PORT="5555"

# Check if port is available before use
check_port_available() {
    local port="$1"
    if command -v ss &>/dev/null; then
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            return 1
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            return 1
        fi
    fi
    return 0
}

# Create secure temporary file for password
# Uses /dev/shm if available (RAM-based, faster and more secure)
# Falls back to regular /tmp if /dev/shm is not available
# Returns: path to temporary file
create_passfile() {
    local passfile
    # Try /dev/shm first (RAM-based, not on disk)
    if [[ -d /dev/shm ]] && [[ -w /dev/shm ]]; then
        passfile=$(mktemp --tmpdir=/dev/shm pve-passfile.XXXXXX 2>/dev/null || mktemp)
    else
        passfile=$(mktemp)
    fi
    
    echo "$NEW_ROOT_PASSWORD" > "$passfile"
    chmod 600 "$passfile"
    
    echo "$passfile"
}

# Securely clean up password file
# Uses shred if available, otherwise overwrites with zeros before deletion
secure_cleanup_passfile() {
    local passfile="$1"
    if [[ -f "$passfile" ]]; then
        # Try to securely erase using shred
        if command -v shred &>/dev/null; then
            shred -u -z "$passfile" 2>/dev/null || rm -f "$passfile"
        else
            # Fallback: overwrite with zeros if dd is available
            if command -v dd &>/dev/null; then
                local file_size
                file_size=$(stat -c%s "$passfile" 2>/dev/null || echo 1024)
                dd if=/dev/zero of="$passfile" bs=1 count="$file_size" 2>/dev/null || true
            fi
            rm -f "$passfile"
        fi
    fi
}

# Wait for SSH to be fully ready (not just port open)
wait_for_ssh_ready() {
    local timeout="${1:-120}"

    # Clear any stale known_hosts entries
    ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

    # Quick port check first (faster than SSH attempts)
    local port_check=0
    for i in {1..10}; do
        if (echo >/dev/tcp/localhost/$SSH_PORT) 2>/dev/null; then
            port_check=1
            break
        fi
        sleep 1
    done

    if [[ $port_check -eq 0 ]]; then
        print_error "Port $SSH_PORT is not accessible"
        log "ERROR: Port $SSH_PORT not accessible after 10 attempts"
        return 1
    fi

    # Use secure temporary file for password
    local passfile
    passfile=$(create_passfile)
    
    # shellcheck disable=SC2086
    wait_with_progress "Waiting for SSH to be ready" "$timeout" \
        "sshpass -f \"$passfile\" ssh -p \"$SSH_PORT\" $SSH_OPTS root@localhost 'echo ready' >/dev/null 2>&1" \
        2 "SSH connection established"
    
    local exit_code=$?
    secure_cleanup_passfile "$passfile"
    return $exit_code
}

remote_exec() {
    # Use secure temporary file for password
    local passfile
    passfile=$(create_passfile)
    
    # Retry logic for SSH connections
    local max_attempts=3
    local attempt=0
    local exit_code=1
    
    while [[ $attempt -lt $max_attempts ]]; do
        attempt=$((attempt + 1))
        
        # shellcheck disable=SC2086
        if sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "$@"; then
            exit_code=0
            break
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "SSH attempt $attempt failed, retrying in 2 seconds..."
            sleep 2
        fi
    done
    
    secure_cleanup_passfile "$passfile"
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: SSH command failed after $max_attempts attempts: $*"
    fi
    
    return $exit_code
}

remote_exec_script() {
    # Use secure temporary file for password
    local passfile
    passfile=$(create_passfile)
    
    # shellcheck disable=SC2086
    sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s'
    local exit_code=$?
    
    secure_cleanup_passfile "$passfile"
    return $exit_code
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

    # Use secure temporary file for password
    local passfile
    passfile=$(create_passfile)
    
    # Create temporary file for output to check for errors
    local output_file
    output_file=$(mktemp)

    # shellcheck disable=SC2086
    echo "$script" | sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s' > "$output_file" 2>&1 &
    local pid=$!
    show_progress $pid "$message" "$done_message"
    local exit_code=$?

    # Check output for critical errors
    if grep -qiE "(error|failed|cannot|unable|fatal)" "$output_file" 2>/dev/null; then
        log "WARNING: Potential errors in remote command output:"
        grep -iE "(error|failed|cannot|unable|fatal)" "$output_file" >> "$LOG_FILE" 2>/dev/null || true
    fi
    
    # Append output to log file
    cat "$output_file" >> "$LOG_FILE"
    rm -f "$output_file"

    secure_cleanup_passfile "$passfile"

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
        log "ERROR: $message failed"
        exit 1
    fi
}

remote_copy() {
    local src="$1"
    local dst="$2"
    
    # Use secure temporary file for password
    local passfile
    passfile=$(create_passfile)
    
    # shellcheck disable=SC2086
    sshpass -f "$passfile" scp -P "$SSH_PORT" $SSH_OPTS "$src" "root@localhost:$dst"
    local exit_code=$?
    
    secure_cleanup_passfile "$passfile"
    return $exit_code
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
