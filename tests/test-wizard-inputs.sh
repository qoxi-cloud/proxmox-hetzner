#!/usr/bin/env bash
# =============================================================================
# Unit tests for wizard input functions (09-wizard-inputs.sh)
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

# Source dependencies
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/08-wizard-core.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/09-wizard-inputs.sh"

# Test helper functions
assert_true() {
    local description="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$@" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $description"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_false() {
    local description="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! "$@" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $description"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

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
# Navigation handling tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing wiz_wait_nav function ===${NC}"

test_wait_nav_next() {
    # Simulate Enter key
    local result
    result=$(printf '\n' | wiz_wait_nav)
    [[ "$result" == "next" ]]
}

assert_true "wiz_wait_nav returns 'next' on Enter" test_wait_nav_next

test_wait_nav_back() {
    # Simulate 'b' key
    local result
    result=$(printf 'b' | wiz_wait_nav)
    [[ "$result" == "back" ]]
}

assert_true "wiz_wait_nav returns 'back' on 'b'" test_wait_nav_back

test_wait_nav_back_uppercase() {
    # Simulate 'B' key
    local result
    result=$(printf 'B' | wiz_wait_nav)
    [[ "$result" == "back" ]]
}

assert_true "wiz_wait_nav returns 'back' on 'B'" test_wait_nav_back_uppercase

test_wait_nav_quit() {
    # Simulate 'q' key
    local result
    result=$(printf 'q' | wiz_wait_nav)
    [[ "$result" == "quit" ]]
}

assert_true "wiz_wait_nav returns 'quit' on 'q'" test_wait_nav_quit

test_wait_nav_quit_uppercase() {
    # Simulate 'Q' key
    local result
    result=$(printf 'Q' | wiz_wait_nav)
    [[ "$result" == "quit" ]]
}

assert_true "wiz_wait_nav returns 'quit' on 'Q'" test_wait_nav_quit_uppercase

# =============================================================================
# Message type tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing wiz_msg function ===${NC}"

# Mock gum for testing
gum() {
    local cmd="$1"
    shift
    case "$cmd" in
        style)
            # Extract the text argument (last non-option)
            local text=""
            while [[ $# -gt 0 ]]; do
                if [[ "$1" != --* ]]; then
                    text="$1"
                fi
                shift
            done
            echo "$text"
            ;;
    esac
}

test_msg_error() {
    local output
    output=$(wiz_msg "error" "Test error message")
    [[ "$output" == *"Test error message"* ]] && [[ "$output" == *"✗"* ]]
}

assert_true "wiz_msg displays error message" test_msg_error

test_msg_warning() {
    local output
    output=$(wiz_msg "warning" "Test warning")
    [[ "$output" == *"Test warning"* ]] && [[ "$output" == *"⚠"* ]]
}

assert_true "wiz_msg displays warning message" test_msg_warning

test_msg_success() {
    local output
    output=$(wiz_msg "success" "Test success")
    [[ "$output" == *"Test success"* ]] && [[ "$output" == *"✓"* ]]
}

assert_true "wiz_msg displays success message" test_msg_success

test_msg_info() {
    local output
    output=$(wiz_msg "info" "Test info")
    [[ "$output" == *"Test info"* ]] && [[ "$output" == *"ℹ"* ]]
}

assert_true "wiz_msg displays info message" test_msg_info

test_msg_unknown_type() {
    local output
    output=$(wiz_msg "unknown" "Test message")
    [[ "$output" == *"Test message"* ]] && [[ "$output" == *"•"* ]]
}

assert_true "wiz_msg handles unknown type with default icon" test_msg_unknown_type

# =============================================================================
# Edge case tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing edge cases ===${NC}"

test_msg_empty_message() {
    local output
    output=$(wiz_msg "info" "")
    [[ -n "$output" ]]
}

assert_true "wiz_msg handles empty message" test_msg_empty_message

test_msg_long_message() {
    local long_msg
    long_msg=$(printf 'A%.0s' {1..200})
    local output
    output=$(wiz_msg "info" "$long_msg")
    [[ "$output" == *"$long_msg"* ]]
}

assert_true "wiz_msg handles long messages" test_msg_long_message

test_msg_special_chars() {
    local output
    output=$(wiz_msg "error" "Test & < > | $ @ # message")
    [[ "$output" == *"&"* ]] && [[ "$output" == *"$"* ]]
}

assert_true "wiz_msg handles special characters" test_msg_special_chars

test_msg_newlines() {
    local output
    output=$(wiz_msg "info" "Line1"$'\n'"Line2")
    [[ "$output" == *"Line1"* ]]
}

assert_true "wiz_msg handles newlines in text" test_msg_newlines

# =============================================================================
# Function existence tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing function existence ===${NC}"

test_function_exists_input() {
    declare -F wiz_input > /dev/null
}

assert_true "wiz_input function exists" test_function_exists_input

test_function_exists_choose() {
    declare -F wiz_choose > /dev/null
}

assert_true "wiz_choose function exists" test_function_exists_choose

test_function_exists_choose_multi() {
    declare -F wiz_choose_multi > /dev/null
}

assert_true "wiz_choose_multi function exists" test_function_exists_choose_multi

test_function_exists_confirm() {
    declare -F wiz_confirm > /dev/null
}

assert_true "wiz_confirm function exists" test_function_exists_confirm

test_function_exists_spin() {
    declare -F wiz_spin > /dev/null
}

assert_true "wiz_spin function exists" test_function_exists_spin

test_function_exists_handle_quit() {
    declare -F wiz_handle_quit > /dev/null
}

assert_true "wiz_handle_quit function exists" test_function_exists_handle_quit

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