# shellcheck shell=bash
# shellcheck disable=SC2034
# =============================================================================
# Shared mocks for configure script tests
# =============================================================================
#
# Usage in spec files:
#   %const SUPPORT_DIR: "${SHELLSPEC_PROJECT_ROOT}/spec/support"
#   eval "$(cat "$SUPPORT_DIR/configure_mocks.sh")"

# =============================================================================
# Mock result controls - set these in your tests
# =============================================================================
MOCK_REMOTE_RUN_RESULT=0
MOCK_REMOTE_EXEC_RESULT=0
MOCK_REMOTE_EXEC_OUTPUT=""
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
add_log() { :; }

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
  # Output mock data if configured (visible in subshells via variable inheritance)
  [[ -n $MOCK_REMOTE_EXEC_OUTPUT ]] && echo "$MOCK_REMOTE_EXEC_OUTPUT"
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

deploy_user_config() {
  return "$MOCK_REMOTE_COPY_RESULT"
}

# =============================================================================
# Parallel execution mocks
# =============================================================================
parallel_mark_configured() {
  : # no-op in tests
}

# =============================================================================
# Package installation mocks
# =============================================================================
install_base_packages() { :; }
batch_install_packages() { :; }

# =============================================================================
# Color constants (used by some configure scripts)
# =============================================================================
CLR_RED=''
CLR_CYAN=''
CLR_YELLOW=''
CLR_ORANGE=''
CLR_GRAY=''
CLR_GOLD=''
CLR_RESET=''

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

# =============================================================================
# Feature wrapper factory (real implementation for tests)
# =============================================================================
# shellcheck disable=SC2086,SC2154
make_feature_wrapper() {
  local feature="$1"
  local flag_var="$2"
  eval "configure_${feature}() { [[ \${${flag_var}:-} != \"yes\" ]] && return 0; _config_${feature}; }"
}
