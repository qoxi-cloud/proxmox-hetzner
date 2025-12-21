# shellcheck shell=bash
# shellcheck disable=SC2034
# =============================================================================
# Shared mocks for configure script tests
# =============================================================================

# Mock result controls - set these in your tests
MOCK_RUN_REMOTE_RESULT=0
MOCK_REMOTE_EXEC_RESULT=0
MOCK_REMOTE_COPY_RESULT=0
MOCK_APPLY_TEMPLATE_VARS_RESULT=0

# =============================================================================
# Common variables used by configure scripts
# =============================================================================
ADMIN_USERNAME="testadmin"

# =============================================================================
# Logging mocks
# =============================================================================
log() { :; }

# =============================================================================
# Display mocks
# =============================================================================
print_warning() { :; }
print_error() { :; }
print_info() { :; }
print_success() { :; }

# =============================================================================
# Remote execution mocks
# =============================================================================
remote_run() {
  return "$MOCK_REMOTE_RUN_RESULT"
}

remote_exec() {
  return "$MOCK_REMOTE_EXEC_RESULT"
}

remote_copy() {
  return "$MOCK_REMOTE_COPY_RESULT"
}

remote_enable_services() {
  return "$MOCK_REMOTE_EXEC_RESULT"
}

# =============================================================================
# Template mocks
# =============================================================================
apply_template_vars() {
  return "$MOCK_APPLY_TEMPLATE_VARS_RESULT"
}

deploy_template() {
  return "$MOCK_REMOTE_COPY_RESULT"
}

deploy_systemd_service() {
  return "$MOCK_REMOTE_COPY_RESULT"
}

deploy_timer() {
  return "$MOCK_REMOTE_COPY_RESULT"
}

deploy_systemd_timer() {
  return "$MOCK_REMOTE_COPY_RESULT"
}

# =============================================================================
# Parallel execution mocks
# =============================================================================
parallel_mark_configured() {
  : # no-op in tests
}

# =============================================================================
# Progress mocks
# =============================================================================
show_progress() {
  local pid="$1"
  wait "$pid" 2>/dev/null
  return $?
}

run_with_progress() {
  local func="${3:-}"
  if [[ -n $func ]] && declare -F "$func" &>/dev/null; then
    "$func"
    return $?
  fi
  return 0
}
