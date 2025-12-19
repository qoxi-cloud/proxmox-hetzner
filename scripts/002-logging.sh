# shellcheck shell=bash
# =============================================================================
# Logging setup
# =============================================================================

# Logs message to file with timestamp (not shown to user).
# Parameters:
#   $* - Message to log
# Side effects: Appends to LOG_FILE
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

# =============================================================================
# Installation Metrics
# =============================================================================

# Installation start time (set by metrics_start)
INSTALL_START_TIME=""

# Starts installation metrics timer.
# Side effects: Sets INSTALL_START_TIME global
metrics_start() {
  INSTALL_START_TIME=$(date +%s)
  log "METRIC: installation_started"
}

# Logs metric for a completed step with elapsed time.
# Parameters:
#   $1 - Step name (e.g., "iso_download", "qemu_start")
# Side effects: Logs metric to LOG_FILE
log_metric() {
  local step="$1"
  if [[ -n $INSTALL_START_TIME ]]; then
    local elapsed=$(($(date +%s) - INSTALL_START_TIME))
    log "METRIC: ${step}_completed elapsed=${elapsed}s"
  fi
}

# Logs final installation metrics summary.
# Side effects: Logs total time and summary to LOG_FILE
metrics_finish() {
  if [[ -n $INSTALL_START_TIME ]]; then
    local total=$(($(date +%s) - INSTALL_START_TIME))
    local minutes=$((total / 60))
    local seconds=$((total % 60))
    log "METRIC: installation_completed total_time=${total}s (${minutes}m ${seconds}s)"
  fi
}
