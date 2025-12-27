# shellcheck shell=bash
# Logging setup

# Log message to file with timestamp. $*=message
log() {
  printf '%s\n' "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

# Installation Metrics

# Start installation metrics timer. Sets INSTALL_START_TIME.
metrics_start() {
  INSTALL_START_TIME=$(date +%s)
  log "METRIC: installation_started"
}

# Log metric with elapsed time. $1=step_name
log_metric() {
  local step="$1"
  if [[ -n $INSTALL_START_TIME ]]; then
    local elapsed=$(($(date +%s) - INSTALL_START_TIME))
    log "METRIC: ${step}_completed elapsed=${elapsed}s"
  fi
}

# Log final installation metrics summary
metrics_finish() {
  if [[ -n $INSTALL_START_TIME ]]; then
    local total=$(($(date +%s) - INSTALL_START_TIME))
    local minutes=$((total / 60))
    local seconds=$((total % 60))
    log "METRIC: installation_completed total_time=${total}s (${minutes}m ${seconds}s)"
  fi
}
