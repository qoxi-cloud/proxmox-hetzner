#!/usr/bin/env bash
# =============================================================================
# Unit tests for utility functions (06-utils.sh)
# =============================================================================

set -euo pipefail

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Source required scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Mock dependencies
CLR_RED='\033[0;31m'
CLR_CYAN='\033[0;36m'
CLR_RESET='\033[0m'
LOG_FILE="/tmp/pve-test.log"

# Mock functions
log() { echo "$*" >> "$LOG_FILE"; }
print_error() { echo -e "${CLR_RED}✗${CLR_RESET} $1"; }

# Extract only the functions we need to test (avoid dependencies)
eval "$(sed -n '/^format_duration()/,/^}/p' "$SCRIPT_DIR/scripts/06-utils.sh")"

# Test helper functions
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $description (expected: '$expected', got: '$actual')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# =============================================================================
# format_duration tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing format_duration ===${NC}"

assert_equals "format 0 seconds" "0m 0s" "$(format_duration 0)"
assert_equals "format 30 seconds" "0m 30s" "$(format_duration 30)"
assert_equals "format 60 seconds" "1m 0s" "$(format_duration 60)"
assert_equals "format 90 seconds" "1m 30s" "$(format_duration 90)"
assert_equals "format 3600 seconds (1 hour)" "1h 0m 0s" "$(format_duration 3600)"
assert_equals "format 3661 seconds" "1h 1m 1s" "$(format_duration 3661)"
assert_equals "format 7325 seconds" "2h 2m 5s" "$(format_duration 7325)"

# Note: apply_template_vars tests skipped - uses sed -i which differs on macOS/Linux

# =============================================================================
# Summary
# =============================================================================
echo -e "\n${YELLOW}=== Test Summary ===${NC}"
echo "Tests run: $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
