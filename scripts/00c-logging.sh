# shellcheck shell=bash
# =============================================================================
# Logging setup
# =============================================================================

# Log silently to file only (not shown to user)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Log debug info (only to file)
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >> "$LOG_FILE"
}

# Log command output to file
# Usage: log_cmd command [args...]
# Example: log_cmd apt-get update
log_cmd() {
    log_debug "Running: $*"
    "$@" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    log_debug "Exit code: $exit_code"
    return $exit_code
}

# Run command silently, log output to file, return exit code
run_logged() {
    log_debug "Executing: $*"
    "$@" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    log_debug "Exit code: $exit_code"
    return $exit_code
}
