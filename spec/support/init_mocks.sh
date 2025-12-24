# shellcheck shell=bash
# shellcheck disable=SC2034
# =============================================================================
# Mocks for 000-init.sh tests
# =============================================================================
#
# Usage in spec files:
#   %const SUPPORT_DIR: "${SHELLSPEC_PROJECT_ROOT}/spec/support"
#   eval "$(cat "$SUPPORT_DIR/init_mocks.sh")"

# =============================================================================
# Side-effect prevention
# =============================================================================
# These mocks prevent 000-init.sh from causing side effects during sourcing

# Prevent cd to /root (fails in test environment)
cd() { :; }

# Prevent trap handler registration during tests
trap() { :; }

# Silent logging (log function may not exist yet during init)
log() { :; }

# =============================================================================
# Test helper: reset temp file registry
# =============================================================================
reset_temp_files() {
  _TEMP_FILES=()
}

# =============================================================================
# Test helper: mock secure_delete_file
# =============================================================================
secure_delete_file() {
  rm -f "$1" 2>/dev/null || true
}

# =============================================================================
# Test helper: mock find for cleanup
# =============================================================================
mock_find_noop() {
  :
}

