#!/usr/bin/env bash
# =============================================================================
# Unit tests for wizard core functions (08-wizard-core.sh)
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

# Source the wizard core functions
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/08-wizard-core.sh"

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

assert_contains() {
    local description="$1"
    local needle="$2"
    local haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $description (expected to contain: '$needle')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_not_empty() {
    local description="$1"
    local value="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -n "$value" ]]; then
        echo -e "${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $description (value is empty)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# =============================================================================
# Configuration constants tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing wizard configuration constants ===${NC}"

assert_equals "WIZARD_WIDTH is set correctly" "60" "$WIZARD_WIDTH"
assert_equals "WIZARD_TOTAL_STEPS is set correctly" "6" "$WIZARD_TOTAL_STEPS"

# =============================================================================
# Color configuration tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing color configuration ===${NC}"

assert_equals "GUM_PRIMARY is hex color" "#00B1FF" "$GUM_PRIMARY"
assert_equals "GUM_ACCENT is hex color" "#FF8700" "$GUM_ACCENT"
assert_equals "GUM_SUCCESS is hex color" "#55FF55" "$GUM_SUCCESS"
assert_equals "GUM_WARNING is hex color" "#FFFF55" "$GUM_WARNING"
assert_equals "GUM_ERROR is hex color" "#FF5555" "$GUM_ERROR"
assert_equals "GUM_MUTED is hex color" "#585858" "$GUM_MUTED"
assert_equals "GUM_BORDER is hex color" "#444444" "$GUM_BORDER"
assert_equals "GUM_HETZNER is hex color" "#D70000" "$GUM_HETZNER"

assert_not_empty "ANSI_PRIMARY is set" "$ANSI_PRIMARY"
assert_not_empty "ANSI_ACCENT is set" "$ANSI_ACCENT"
assert_not_empty "ANSI_SUCCESS is set" "$ANSI_SUCCESS"
assert_not_empty "ANSI_WARNING is set" "$ANSI_WARNING"
assert_not_empty "ANSI_ERROR is set" "$ANSI_ERROR"
assert_not_empty "ANSI_MUTED is set" "$ANSI_MUTED"
assert_not_empty "ANSI_HETZNER is set" "$ANSI_HETZNER"
assert_not_empty "ANSI_RESET is set" "$ANSI_RESET"

# =============================================================================
# Banner display tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing wiz_banner function ===${NC}"

test_banner_output() {
    local output
    output=$(wiz_banner)
    [[ -n "$output" ]] && [[ "$output" == *"Proxmox"* ]] && [[ "$output" == *"Hetzner"* ]]
}

assert_true "wiz_banner produces output" test_banner_output

test_banner_contains_ansi() {
    local output
    output=$(wiz_banner)
    [[ "$output" == *$'\033['* ]]
}

assert_true "wiz_banner contains ANSI codes" test_banner_contains_ansi

# =============================================================================
# Progress bar tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing _wiz_progress_bar function ===${NC}"

test_progress_bar_basic() {
    local bar
    bar=$(_wiz_progress_bar 1 2 10)
    [[ ${#bar} -eq 10 ]]
}

assert_true "_wiz_progress_bar returns correct width" test_progress_bar_basic

test_progress_bar_half() {
    local bar
    bar=$(_wiz_progress_bar 5 10 20)
    [[ "$bar" == *"█"* ]] && [[ "$bar" == *"░"* ]]
}

assert_true "_wiz_progress_bar has filled and empty sections" test_progress_bar_half

test_progress_bar_full() {
    local bar
    bar=$(_wiz_progress_bar 10 10 20)
    [[ "$bar" != *"░"* ]]
}

assert_true "_wiz_progress_bar is full when step equals total" test_progress_bar_full

test_progress_bar_empty() {
    local bar
    bar=$(_wiz_progress_bar 0 10 20)
    [[ "$bar" != *"█"* ]]
}

assert_true "_wiz_progress_bar is empty when step is zero" test_progress_bar_empty

test_progress_bar_various_widths() {
    local bar10 bar50 bar100
    bar10=$(_wiz_progress_bar 5 10 10)
    bar50=$(_wiz_progress_bar 5 10 50)
    bar100=$(_wiz_progress_bar 5 10 100)
    [[ ${#bar10} -eq 10 ]] && [[ ${#bar50} -eq 50 ]] && [[ ${#bar100} -eq 100 ]]
}

assert_true "_wiz_progress_bar handles various widths" test_progress_bar_various_widths

# =============================================================================
# Field display tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing field display functions ===${NC}"

# Mock gum for testing
gum() {
    local cmd="$1"
    shift
    case "$cmd" in
        style)
            # Extract the last argument (the text)
            while [[ $# -gt 0 ]]; do
                if [[ "$1" != --* ]]; then
                    echo "$1"
                    return
                fi
                shift
            done
            ;;
    esac
}

test_field_completed() {
    local output
    output=$(_wiz_field "Hostname" "example.com")
    [[ "$output" == *"Hostname"* ]] && [[ "$output" == *"example.com"* ]]
}

assert_true "_wiz_field displays completed field" test_field_completed

test_field_pending() {
    local output
    output=$(_wiz_field_pending "Email")
    [[ "$output" == *"Email"* ]] && [[ "$output" == *"..."* ]]
}

assert_true "_wiz_field_pending displays pending field" test_field_pending

# =============================================================================
# Content building tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing wiz_build_content function ===${NC}"

test_build_content_mixed() {
    local content
    content=$(wiz_build_content "Field1|value1" "Field2|" "Field3|value3")
    [[ "$content" == *"Field1"* ]] && [[ "$content" == *"value1"* ]] && \
    [[ "$content" == *"Field2"* ]] && [[ "$content" == *"..."* ]] && \
    [[ "$content" == *"Field3"* ]] && [[ "$content" == *"value3"* ]]
}

assert_true "wiz_build_content handles mixed complete and pending fields" test_build_content_mixed

test_build_content_empty() {
    local content
    content=$(wiz_build_content)
    [[ -z "$content" ]]
}

assert_true "wiz_build_content handles no fields" test_build_content_empty

test_build_content_single() {
    local content
    content=$(wiz_build_content "Test|value")
    [[ "$content" == *"Test"* ]] && [[ "$content" == *"value"* ]]
}

assert_true "wiz_build_content handles single field" test_build_content_single

# =============================================================================
# Section header tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing wiz_section function ===${NC}"

test_section_header() {
    local output
    output=$(wiz_section "System Configuration")
    [[ "$output" == *"System Configuration"* ]]
}

assert_true "wiz_section displays section title" test_section_header

# =============================================================================
# Edge case tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing edge cases ===${NC}"

test_progress_bar_zero_width() {
    local bar
    bar=$(_wiz_progress_bar 1 1 0)
    [[ ${#bar} -eq 0 ]]
}

assert_true "_wiz_progress_bar handles zero width" test_progress_bar_zero_width

test_progress_bar_boundary() {
    local bar1 bar2
    bar1=$(_wiz_progress_bar 1 1 10)
    bar2=$(_wiz_progress_bar 0 0 10)
    [[ -n "$bar1" ]]
}

assert_true "_wiz_progress_bar handles boundary conditions" test_progress_bar_boundary

test_field_empty_values() {
    local output
    output=$(_wiz_field "" "")
    [[ -n "$output" ]]
}

assert_true "_wiz_field handles empty strings" test_field_empty_values

test_field_special_chars() {
    local output
    output=$(_wiz_field "Test & Field" "value@example.com")
    [[ "$output" == *"Test & Field"* ]] && [[ "$output" == *"value@example.com"* ]]
}

assert_true "_wiz_field handles special characters" test_field_special_chars

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