# shellcheck shell=bash
# shellcheck disable=SC2034
# =============================================================================
# Mocks for 200-packages.sh tests
# =============================================================================
#
# Usage in spec files:
#   %const SUPPORT_DIR: "${SHELLSPEC_PROJECT_ROOT}/spec/support"
#   eval "$(cat "$SUPPORT_DIR/packages_mocks.sh")"
#   BeforeEach 'reset_packages_mocks'

# =============================================================================
# Mock control variables
# =============================================================================
MOCK_CURL_RESULT=0
MOCK_APT_RESULT=0
MOCK_WAIT_SEQUENCE=()
_MOCK_WAIT_INDEX=0

# =============================================================================
# Reset mock state
# =============================================================================
reset_packages_mocks() {
  MOCK_CURL_RESULT=0
  MOCK_APT_RESULT=0
  MOCK_WAIT_SEQUENCE=()
  _MOCK_WAIT_INDEX=0
  LOG_FILE="/tmp/test-packages.log"
}

# =============================================================================
# curl mock
# =============================================================================
curl() {
  return "$MOCK_CURL_RESULT"
}

# =============================================================================
# apt mock
# =============================================================================
apt() {
  return "$MOCK_APT_RESULT"
}

# =============================================================================
# show_progress mock - silently wait
# =============================================================================
show_progress() {
  return 0
}

# =============================================================================
# wait mock - returns from sequence or 0
# =============================================================================
mock_wait() {
  if [[ ${#MOCK_WAIT_SEQUENCE[@]} -gt 0 ]]; then
    local result="${MOCK_WAIT_SEQUENCE[$_MOCK_WAIT_INDEX]:-0}"
    _MOCK_WAIT_INDEX=$((_MOCK_WAIT_INDEX + 1))
    return "$result"
  fi
  return 0
}

# =============================================================================
# live_log_subtask mock
# =============================================================================
MOCK_SUBTASK_CALLS=()
live_log_subtask() {
  MOCK_SUBTASK_CALLS+=("$1")
}

# =============================================================================
# type mock for live_log_subtask detection
# =============================================================================
# Note: Override type() in test if needed to control availability

# =============================================================================
# Apply packages mocks
# =============================================================================
apply_packages_mocks() {
  wait() { mock_wait "$@"; }
  export -f wait 2>/dev/null || true
}

