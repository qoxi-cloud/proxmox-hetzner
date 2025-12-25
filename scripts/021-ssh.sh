# shellcheck shell=bash
# =============================================================================
# SSH helper functions
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

  # Create new passfile
  printf '%s\n' "$NEW_ROOT_PASSWORD" >"$passfile_path"
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

  # Clear any stale known_hosts entries
  ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

  # Split timeout: 75% for port check (boot is slow), 25% for SSH verification
  local port_timeout=$((timeout * 3 / 4))
  local ssh_timeout=$((timeout - port_timeout))

  # Port check - wait for VM to boot and open SSH port
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
# Remote execution functions
# =============================================================================
#
# Function selection guide:
#
# remote_exec()      - Low-level SSH execution with retry. Use for:
#                      - Single commands that may not need progress display
#                      - Commands within subshells that already show progress
#                      - Quick status checks or simple configurations
#                      - Returns exit code (doesn't exit on failure)
#
# remote_run()       - Primary function for configuration scripts. Use for:
#                      - All major installation/configuration steps
#                      - Commands that should show progress to user
#                      - Operations where failure should abort installation
#                      - Automatically exits on failure (no manual error handling)
#
# remote_copy()      - SCP file transfer. Use for:
#                      - Deploying config files and templates
#                      - Returns exit code (check manually or use || return 1)
#
# deploy_template()  - High-level helper (in 038-deploy-helpers.sh). Use for:
#                      - Templates with variable substitution + remote copy
#
# run_with_progress() - Background command with progress. Use for:
#                      - Local or remote operations needing progress display
#                      - Wraps any command (not just SSH)
#
# =============================================================================

# Default timeout for remote commands (seconds)
# Can be overridden per-call or via SSH_COMMAND_TIMEOUT environment variable
readonly SSH_DEFAULT_TIMEOUT=300

# Sanitizes script content for logging by masking sensitive values.
# Replaces passwords and secrets with [REDACTED] to prevent leaks in log files.
# Parameters:
#   $1 - Script content to sanitize
# Returns: Sanitized script via stdout
_sanitize_script_for_log() {
  local script="$1"

  # Mask common password patterns (variable assignments and chpasswd)
  # Pattern: PASSWORD=something, PASSWORD="quoted", PASSWORD='quoted'
  # Handle unquoted, single-quoted, and double-quoted values
  script=$(printf '%s\n' "$script" | sed -E 's/(PASSWORD|password|PASSWD|passwd|SECRET|secret|TOKEN|token|KEY|key)=('"'"'[^'"'"']*'"'"'|"[^"]*"|[^[:space:]'"'"'";]+)/\1=[REDACTED]/g')

  # Pattern: echo "user:password" | chpasswd
  script=$(printf '%s\n' "$script" | sed -E 's/(echo[[:space:]]+['\''"]?[^:]+:)[^|'\''"]*/\1[REDACTED]/g')

  # Pattern: --authkey='...' or --authkey="..." or --authkey=...
  # Handle unquoted, single-quoted, and double-quoted values
  script=$(printf '%s\n' "$script" | sed -E 's/(--authkey=)('"'"'[^'"'"']*'"'"'|"[^"]*"|[^[:space:]'"'"'";]+)/\1[REDACTED]/g')

  printf '%s\n' "$script"
}

# Executes command on remote VM via SSH with retry logic and timeout.
# Use when you need return code handling or within subshells with own progress.
# Parameters:
#   $* - Command to execute remotely
# Environment:
#   SSH_COMMAND_TIMEOUT - Override default timeout (seconds, default: 300)
# Returns: Exit code from remote command (124 on timeout)
remote_exec() {
  local passfile
  passfile=$(_ssh_get_passfile)

  local cmd_timeout="${SSH_COMMAND_TIMEOUT:-$SSH_DEFAULT_TIMEOUT}"
  local max_attempts="${SSH_RETRY_ATTEMPTS:-3}"
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))

    # shellcheck disable=SC2086
    if timeout "$cmd_timeout" sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "$@"; then
      return 0
    fi

    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      log "ERROR: SSH command timed out after ${cmd_timeout}s: $*"
      return 124
    fi

    if [[ $attempt -lt $max_attempts ]]; then
      log "SSH attempt $attempt failed, retrying in ${RETRY_DELAY_SECONDS:-2} seconds..."
      sleep "${RETRY_DELAY_SECONDS:-2}"
    fi
  done

  log "ERROR: SSH command failed after $max_attempts attempts: $*"
  return 1
}

# Internal: Executes remote script with progress indicator.
# Don't use directly - use remote_run() instead which handles errors.
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
  log "--- Script start (sanitized) ---"
  # Sanitize script before logging to prevent password leaks
  _sanitize_script_for_log "$script" >>"$LOG_FILE"
  log "--- Script end ---"

  local passfile
  passfile=$(_ssh_get_passfile)

  local output_file
  output_file=$(mktemp)

  local cmd_timeout="${SSH_COMMAND_TIMEOUT:-$SSH_DEFAULT_TIMEOUT}"

  # shellcheck disable=SC2086
  printf '%s\n' "$script" | timeout "$cmd_timeout" sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s' >"$output_file" 2>&1 &
  local pid=$!
  show_progress $pid "$message" "$done_message"
  local exit_code=$?

  # Check output for critical errors (exclude package names like liberror-perl)
  # Use word boundaries and exclude common false positives from apt output
  if grep -iE '\b(error|failed|cannot|unable|fatal)\b' "$output_file" 2>/dev/null \
    | grep -qivE '(lib.*error|error-perl|\.deb|Unpacking|Setting up|Selecting)'; then
    log "WARNING: Potential errors in remote command output:"
    grep -iE '\b(error|failed|cannot|unable|fatal)\b' "$output_file" 2>/dev/null \
      | grep -ivE '(lib.*error|error-perl|\.deb|Unpacking|Setting up|Selecting)' >>"$LOG_FILE" || true
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
# PRIMARY function for all configuration scripts - use this by default.
# Shows progress spinner to user and logs output for debugging.
# Parameters:
#   $1 - Progress message (shown while running)
#   $2 - Script content to execute (can be multi-line heredoc)
#   $3 - Done message (optional, defaults to $1)
# Side effects: Exits with code 1 on failure (no need to check return)
# Example:
#   remote_run "Installing packages" 'apt-get install -y foo' "Packages installed"
remote_run() {
  local message="$1"
  local script="$2"
  local done_message="${3:-$message}"

  if ! _remote_exec_with_progress "$message" "$script" "$done_message"; then
    log "ERROR: $message failed"
    exit 1
  fi
}

# Copies file to remote VM via SCP.
# Use for deploying config files. For templates with vars, use deploy_template().
# Parameters:
#   $1 - Source file path (local)
#   $2 - Destination path (remote)
# Returns: 0 on success, 1 on failure (check manually: || return 1)
# Example:
#   remote_copy "templates/foo.conf" "/etc/foo.conf" || return 1
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
    grep -E "^ssh-(rsa|ed25519|ecdsa)" /root/.ssh/authorized_keys 2>/dev/null | head -1
  fi
}
