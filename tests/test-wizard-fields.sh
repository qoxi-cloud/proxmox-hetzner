#!/usr/bin/env bash
# =============================================================================
# Unit tests for wizard field management (10-wizard-fields.sh)
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
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/10-wizard-fields.sh"

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
# Field array initialization tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing field array declarations ===${NC}"

test_field_arrays_exist() {
    [[ -v WIZ_FIELD_LABELS ]] && \
    [[ -v WIZ_FIELD_VALUES ]] && \
    [[ -v WIZ_FIELD_TYPES ]] && \
    [[ -v WIZ_FIELD_OPTIONS ]] && \
    [[ -v WIZ_FIELD_DEFAULTS ]] && \
    [[ -v WIZ_FIELD_VALIDATORS ]] && \
    [[ -v WIZ_CURRENT_FIELD ]]
}

assert_true "field arrays are declared" test_field_arrays_exist

# =============================================================================
# Clear fields tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing _wiz_clear_fields function ===${NC}"

test_clear_fields_basic() {
    # Populate arrays
    WIZ_FIELD_LABELS=("Test1" "Test2")
    WIZ_FIELD_VALUES=("val1" "val2")
    WIZ_FIELD_TYPES=("input" "choose")
    WIZ_FIELD_OPTIONS=("" "opt1|opt2")
    WIZ_FIELD_DEFAULTS=("def1" "")
    WIZ_FIELD_VALIDATORS=("" "")
    WIZ_CURRENT_FIELD=5
    
    # Clear
    _wiz_clear_fields
    
    # Verify all empty
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 0 ]] && \
    [[ ${#WIZ_FIELD_VALUES[@]} -eq 0 ]] && \
    [[ ${#WIZ_FIELD_TYPES[@]} -eq 0 ]] && \
    [[ ${#WIZ_FIELD_OPTIONS[@]} -eq 0 ]] && \
    [[ ${#WIZ_FIELD_DEFAULTS[@]} -eq 0 ]] && \
    [[ ${#WIZ_FIELD_VALIDATORS[@]} -eq 0 ]] && \
    [[ $WIZ_CURRENT_FIELD -eq 0 ]]
}

assert_true "_wiz_clear_fields clears all arrays" test_clear_fields_basic

test_clear_fields_multiple_calls() {
    _wiz_clear_fields
    _wiz_clear_fields
    _wiz_clear_fields
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 0 ]]
}

assert_true "_wiz_clear_fields can be called multiple times" test_clear_fields_multiple_calls

# =============================================================================
# Add field tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing _wiz_add_field function ===${NC}"

test_add_field_input() {
    _wiz_clear_fields
    _wiz_add_field "Hostname" "input" "default-host"
    
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 1 ]] && \
    [[ "${WIZ_FIELD_LABELS[0]}" == "Hostname" ]] && \
    [[ "${WIZ_FIELD_TYPES[0]}" == "input" ]] && \
    [[ "${WIZ_FIELD_DEFAULTS[0]}" == "default-host" ]] && \
    [[ "${WIZ_FIELD_VALUES[0]}" == "" ]]
}

assert_true "_wiz_add_field adds input field correctly" test_add_field_input

test_add_field_password() {
    _wiz_clear_fields
    _wiz_add_field "Password" "password" ""
    
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 1 ]] && \
    [[ "${WIZ_FIELD_LABELS[0]}" == "Password" ]] && \
    [[ "${WIZ_FIELD_TYPES[0]}" == "password" ]]
}

assert_true "_wiz_add_field adds password field correctly" test_add_field_password

test_add_field_choose() {
    _wiz_clear_fields
    _wiz_add_field "Bridge Mode" "choose" "internal|external|both"
    
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 1 ]] && \
    [[ "${WIZ_FIELD_LABELS[0]}" == "Bridge Mode" ]] && \
    [[ "${WIZ_FIELD_TYPES[0]}" == "choose" ]] && \
    [[ "${WIZ_FIELD_OPTIONS[0]}" == "internal|external|both" ]]
}

assert_true "_wiz_add_field adds choose field correctly" test_add_field_choose

test_add_field_multi() {
    _wiz_clear_fields
    _wiz_add_field "Features" "multi" "feat1|feat2|feat3"
    
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 1 ]] && \
    [[ "${WIZ_FIELD_TYPES[0]}" == "multi" ]] && \
    [[ "${WIZ_FIELD_OPTIONS[0]}" == "feat1|feat2|feat3" ]]
}

assert_true "_wiz_add_field adds multi field correctly" test_add_field_multi

test_add_field_with_validator() {
    _wiz_clear_fields
    _wiz_add_field "Email" "input" "user@example.com" "validate_email"
    
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 1 ]] && \
    [[ "${WIZ_FIELD_VALIDATORS[0]}" == "validate_email" ]]
}

assert_true "_wiz_add_field adds field with validator" test_add_field_with_validator

test_add_multiple_fields() {
    _wiz_clear_fields
    _wiz_add_field "Field1" "input" "default1"
    _wiz_add_field "Field2" "choose" "opt1|opt2"
    _wiz_add_field "Field3" "password" ""
    
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 3 ]] && \
    [[ "${WIZ_FIELD_LABELS[0]}" == "Field1" ]] && \
    [[ "${WIZ_FIELD_LABELS[1]}" == "Field2" ]] && \
    [[ "${WIZ_FIELD_LABELS[2]}" == "Field3" ]]
}

assert_true "_wiz_add_field handles multiple fields" test_add_multiple_fields

# =============================================================================
# Build fields content tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing _wiz_build_fields_content function ===${NC}"

# Mock gum for testing
gum() {
    echo "$@" | grep -o '[^-][^ ]*$' | tail -1
}

test_build_fields_content_empty() {
    _wiz_clear_fields
    local content
    content=$(_wiz_build_fields_content -1 -1 "")
    [[ -z "$content" ]]
}

assert_true "_wiz_build_fields_content handles empty fields" test_build_fields_content_empty

test_build_fields_content_with_values() {
    _wiz_clear_fields
    _wiz_add_field "Field1" "input" "default"
    _wiz_add_field "Field2" "input" "default"
    WIZ_FIELD_VALUES[0]="value1"
    
    local content
    content=$(_wiz_build_fields_content -1 -1 "")
    [[ -n "$content" ]]
}

assert_true "_wiz_build_fields_content generates content" test_build_fields_content_with_values

test_build_fields_content_cursor() {
    _wiz_clear_fields
    _wiz_add_field "Field1" "input" ""
    _wiz_add_field "Field2" "input" ""
    WIZ_FIELD_VALUES[0]="value1"
    
    local content
    content=$(_wiz_build_fields_content 1 -1 "")
    [[ -n "$content" ]]
}

assert_true "_wiz_build_fields_content shows cursor" test_build_fields_content_cursor

test_build_fields_content_password_masking() {
    _wiz_clear_fields
    _wiz_add_field "Password" "password" ""
    WIZ_FIELD_VALUES[0]="secret123"
    
    local content
    content=$(_wiz_build_fields_content -1 -1 "")
    [[ "$content" != *"secret123"* ]]
}

assert_true "_wiz_build_fields_content masks password fields" test_build_fields_content_password_masking

# =============================================================================
# Edge case tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing edge cases ===${NC}"

test_add_field_empty_label() {
    _wiz_clear_fields
    _wiz_add_field "" "input" "default"
    [[ ${#WIZ_FIELD_LABELS[@]} -eq 1 ]] && [[ "${WIZ_FIELD_LABELS[0]}" == "" ]]
}

assert_true "_wiz_add_field handles empty label" test_add_field_empty_label

test_add_field_special_chars() {
    _wiz_clear_fields
    _wiz_add_field "Test & Field <>" "input" "value@test"
    [[ "${WIZ_FIELD_LABELS[0]}" == "Test & Field <>" ]] && \
    [[ "${WIZ_FIELD_DEFAULTS[0]}" == "value@test" ]]
}

assert_true "_wiz_add_field handles special characters" test_add_field_special_chars

test_add_field_long_options() {
    _wiz_clear_fields
    local long_opts=""
    for i in {1..50}; do
        [[ -n "$long_opts" ]] && long_opts+="|"
        long_opts+="option$i"
    done
    _wiz_add_field "Many Options" "choose" "$long_opts"
    [[ "${WIZ_FIELD_OPTIONS[0]}" == "$long_opts" ]]
}

assert_true "_wiz_add_field handles many options" test_add_field_long_options

test_field_arrays_sync() {
    _wiz_clear_fields
    _wiz_add_field "F1" "input" "d1"
    _wiz_add_field "F2" "choose" "o1|o2"
    _wiz_add_field "F3" "password" ""
    
    local len1=${#WIZ_FIELD_LABELS[@]}
    local len2=${#WIZ_FIELD_VALUES[@]}
    local len3=${#WIZ_FIELD_TYPES[@]}
    local len4=${#WIZ_FIELD_OPTIONS[@]}
    local len5=${#WIZ_FIELD_DEFAULTS[@]}
    local len6=${#WIZ_FIELD_VALIDATORS[@]}
    
    [[ $len1 -eq 3 ]] && [[ $len1 -eq $len2 ]] && [[ $len2 -eq $len3 ]] && \
    [[ $len3 -eq $len4 ]] && [[ $len4 -eq $len5 ]] && [[ $len5 -eq $len6 ]]
}

assert_true "field arrays remain synchronized" test_field_arrays_sync

# =============================================================================
# Function existence tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing function existence ===${NC}"

test_function_exists_edit_field_select() {
    declare -F _wiz_edit_field_select > /dev/null
}

assert_true "_wiz_edit_field_select function exists" test_function_exists_edit_field_select

test_function_exists_step_interactive() {
    declare -F wiz_step_interactive > /dev/null
}

assert_true "wiz_step_interactive function exists" test_function_exists_step_interactive

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