#!/usr/bin/env bash
# =============================================================================
# Unit tests for SSH functions (07-ssh.sh)
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

# Extract only the functions we can test without full environment
eval "$(sed -n '/^validate_ssh_key()/,/^}/p' "$SCRIPT_DIR/scripts/07-ssh.sh")"
eval "$(sed -n '/^parse_ssh_key()/,/^}/p' "$SCRIPT_DIR/scripts/07-ssh.sh")"

# Test helper functions
assert_true() {
    local description="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$@"; then
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
    if ! "$@"; then
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

assert_not_empty() {
    local description="$1"
    local actual="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -n "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $description (expected non-empty value)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# =============================================================================
# validate_ssh_key tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_ssh_key ===${NC}"

# Valid keys
assert_true "valid ssh-rsa key" validate_ssh_key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... user@host"
assert_true "valid ssh-ed25519 key" validate_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@host"
assert_true "valid ssh-ecdsa key" validate_ssh_key "ssh-ecdsa AAAAE2VjZHNhLXNoYTItbmlzdHAy... user@host"
assert_true "valid key without comment" validate_ssh_key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ..."

# Invalid keys
assert_false "invalid: empty string" validate_ssh_key ""
assert_false "invalid: random text" validate_ssh_key "not a valid key"
assert_false "invalid: missing prefix" validate_ssh_key "AAAAB3NzaC1yc2EAAAADAQABAAACAQ..."
assert_false "invalid: wrong prefix" validate_ssh_key "ssh-dsa AAAAB3..."

# =============================================================================
# parse_ssh_key tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing parse_ssh_key ===${NC}"

# Test with full key
parse_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHk7rJsQxRasYkHY user@laptop"
assert_equals "parse type: ssh-ed25519" "ssh-ed25519" "$SSH_KEY_TYPE"
assert_equals "parse data" "AAAAC3NzaC1lZDI1NTE5AAAAIHk7rJsQxRasYkHY" "$SSH_KEY_DATA"
assert_equals "parse comment" "user@laptop" "$SSH_KEY_COMMENT"

# Test without comment
parse_ssh_key "ssh-rsa AAAAB3NzaC1yc2EAAA"
assert_equals "parse type without comment" "ssh-rsa" "$SSH_KEY_TYPE"
assert_equals "parse data without comment" "AAAAB3NzaC1yc2EAAA" "$SSH_KEY_DATA"
assert_equals "parse empty comment" "" "$SSH_KEY_COMMENT"

# Test short key display
parse_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHk7rJsQxRasYkHYtest1234567890 user"
assert_not_empty "short key is set" "$SSH_KEY_SHORT"

# Test empty key (parse_ssh_key returns 1 for empty, so use || true)
parse_ssh_key "" || true
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -z "$SSH_KEY_TYPE" ]]; then
    echo -e "${GREEN}✓${NC} parse empty key returns empty type"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} parse empty key should return empty type"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

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
