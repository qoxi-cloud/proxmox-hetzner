# =============================================================================
# SSH helper functions
# =============================================================================

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SSH_PORT="5555"

remote_exec() {
    sshpass -p "$NEW_ROOT_PASSWORD" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "$@"
}

remote_exec_script() {
    sshpass -p "$NEW_ROOT_PASSWORD" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s'
}

# Execute remote script with progress indicator (hides output, shows spinner)
remote_exec_with_progress() {
    local message="$1"
    local script="$2"
    local done_message="${3:-$message}"

    echo "$script" | sshpass -p "$NEW_ROOT_PASSWORD" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s' > /dev/null 2>&1 &
    local pid=$!
    show_progress $pid "$message" "$done_message"
    wait $pid
    return $?
}

remote_copy() {
    local src="$1"
    local dst="$2"
    sshpass -p "$NEW_ROOT_PASSWORD" scp -P "$SSH_PORT" $SSH_OPTS "$src" "root@localhost:$dst"
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
