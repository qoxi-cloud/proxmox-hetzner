# shellcheck shell=bash
# =============================================================================
# Asynchronous operation helpers
# =============================================================================

# Executes command with retry logic and exponential backoff.
# Parameters:
#   $1 - Maximum number of retries (default: 3)
#   $2 - Initial delay in seconds (default: 2)
#   $@ - Command and arguments to execute
# Returns: 0 on success, 1 if all retries exhausted
retry_command() {
  local max_retries="${1:-3}"
  local delay="${2:-2}"
  shift 2

  local retry_count=0
  while [ "$retry_count" -lt "$max_retries" ]; do
    if "$@"; then
      return 0
    fi
    retry_count=$((retry_count + 1))
    if [ "$retry_count" -lt "$max_retries" ]; then
      log "Retry $retry_count/$max_retries after ${delay}s delay"
      sleep "$delay"
      delay=$((delay * 2)) # exponential backoff
    fi
  done

  log "ERROR: Command failed after $max_retries attempts"
  return 1
}

# Runs command in background with progress indicator and error handling.
# Parameters:
#   $1 - Progress message
#   $2 - Done message
#   $@ - Command and arguments to execute
# Returns: Exit code of the command
# Side effects: Logs to LOG_FILE, displays progress via show_progress
run_with_progress() {
  local message="$1"
  local done_message="$2"
  shift 2

  # Execute command in background, redirecting output to log
  "$@" >>"$LOG_FILE" 2>&1 &
  local pid=$!

  # Show progress indicator
  show_progress "$pid" "$message" "$done_message"
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: $message failed with exit code $exit_code"
    return 1
  fi

  return 0
}

# Executes multiple commands in parallel and waits for all to complete.
# Parameters:
#   $@ - Commands to execute in parallel (as strings)
# Returns: 0 if all succeeded, 1 if any failed
# Note: Commands are eval'd, so be careful with quoting
run_parallel() {
  local -a pids=()
  local exit_code=0

  # Start all commands in background
  for cmd in "$@"; do
    eval "$cmd" &
    pids+=($!)
  done

  # Wait for all commands to complete
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      exit_code=1
    fi
  done

  return $exit_code
}
