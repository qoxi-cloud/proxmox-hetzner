# shellcheck shell=bash
# =============================================================================
# SSH helper functions
# =============================================================================

# SSH options for QEMU VM on localhost - host key checking disabled since VM is local/ephemeral
# NOT suitable for production remote servers
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10}"
SSH_PORT="5555"

# Session passfile - created once, reused for all SSH operations
_SSH_SESSION_PASSFILE=""
_SSH_SESSION_LOGGED=false

# =============================================================================
# Session management
# =============================================================================

# Initializes SSH session with persistent passfile.
# Creates passfile once for reuse across all remote operations.
# Side effects: Sets _SSH_SESSION_PASSFILE, registers cleanup trap
_ssh_session_init() {
  # Already initialized
  [[ -n $_SSH_SESSION_PASSFILE ]] && [[ -f $_SSH_SESSION_PASSFILE ]] && return 0

  # Create passfile in RAM if possible
  if [[ -d /dev/shm ]] && [[ -w /dev/shm ]]; then
    _SSH_SESSION_PASSFILE=$(mktemp --tmpdir=/dev/shm pve-ssh-session.XXXXXX 2>/dev/null || mktemp)
  else
    _SSH_SESSION_PASSFILE=$(mktemp)
  fi

  echo "$NEW_ROOT_PASSWORD" >"$_SSH_SESSION_PASSFILE"
  chmod 600 "$_SSH_SESSION_PASSFILE"

  # Register cleanup on exit - but ONLY in main shell, not in subshells
  # Command substitution like $(func) runs in subshell, and EXIT trap would
  # delete the passfile immediately when subshell exits
  if [[ $BASHPID == "$$" ]]; then
    local existing_trap
    existing_trap=$(trap -p EXIT 2>/dev/null | sed "s/trap -- '\\(.*\\)' EXIT/\\1/" || true)
    if [[ -n $existing_trap ]]; then
      # shellcheck disable=SC2064
      trap "${existing_trap}; _ssh_session_cleanup" EXIT
    else
      trap '_ssh_session_cleanup' EXIT
    fi

    # Only log once from main shell
    if [[ $_SSH_SESSION_LOGGED != true ]]; then
      log "SSH session initialized"
      _SSH_SESSION_LOGGED=true
    fi
  fi
}

# Cleans up SSH session passfile securely.
# Uses secure_delete_file if available, otherwise shred/dd fallback.
_ssh_session_cleanup() {
  [[ -z $_SSH_SESSION_PASSFILE ]] && return 0
  [[ ! -f $_SSH_SESSION_PASSFILE ]] && return 0

  # Use secure_delete_file if available (defined in 012-utils.sh)
  if type secure_delete_file &>/dev/null; then
    secure_delete_file "$_SSH_SESSION_PASSFILE"
  elif command -v shred &>/dev/null; then
    shred -u -z "$_SSH_SESSION_PASSFILE" 2>/dev/null || rm -f "$_SSH_SESSION_PASSFILE"
  else
    # Fallback: overwrite with zeros
    local file_size
    file_size=$(stat -c%s "$_SSH_SESSION_PASSFILE" 2>/dev/null || echo 1024)
    dd if=/dev/zero of="$_SSH_SESSION_PASSFILE" bs=1 count="$file_size" conv=notrunc 2>/dev/null || true
    rm -f "$_SSH_SESSION_PASSFILE"
  fi

  _SSH_SESSION_PASSFILE=""
  log "SSH session cleaned up"
}

# Gets session passfile, initializing if needed.
# Returns: Path to passfile via stdout
_ssh_get_passfile() {
  _ssh_session_init
  echo "$_SSH_SESSION_PASSFILE"
}

# =============================================================================
# Port and connection checks
# =============================================================================

# Checks if specified port is available (not in use).
# Parameters:
#   $1 - Port number to check
# Returns: 0 if available, 1 if in use
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

# Waits for SSH service to be fully ready on localhost:SSH_PORT.
# Performs port check followed by SSH connection test.
# Parameters:
#   $1 - Timeout in seconds (default: 120)
# Returns: 0 if SSH ready, 1 on timeout or failure
wait_for_ssh_ready() {
  local timeout="${1:-120}"

  # Clear any stale known_hosts entries
  ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

  # Quick port check first (faster than SSH attempts)
  local port_check=0
  for _ in {1..10}; do
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

  local passfile
  passfile=$(_ssh_get_passfile)

  # Wait for SSH to be ready with background process
  (
    local elapsed=0
    while ((elapsed < timeout)); do
      # shellcheck disable=SC2086
      if sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'echo ready' >/dev/null 2>&1; then
        exit 0
      fi
      sleep 2
      ((elapsed += 2))
    done
    exit 1
  ) &
  local wait_pid=$!

  show_progress $wait_pid "Waiting for SSH to be ready" "SSH connection established"
  return $?
}

# =============================================================================
# Remote execution functions
# =============================================================================

# Executes command on remote VM via SSH with retry logic.
# Parameters:
#   $* - Command to execute remotely
# Returns: Exit code from remote command
remote_exec() {
  local passfile
  passfile=$(_ssh_get_passfile)

  local max_attempts=3
  local attempt=0
  local exit_code=1

  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))

    # shellcheck disable=SC2086
    if sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "$@"; then
      return 0
    fi

    if [[ $attempt -lt $max_attempts ]]; then
      log "SSH attempt $attempt failed, retrying in 2 seconds..."
      sleep 2
    fi
  done

  log "ERROR: SSH command failed after $max_attempts attempts: $*"
  return 1
}

# Internal: Executes remote script with progress indicator.
# Parameters:
#   $1 - Progress message
#   $2 - Script content to execute
#   $3 - Done message (optional, defaults to $1)
# Returns: Exit code from remote script
_remote_exec_with_progress() {
  local message="$1"
  local script="$2"
  local done_message="${3:-$message}"

  log "_remote_exec_with_progress: $message"
  log "--- Script start ---"
  echo "$script" >>"$LOG_FILE"
  log "--- Script end ---"

  local passfile
  passfile=$(_ssh_get_passfile)

  local output_file
  output_file=$(mktemp)

  # shellcheck disable=SC2086
  echo "$script" | sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s' >"$output_file" 2>&1 &
  local pid=$!
  show_progress $pid "$message" "$done_message"
  local exit_code=$?

  # Check output for critical errors
  if grep -qiE "(error|failed|cannot|unable|fatal)" "$output_file" 2>/dev/null; then
    log "WARNING: Potential errors in remote command output:"
    grep -iE "(error|failed|cannot|unable|fatal)" "$output_file" >>"$LOG_FILE" 2>/dev/null || true
  fi

  cat "$output_file" >>"$LOG_FILE"
  rm -f "$output_file"

  if [[ $exit_code -ne 0 ]]; then
    log "_remote_exec_with_progress: FAILED with exit code $exit_code"
  else
    log "_remote_exec_with_progress: completed successfully"
  fi

  return $exit_code
}

# Executes remote script with progress, exits on failure.
# This is the primary function for running installation scripts.
# Parameters:
#   $1 - Progress message
#   $2 - Script content to execute
#   $3 - Done message (optional, defaults to $1)
# Side effects: Exits with code 1 on failure
run_remote() {
  local message="$1"
  local script="$2"
  local done_message="${3:-$message}"

  if ! _remote_exec_with_progress "$message" "$script" "$done_message"; then
    log "ERROR: $message failed"
    exit 1
  fi
}

# Copies file to remote VM via SCP.
# Parameters:
#   $1 - Source file path (local)
#   $2 - Destination path (remote)
# Returns: 0 on success, 1 on failure
remote_copy() {
  local src="$1"
  local dst="$2"

  local passfile
  passfile=$(_ssh_get_passfile)

  # shellcheck disable=SC2086
  if ! sshpass -f "$passfile" scp -P "$SSH_PORT" $SSH_OPTS "$src" "root@localhost:$dst"; then
    log "ERROR: Failed to copy $src to $dst"
    return 1
  fi
}

# =============================================================================
# SSH key utilities
# =============================================================================

# Parses SSH public key into components.
# Parameters:
#   $1 - SSH public key string
# Returns: 0 on success, 1 if key is empty
# Side effects: Sets SSH_KEY_TYPE, SSH_KEY_DATA, SSH_KEY_COMMENT, SSH_KEY_SHORT globals
parse_ssh_key() {
  local key="$1"

  SSH_KEY_TYPE=""
  SSH_KEY_DATA=""
  SSH_KEY_COMMENT=""
  SSH_KEY_SHORT=""

  [[ -z $key ]] && return 1

  SSH_KEY_TYPE=$(echo "$key" | awk '{print $1}')
  SSH_KEY_DATA=$(echo "$key" | awk '{print $2}')
  SSH_KEY_COMMENT=$(echo "$key" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')

  if [[ ${#SSH_KEY_DATA} -gt 35 ]]; then
    SSH_KEY_SHORT="${SSH_KEY_DATA:0:20}...${SSH_KEY_DATA: -10}"
  else
    SSH_KEY_SHORT="$SSH_KEY_DATA"
  fi

  return 0
}

# Retrieves SSH public key from rescue system's authorized_keys.
# Returns: First valid SSH public key via stdout, empty if none found
get_rescue_ssh_key() {
  if [[ -f /root/.ssh/authorized_keys ]]; then
    grep -E "^ssh-(rsa|ed25519|ecdsa)" /root/.ssh/authorized_keys 2>/dev/null | head -1
  fi
}
