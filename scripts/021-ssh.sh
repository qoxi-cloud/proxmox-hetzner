# shellcheck shell=bash
# =============================================================================
# SSH helper functions - Session management and connection
# =============================================================================

# SSH options for QEMU VM on localhost - host key checking disabled since VM is local/ephemeral
# NOT suitable for production remote servers
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10}"
SSH_PORT="${SSH_PORT_QEMU:-5555}"

# Session passfile - created once, reused for all SSH operations
# Uses predictable path with $$ (top-level PID) so subshells share same file
_SSH_SESSION_PASSFILE=""
_SSH_SESSION_LOGGED=false

# =============================================================================
# Session management
# =============================================================================

# Gets the predictable passfile path based on top-level shell PID.
# $$ is inherited by subshells, so all invocations see the same path.
# Returns: Path via stdout
_ssh_passfile_path() {
  local passfile_dir="/dev/shm"
  if [[ ! -d /dev/shm ]] || [[ ! -w /dev/shm ]]; then
    passfile_dir="/tmp"
  fi
  printf '%s\n' "${passfile_dir}/pve-ssh-session.$$"
}

# Initializes SSH session with persistent passfile.
# Creates passfile once for reuse across all remote operations.
# Uses predictable path with $$ so subshells find existing file.
# Side effects: Sets _SSH_SESSION_PASSFILE, registers cleanup trap
_ssh_session_init() {
  local passfile_path
  passfile_path=$(_ssh_passfile_path)

  # Already exists with content? Just set variable and return
  if [[ -f "$passfile_path" ]] && [[ -s "$passfile_path" ]]; then
    _SSH_SESSION_PASSFILE="$passfile_path"
    return 0
  fi

  # Create new passfile (no trailing newline - sshpass reads entire file content)
  printf '%s' "$NEW_ROOT_PASSWORD" >"$passfile_path"
  chmod 600 "$passfile_path"
  _SSH_SESSION_PASSFILE="$passfile_path"

  # Log once from main shell (cleanup handled by cleanup_and_error_handler in 000-init.sh)
  if [[ $BASHPID == "$$" ]] && [[ $_SSH_SESSION_LOGGED != true ]]; then
    log "SSH session initialized: $passfile_path"
    _SSH_SESSION_LOGGED=true
  fi
}

# Cleans up SSH session passfile securely.
# Uses secure_delete_file if available, otherwise shred/dd fallback.
# Uses predictable path so cleanup works even if variable is empty.
_ssh_session_cleanup() {
  local passfile_path
  passfile_path=$(_ssh_passfile_path)

  [[ ! -f "$passfile_path" ]] && return 0

  # Use secure_delete_file if available (defined in 012-utils.sh)
  if type secure_delete_file &>/dev/null; then
    secure_delete_file "$passfile_path"
  elif command -v shred &>/dev/null; then
    shred -u -z "$passfile_path" 2>/dev/null || rm -f "$passfile_path"
  else
    # Fallback: overwrite with zeros
    local file_size
    file_size=$(stat -c%s "$passfile_path" 2>/dev/null || echo 1024)
    dd if=/dev/zero of="$passfile_path" bs=1 count="$file_size" conv=notrunc 2>/dev/null || true
    rm -f "$passfile_path"
  fi

  _SSH_SESSION_PASSFILE=""
  log "SSH session cleaned up: $passfile_path"
}

# Gets session passfile, initializing if needed.
# Returns: Path to passfile via stdout
_ssh_get_passfile() {
  _ssh_session_init
  printf '%s\n' "$_SSH_SESSION_PASSFILE"
}

# =============================================================================
# SSH command construction
# =============================================================================

# Builds base SSH command with options and authentication.
# Use this helper to avoid repeating SSH options across functions.
# Parameters:
#   $1 - Optional timeout (default: SSH_DEFAULT_TIMEOUT)
# Returns: Prints command prefix to stdout (use with eval or as array)
# Example: eval "$(_ssh_base_cmd) 'remote command'"
_ssh_base_cmd() {
  local passfile
  passfile=$(_ssh_get_passfile)
  local cmd_timeout="${1:-${SSH_COMMAND_TIMEOUT:-$SSH_DEFAULT_TIMEOUT}}"
  # shellcheck disable=SC2086
  printf 'timeout %s sshpass -f "%s" ssh -p "%s" %s root@localhost' \
    "$cmd_timeout" "$passfile" "$SSH_PORT" "$SSH_OPTS"
}

# Builds SCP command with options and authentication.
# Parameters: None
# Returns: Prints command prefix to stdout
# Example: eval "$(_scp_base_cmd) /local/file root@localhost:/remote/path"
_scp_base_cmd() {
  local passfile
  passfile=$(_ssh_get_passfile)
  # shellcheck disable=SC2086
  printf 'sshpass -f "%s" scp -P "%s" %s' "$passfile" "$SSH_PORT" "$SSH_OPTS"
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
  local start_time
  start_time=$(date +%s)

  # Clear any stale known_hosts entries
  ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

  # Port check - wait for VM to boot and open SSH port
  # Allow up to 75% of timeout for port check, but track actual elapsed time
  local port_timeout=$((timeout * 3 / 4))
  local port_check=0
  local elapsed=0
  while ((elapsed < port_timeout)); do
    if (echo >/dev/tcp/localhost/"$SSH_PORT") 2>/dev/null; then
      port_check=1
      break
    fi
    sleep "${RETRY_DELAY_SECONDS:-2}"
    ((elapsed += RETRY_DELAY_SECONDS))
  done

  if [[ $port_check -eq 0 ]]; then
    print_error "Port $SSH_PORT is not accessible"
    log "ERROR: Port $SSH_PORT not accessible after ${port_timeout}s"
    return 1
  fi

  # Calculate remaining time for SSH verification
  local actual_elapsed=$(($(date +%s) - start_time))
  local ssh_timeout=$((timeout - actual_elapsed))
  if ((ssh_timeout < 10)); then
    ssh_timeout=10 # Minimum 10s for SSH check
  fi

  local passfile
  passfile=$(_ssh_get_passfile)

  # Wait for SSH to be ready with background process
  (
    local elapsed=0
    local retry_delay="${RETRY_DELAY_SECONDS:-2}"
    while ((elapsed < ssh_timeout)); do
      # shellcheck disable=SC2086
      if sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'echo ready' >/dev/null 2>&1; then
        exit 0
      fi
      sleep "$retry_delay"
      ((elapsed += retry_delay))
    done
    exit 1
  ) &
  local wait_pid=$!

  show_progress $wait_pid "Waiting for SSH to be ready" "SSH connection established"
  return $?
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

  SSH_KEY_TYPE=$(printf '%s\n' "$key" | awk '{print $1}')
  SSH_KEY_DATA=$(printf '%s\n' "$key" | awk '{print $2}')
  SSH_KEY_COMMENT=$(printf '%s\n' "$key" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')

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
    grep -E "^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh.com)" /root/.ssh/authorized_keys 2>/dev/null | head -1
  fi
}
