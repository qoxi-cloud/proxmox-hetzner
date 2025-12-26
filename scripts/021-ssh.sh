# shellcheck shell=bash
# SSH helper functions - Session management and connection
# ControlMaster multiplexes all connections over single TCP socket

# Control socket path (uses $$ so subshells share master connection)
_SSH_CONTROL_PATH="/tmp/ssh-pve-control.$$"

# SSH options for QEMU VM - host key checking disabled (local/ephemeral)
# Includes keepalive settings: ServerAliveInterval=30s, ServerAliveCountMax=3 (90s before disconnect)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10} -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o ControlPath=${_SSH_CONTROL_PATH} -o ControlPersist=300"
SSH_PORT="${SSH_PORT_QEMU:-5555}"

# Session passfile (created once, path uses $$ for subshell sharing)
_SSH_SESSION_PASSFILE=""
_SSH_SESSION_LOGGED=false

# Session management

# Gets passfile path based on top-level PID ($$ inherited by subshells)
_ssh_passfile_path() {
  local passfile_dir="/dev/shm"
  if [[ ! -d /dev/shm ]] || [[ ! -w /dev/shm ]]; then
    passfile_dir="/tmp"
  fi
  printf '%s\n' "${passfile_dir}/pve-ssh-session.$$"
}

# Initializes SSH session with persistent passfile (creates once, reuses across operations)
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

# Cleans up SSH control master socket (graceful close)
_ssh_control_cleanup() {
  local control_path="/tmp/ssh-pve-control.$$"
  if [[ -S "$control_path" ]]; then
    # Gracefully close master connection
    ssh -o ControlPath="$control_path" -O exit root@localhost 2>/dev/null || true
    rm -f "$control_path" 2>/dev/null || true
    log "SSH control socket cleaned up: $control_path"
  fi
}

# Cleans up SSH session (control socket + passfile with secure deletion)
_ssh_session_cleanup() {
  # Clean up control socket first
  _ssh_control_cleanup

  local passfile_path
  passfile_path=$(_ssh_passfile_path)

  [[ ! -f "$passfile_path" ]] && return 0

  # Use secure_delete_file if available (defined in 012-utils.sh)
  if type secure_delete_file &>/dev/null; then
    secure_delete_file "$passfile_path"
  elif command -v shred &>/dev/null; then
    shred -u -z "$passfile_path" 2>/dev/null || rm -f "$passfile_path"
  else
    # Fallback: overwrite with zeros (cross-platform stat: GNU -c%s, BSD -f%z)
    local file_size
    file_size=$(stat -c%s "$passfile_path" 2>/dev/null || stat -f%z "$passfile_path" 2>/dev/null || echo 1024)
    dd if=/dev/zero of="$passfile_path" bs=1 count="$file_size" conv=notrunc 2>/dev/null || true
    rm -f "$passfile_path"
  fi

  _SSH_SESSION_PASSFILE=""
  log "SSH session cleaned up: $passfile_path"
}

# Gets session passfile (initializes if needed)
_ssh_get_passfile() {
  _ssh_session_init
  printf '%s\n' "$_SSH_SESSION_PASSFILE"
}

# SSH command construction

# Builds base SSH command with options and auth. $1=timeout (optional)
_ssh_base_cmd() {
  local passfile
  passfile=$(_ssh_get_passfile)
  local cmd_timeout="${1:-${SSH_COMMAND_TIMEOUT:-$SSH_DEFAULT_TIMEOUT}}"
  # shellcheck disable=SC2086
  printf 'timeout %s sshpass -f "%s" ssh -p "%s" %s root@localhost' \
    "$cmd_timeout" "$passfile" "$SSH_PORT" "$SSH_OPTS"
}

# Builds SCP command with options and auth
_scp_base_cmd() {
  local passfile
  passfile=$(_ssh_get_passfile)
  # shellcheck disable=SC2086
  printf 'sshpass -f "%s" scp -P "%s" %s' "$passfile" "$SSH_PORT" "$SSH_OPTS"
}

# Port and connection checks

# Checks if port is available. Returns 0 if available, 1 if in use
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

# Waits for SSH to be ready on localhost:SSH_PORT. $1=timeout (default 120)
wait_for_ssh_ready() {
  local timeout="${1:-120}"
  local start_time
  start_time=$(date +%s)

  # Clear any stale known_hosts entries
  local ssh_known_hosts="${INSTALL_DIR:-${HOME:-/root}}/.ssh/known_hosts"
  ssh-keygen -f "$ssh_known_hosts" -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

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

# SSH key utilities

# Parses SSH key into SSH_KEY_TYPE, SSH_KEY_DATA, SSH_KEY_COMMENT, SSH_KEY_SHORT
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

# Gets SSH public key from rescue system's authorized_keys (first valid key)
get_rescue_ssh_key() {
  local auth_keys="${INSTALL_DIR:-${HOME:-/root}}/.ssh/authorized_keys"
  if [[ -f "$auth_keys" ]]; then
    grep -E "^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh.com)" "$auth_keys" 2>/dev/null | head -1
  fi
}
