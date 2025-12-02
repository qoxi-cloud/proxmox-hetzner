# shellcheck shell=bash
# =============================================================================
# Logging setup
# =============================================================================

# Logs message to file with timestamp (not shown to user).
# Parameters:
#   $* - Message to log
# Side effects: Appends to LOG_FILE
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Logs debug message to file with [DEBUG] prefix.
# Parameters:
#   $* - Debug message to log
# Side effects: Appends to LOG_FILE
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >> "$LOG_FILE"
}

# Executes command and logs its output to file.
# Parameters:
#   $* - Command and arguments to execute
# Returns: Exit code of the command
# Side effects: Logs command, output, and exit code to LOG_FILE
log_cmd() {
    log_debug "Running: $*"
    "$@" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    log_debug "Exit code: $exit_code"
    return $exit_code
}

# Executes command silently, logging output to file only.
# Parameters:
#   $* - Command and arguments to execute
# Returns: Exit code of the command
# Side effects: Redirects output to LOG_FILE
run_logged() {
    log_debug "Executing: $*"
    "$@" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    log_debug "Exit code: $exit_code"
    return $exit_code
}
