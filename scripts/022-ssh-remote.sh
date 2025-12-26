# shellcheck shell=bash
# SSH helper functions - Remote execution

# Default timeout for remote commands (seconds)
# Can be overridden per-call or via SSH_COMMAND_TIMEOUT environment variable
readonly SSH_DEFAULT_TIMEOUT=300

# Mask passwords/secrets in script for logging. $1=script → stdout
_sanitize_script_for_log() {
  local script="$1"

  # Use \x01 (ASCII SOH) as delimiter - won't appear in passwords or scripts
  # Avoids conflict with # in passwords or / in paths
  local d=$'\x01'

  # Mask common password patterns (variable assignments and chpasswd)
  script=$(printf '%s\n' "$script" | sed -E "s${d}(PASSWORD|password|PASSWD|passwd|SECRET|secret|TOKEN|token|KEY|key)=('[^']*'|\"[^\"]*\"|[^[:space:]'\";]+)${d}\\1=[REDACTED]${d}g")

  # Pattern: echo "user:password" | chpasswd
  script=$(printf '%s\n' "$script" | sed -E "s${d}(echo[[:space:]]+['\"]?[^:]+:)[^|'\"]*${d}\\1[REDACTED]${d}g")

  # Pattern: --authkey='...' or --authkey="..." or --authkey=...
  script=$(printf '%s\n' "$script" | sed -E "s${d}(--authkey=)('[^']*'|\"[^\"]*\"|[^[:space:]'\";]+)${d}\\1[REDACTED]${d}g")

  printf '%s\n' "$script"
}

# Execute command on remote VM with exponential backoff retry. $*=command. Returns exit code (124=timeout)
remote_exec() {
  local passfile
  passfile=$(_ssh_get_passfile)

  local cmd_timeout="${SSH_COMMAND_TIMEOUT:-$SSH_DEFAULT_TIMEOUT}"
  local max_attempts="${SSH_RETRY_ATTEMPTS:-3}"
  local base_delay="${RETRY_DELAY_SECONDS:-2}"
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
      # Exponential backoff: delay = base_delay * 2^(attempt-1), capped at 30s
      local delay=$((base_delay * (1 << (attempt - 1))))
      ((delay > 30)) && delay=30
      log "SSH attempt $attempt failed, retrying in ${delay} seconds..."
      sleep "$delay"
    fi
  done

  log "ERROR: SSH command failed after $max_attempts attempts: $*"
  return 1
}

# Internal: remote script with progress. Use remote_run() instead.
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
  register_temp_file "$output_file"

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

# PRIMARY: Run remote script with progress, exit on failure.
# $1=message, $2=script, $3=done_message (optional)
remote_run() {
  local message="$1"
  local script="$2"
  local done_message="${3:-$message}"

  if ! _remote_exec_with_progress "$message" "$script" "$done_message"; then
    log "ERROR: $message failed"
    exit 1
  fi
}

# Copy file to remote via SCP. $1=src, $2=dst
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
