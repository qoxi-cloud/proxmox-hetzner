#!/usr/bin/env bash
# =============================================================================
# Unit tests for validation functions (13-validation.sh)
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

# Source validation functions directly from scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/13-validation.sh"

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

# =============================================================================
# Hostname validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_hostname ===${NC}"

assert_true "valid hostname: pve01" validate_hostname "pve01"
assert_true "valid hostname: my-server" validate_hostname "my-server"
assert_true "valid hostname: a" validate_hostname "a"
assert_true "valid hostname: server123" validate_hostname "server123"
assert_true "valid hostname: A1-test-B2" validate_hostname "A1-test-B2"
assert_false "invalid hostname: -invalid" validate_hostname "-invalid"
assert_false "invalid hostname: invalid-" validate_hostname "invalid-"
assert_false "invalid hostname: has.dot" validate_hostname "has.dot"
assert_false "invalid hostname: has space" validate_hostname "has space"
assert_false "invalid hostname: empty" validate_hostname ""
assert_false "invalid hostname: too-long-hostname-with-more-than-63-characters-which-is-not-allowed-here" validate_hostname "too-long-hostname-with-more-than-63-characters-which-is-not-allowed-here"

# =============================================================================
# FQDN validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_fqdn ===${NC}"

assert_true "valid fqdn: pve01.example.com" validate_fqdn "pve01.example.com"
assert_true "valid fqdn: server.sub.domain.org" validate_fqdn "server.sub.domain.org"
assert_true "valid fqdn: a.b.c" validate_fqdn "a.b.c"
assert_true "valid fqdn: my-server.my-domain.co.uk" validate_fqdn "my-server.my-domain.co.uk"
assert_false "invalid fqdn: single-label" validate_fqdn "single-label"
assert_false "invalid fqdn: .starts.with.dot" validate_fqdn ".starts.with.dot"
assert_false "invalid fqdn: ends.with.dot." validate_fqdn "ends.with.dot."
assert_false "invalid fqdn: has..double.dots" validate_fqdn "has..double.dots"
assert_false "invalid fqdn: -starts-with-dash.com" validate_fqdn "-starts-with-dash.com"

# =============================================================================
# Email validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_email ===${NC}"

assert_true "valid email: user@example.com" validate_email "user@example.com"
assert_true "valid email: test.user+tag@sub.domain.org" validate_email "test.user+tag@sub.domain.org"
assert_true "valid email: admin@my-company.co.uk" validate_email "admin@my-company.co.uk"
assert_false "invalid email: no-at-sign" validate_email "no-at-sign"
assert_false "invalid email: @starts-with-at.com" validate_email "@starts-with-at.com"
assert_false "invalid email: missing@tld" validate_email "missing@tld"
assert_false "invalid email: empty" validate_email ""

# =============================================================================
# Password validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_password ===${NC}"

assert_true "valid password: 8+ chars" validate_password "password123"
assert_true "valid password: special chars" validate_password "P@ssw0rd!"
assert_true "valid password: exactly 8 chars" validate_password "12345678"
assert_false "invalid password: too short (7 chars)" validate_password "short12"
assert_false "invalid password: empty" validate_password ""

# Test error messages
echo -e "\n${YELLOW}=== Testing get_password_error ===${NC}"

error=$(get_password_error "")
assert_equals "error message: empty password" "Password cannot be empty!" "$error"

error=$(get_password_error "short")
assert_equals "error message: short password" "Password must be at least 8 characters long." "$error"

error=$(get_password_error "validpassword")
assert_equals "no error: valid password" "" "$error"

# =============================================================================
# ASCII printable tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing is_ascii_printable ===${NC}"

assert_true "ascii: letters and numbers" is_ascii_printable "abc123"
assert_true "ascii: special characters" is_ascii_printable "P@ss!#\$%"
assert_true "ascii: spaces" is_ascii_printable "hello world"

# =============================================================================
# Subnet validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_subnet ===${NC}"

assert_true "valid subnet: 10.0.0.0/24" validate_subnet "10.0.0.0/24"
assert_true "valid subnet: 192.168.1.0/16" validate_subnet "192.168.1.0/16"
assert_true "valid subnet: 172.16.0.0/12" validate_subnet "172.16.0.0/12"
assert_true "valid subnet: 0.0.0.0/0" validate_subnet "0.0.0.0/0"
assert_true "valid subnet: 255.255.255.255/32" validate_subnet "255.255.255.255/32"
assert_true "valid subnet: 10.10.10.10/8" validate_subnet "10.10.10.10/8"
assert_false "invalid subnet: no prefix" validate_subnet "10.0.0.0"
assert_false "invalid subnet: invalid prefix /33" validate_subnet "10.0.0.0/33"
assert_false "invalid subnet: invalid octet 256" validate_subnet "256.0.0.0/24"
assert_false "invalid subnet: missing octet" validate_subnet "10.0.0/24"
assert_false "invalid subnet: negative prefix" validate_subnet "10.0.0.0/-1"
assert_false "invalid subnet: letters" validate_subnet "abc.def.ghi.jkl/24"

# =============================================================================
# IPv6 validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_ipv6 ===${NC}"

# Valid addresses
assert_true "valid ipv6: full address" validate_ipv6 "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
assert_true "valid ipv6: compressed zeros" validate_ipv6 "2001:db8:85a3::8a2e:370:7334"
assert_true "valid ipv6: loopback" validate_ipv6 "::1"
assert_true "valid ipv6: all zeros" validate_ipv6 "::"
assert_true "valid ipv6: link-local" validate_ipv6 "fe80::1"
assert_true "valid ipv6: uppercase" validate_ipv6 "FE80::ABCD:1234"
assert_true "valid ipv6: mixed case" validate_ipv6 "Fe80::aBcD:1234"

# Invalid addresses
assert_false "invalid ipv6: empty" validate_ipv6 ""
assert_false "invalid ipv6: too many groups" validate_ipv6 "2001:db8:85a3:0:0:8a2e:370:7334:extra"
assert_false "invalid ipv6: multiple ::" validate_ipv6 "2001::db8::1"
assert_false "invalid ipv6: invalid chars" validate_ipv6 "2001:db8:85a3:xxxx::1"
assert_false "invalid ipv6: group too long (5 chars)" validate_ipv6 "2001:db8:85a3:00000::1"
assert_false "invalid ipv6: starts with single colon" validate_ipv6 ":2001:db8::1"
assert_false "invalid ipv6: ends with single colon" validate_ipv6 "2001:db8::1:"

# =============================================================================
# IPv6 CIDR validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_ipv6_cidr ===${NC}"

assert_true "valid ipv6 cidr: /64" validate_ipv6_cidr "2001:db8::1/64"
assert_true "valid ipv6 cidr: /128" validate_ipv6_cidr "::1/128"
assert_true "valid ipv6 cidr: /48" validate_ipv6_cidr "2001:db8::/48"
assert_true "valid ipv6 cidr: /0" validate_ipv6_cidr "::/0"
assert_false "invalid ipv6 cidr: no prefix" validate_ipv6_cidr "2001:db8::1"
assert_false "invalid ipv6 cidr: prefix too large /129" validate_ipv6_cidr "2001:db8::1/129"
assert_false "invalid ipv6 cidr: invalid address" validate_ipv6_cidr "invalid::addr/64"
assert_false "invalid ipv6 cidr: negative prefix" validate_ipv6_cidr "2001:db8::1/-1"

# =============================================================================
# IPv6 gateway validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_ipv6_gateway ===${NC}"

assert_true "valid ipv6 gateway: empty (no gateway)" validate_ipv6_gateway ""
assert_true "valid ipv6 gateway: auto" validate_ipv6_gateway "auto"
assert_true "valid ipv6 gateway: link-local" validate_ipv6_gateway "fe80::1"
assert_true "valid ipv6 gateway: global" validate_ipv6_gateway "2001:db8::1"
assert_false "invalid ipv6 gateway: invalid address" validate_ipv6_gateway "not-an-ipv6"
assert_false "invalid ipv6 gateway: with cidr" validate_ipv6_gateway "fe80::1/64"

# =============================================================================
# IPv6 prefix length validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_ipv6_prefix_length ===${NC}"

assert_true "valid prefix: 48" validate_ipv6_prefix_length "48"
assert_true "valid prefix: 64" validate_ipv6_prefix_length "64"
assert_true "valid prefix: 128" validate_ipv6_prefix_length "128"
assert_true "valid prefix: 80" validate_ipv6_prefix_length "80"
assert_false "invalid prefix: 47 (too small)" validate_ipv6_prefix_length "47"
assert_false "invalid prefix: 129 (too large)" validate_ipv6_prefix_length "129"
assert_false "invalid prefix: not a number" validate_ipv6_prefix_length "abc"
assert_false "invalid prefix: empty" validate_ipv6_prefix_length ""
assert_false "invalid prefix: negative" validate_ipv6_prefix_length "-1"

# =============================================================================
# IPv6 type detection tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing is_ipv6_link_local ===${NC}"

assert_true "is link-local: fe80::1" is_ipv6_link_local "fe80::1"
assert_true "is link-local: FE80::1 (uppercase)" is_ipv6_link_local "FE80::1"
assert_true "is link-local: fe80::abcd:1234:5678:9abc" is_ipv6_link_local "fe80::abcd:1234:5678:9abc"
assert_false "not link-local: 2001:db8::1" is_ipv6_link_local "2001:db8::1"
assert_false "not link-local: fd00::1 (ULA)" is_ipv6_link_local "fd00::1"

echo -e "\n${YELLOW}=== Testing is_ipv6_ula ===${NC}"

assert_true "is ULA: fd00::1" is_ipv6_ula "fd00::1"
assert_true "is ULA: fc00::1" is_ipv6_ula "fc00::1"
assert_true "is ULA: FD12:3456::1 (uppercase)" is_ipv6_ula "FD12:3456::1"
assert_false "not ULA: 2001:db8::1 (global)" is_ipv6_ula "2001:db8::1"
assert_false "not ULA: fe80::1 (link-local)" is_ipv6_ula "fe80::1"

echo -e "\n${YELLOW}=== Testing is_ipv6_global ===${NC}"

assert_true "is global: 2001:db8::1" is_ipv6_global "2001:db8::1"
assert_true "is global: 2607:f8b0::1 (Google)" is_ipv6_global "2607:f8b0::1"
assert_true "is global: 3fff::1" is_ipv6_global "3fff::1"
assert_false "not global: fe80::1 (link-local)" is_ipv6_global "fe80::1"
assert_false "not global: fd00::1 (ULA)" is_ipv6_global "fd00::1"
assert_false "not global: ::1 (loopback)" is_ipv6_global "::1"

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
