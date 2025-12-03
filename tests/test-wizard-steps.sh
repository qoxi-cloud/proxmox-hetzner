#!/usr/bin/env bash
# =============================================================================
# Unit tests for wizard step implementations (11-wizard-steps.sh)
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
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/11-wizard-steps.sh"

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

# =============================================================================
# Configuration array tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing wizard configuration arrays ===${NC}"

test_timezones_array() {
    [[ ${#WIZ_TIMEZONES[@]} -gt 0 ]]
}

assert_true "WIZ_TIMEZONES array is populated" test_timezones_array

test_timezones_contains_utc() {
    local found=false
    for tz in "${WIZ_TIMEZONES[@]}"; do
        [[ "$tz" == "UTC" ]] && found=true && break
    done
    $found
}

assert_true "WIZ_TIMEZONES contains UTC" test_timezones_contains_utc

test_bridge_modes_arrays_match() {
    [[ ${#WIZ_BRIDGE_MODES[@]} -eq ${#WIZ_BRIDGE_LABELS[@]} ]]
}

assert_true "WIZ_BRIDGE_MODES and WIZ_BRIDGE_LABELS have same length" test_bridge_modes_arrays_match

test_bridge_modes_content() {
    local found_internal=false
    local found_external=false
    local found_both=false
    for mode in "${WIZ_BRIDGE_MODES[@]}"; do
        [[ "$mode" == "internal" ]] && found_internal=true
        [[ "$mode" == "external" ]] && found_external=true
        [[ "$mode" == "both" ]] && found_both=true
    done
    $found_internal && $found_external && $found_both
}

assert_true "WIZ_BRIDGE_MODES contains all expected modes" test_bridge_modes_content

test_subnets_array() {
    [[ ${#WIZ_SUBNETS[@]} -ge 3 ]]
}

assert_true "WIZ_SUBNETS array has at least 3 options" test_subnets_array

test_subnets_format() {
    local all_valid=true
    for subnet in "${WIZ_SUBNETS[@]}"; do
        if [[ ! "$subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            all_valid=false
            break
        fi
    done
    $all_valid
}

assert_true "WIZ_SUBNETS entries are in CIDR format" test_subnets_format

test_ipv6_modes_arrays_match() {
    [[ ${#WIZ_IPV6_MODES[@]} -eq ${#WIZ_IPV6_LABELS[@]} ]]
}

assert_true "WIZ_IPV6_MODES and WIZ_IPV6_LABELS have same length" test_ipv6_modes_arrays_match

test_ipv6_modes_content() {
    local found_auto=false
    local found_manual=false
    local found_disabled=false
    for mode in "${WIZ_IPV6_MODES[@]}"; do
        [[ "$mode" == "auto" ]] && found_auto=true
        [[ "$mode" == "manual" ]] && found_manual=true
        [[ "$mode" == "disabled" ]] && found_disabled=true
    done
    $found_auto && $found_manual && $found_disabled
}

assert_true "WIZ_IPV6_MODES contains all expected modes" test_ipv6_modes_content

test_zfs_modes_arrays_match() {
    [[ ${#WIZ_ZFS_MODES[@]} -eq ${#WIZ_ZFS_LABELS[@]} ]]
}

assert_true "WIZ_ZFS_MODES and WIZ_ZFS_LABELS have same length" test_zfs_modes_arrays_match

test_zfs_modes_content() {
    local found_raid1=false
    local found_raid0=false
    local found_single=false
    for mode in "${WIZ_ZFS_MODES[@]}"; do
        [[ "$mode" == "raid1" ]] && found_raid1=true
        [[ "$mode" == "raid0" ]] && found_raid0=true
        [[ "$mode" == "single" ]] && found_single=true
    done
    $found_raid1 && $found_raid0 && $found_single
}

assert_true "WIZ_ZFS_MODES contains all expected modes" test_zfs_modes_content

test_repo_types_arrays_match() {
    [[ ${#WIZ_REPO_TYPES[@]} -eq ${#WIZ_REPO_LABELS[@]} ]]
}

assert_true "WIZ_REPO_TYPES and WIZ_REPO_LABELS have same length" test_repo_types_arrays_match

test_repo_types_content() {
    local found_nosub=false
    local found_ent=false
    local found_test=false
    for type in "${WIZ_REPO_TYPES[@]}"; do
        [[ "$type" == "no-subscription" ]] && found_nosub=true
        [[ "$type" == "enterprise" ]] && found_ent=true
        [[ "$type" == "test" ]] && found_test=true
    done
    $found_nosub && $found_ent && $found_test
}

assert_true "WIZ_REPO_TYPES contains all expected types" test_repo_types_content

test_ssl_types_arrays_match() {
    [[ ${#WIZ_SSL_TYPES[@]} -eq ${#WIZ_SSL_LABELS[@]} ]]
}

assert_true "WIZ_SSL_TYPES and WIZ_SSL_LABELS have same length" test_ssl_types_arrays_match

test_ssl_types_content() {
    local found_self=false
    local found_le=false
    for type in "${WIZ_SSL_TYPES[@]}"; do
        [[ "$type" == "self-signed" ]] && found_self=true
        [[ "$type" == "letsencrypt" ]] && found_le=true
    done
    $found_self && $found_le
}

assert_true "WIZ_SSL_TYPES contains all expected types" test_ssl_types_content

test_governors_array() {
    [[ ${#WIZ_GOVERNORS[@]} -ge 5 ]]
}

assert_true "WIZ_GOVERNORS array has at least 5 options" test_governors_array

test_governors_content() {
    local found_perf=false
    local found_ondemand=false
    for gov in "${WIZ_GOVERNORS[@]}"; do
        [[ "$gov" == "performance" ]] && found_perf=true
        [[ "$gov" == "ondemand" ]] && found_ondemand=true
    done
    $found_perf && $found_ondemand
}

assert_true "WIZ_GOVERNORS contains expected governors" test_governors_content

# =============================================================================
# Function existence tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing step function existence ===${NC}"

test_function_exists_step_system() {
    declare -F _wiz_step_system > /dev/null
}

assert_true "_wiz_step_system function exists" test_function_exists_step_system

test_function_exists_step_network() {
    declare -F _wiz_step_network > /dev/null
}

assert_true "_wiz_step_network function exists" test_function_exists_step_network

test_function_exists_step_storage() {
    declare -F _wiz_step_storage > /dev/null
}

assert_true "_wiz_step_storage function exists" test_function_exists_step_storage

test_function_exists_step_security() {
    declare -F _wiz_step_security > /dev/null
}

assert_true "_wiz_step_security function exists" test_function_exists_step_security

test_function_exists_step_features() {
    declare -F _wiz_step_features > /dev/null
}

assert_true "_wiz_step_features function exists" test_function_exists_step_features

test_function_exists_step_tailscale() {
    declare -F _wiz_step_tailscale > /dev/null
}

assert_true "_wiz_step_tailscale function exists" test_function_exists_step_tailscale

# =============================================================================
# Edge case tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing edge cases ===${NC}"

test_empty_timezone_in_array() {
    local has_empty=false
    for tz in "${WIZ_TIMEZONES[@]}"; do
        [[ -z "$tz" ]] && has_empty=true && break
    done
    ! $has_empty
}

assert_true "WIZ_TIMEZONES has no empty entries" test_empty_timezone_in_array

test_duplicate_bridge_modes() {
    local -A seen
    local has_dup=false
    for mode in "${WIZ_BRIDGE_MODES[@]}"; do
        [[ -n "${seen[$mode]:-}" ]] && has_dup=true && break
        seen[$mode]=1
    done
    ! $has_dup
}

assert_true "WIZ_BRIDGE_MODES has no duplicates" test_duplicate_bridge_modes

test_subnet_uniqueness() {
    local -A seen
    local has_dup=false
    for subnet in "${WIZ_SUBNETS[@]}"; do
        [[ -n "${seen[$subnet]:-}" ]] && has_dup=true && break
        seen[$subnet]=1
    done
    ! $has_dup
}

assert_true "WIZ_SUBNETS has no duplicates" test_subnet_uniqueness

test_governor_uniqueness() {
    local -A seen
    local has_dup=false
    for gov in "${WIZ_GOVERNORS[@]}"; do
        [[ -n "${seen[$gov]:-}" ]] && has_dup=true && break
        seen[$gov]=1
    done
    ! $has_dup
}

assert_true "WIZ_GOVERNORS has no duplicates" test_governor_uniqueness

# =============================================================================
# Array consistency tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing array consistency ===${NC}"

test_all_mode_label_pairs_consistent() {
    local all_consistent=true
    
    # Check each mode/label pair
    [[ ${#WIZ_BRIDGE_MODES[@]} -ne ${#WIZ_BRIDGE_LABELS[@]} ]] && all_consistent=false
    [[ ${#WIZ_IPV6_MODES[@]} -ne ${#WIZ_IPV6_LABELS[@]} ]] && all_consistent=false
    [[ ${#WIZ_ZFS_MODES[@]} -ne ${#WIZ_ZFS_LABELS[@]} ]] && all_consistent=false
    [[ ${#WIZ_REPO_TYPES[@]} -ne ${#WIZ_REPO_LABELS[@]} ]] && all_consistent=false
    [[ ${#WIZ_SSL_TYPES[@]} -ne ${#WIZ_SSL_LABELS[@]} ]] && all_consistent=false
    
    $all_consistent
}

assert_true "all mode/label array pairs are consistent" test_all_mode_label_pairs_consistent

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