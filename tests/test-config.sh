#!/usr/bin/env bash
# =============================================================================
# Unit tests for config functions (02-config.sh)
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
NON_INTERACTIVE=false
CONFIG_FILE=""

# Source validation first (required by config)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/13-validation.sh"

# Source only the validate_config function (skip auto-load)
eval "$(sed -n '/^validate_config()/,/^}/p' "$SCRIPT_DIR/scripts/02-config.sh")"

# assert_true runs a command, increments TESTS_RUN, prints a colored pass/fail message with the provided description, and updates TESTS_PASSED or TESTS_FAILED accordingly.
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

# Helper to reset config vars
reset_config() {
    BRIDGE_MODE=""
    ZFS_RAID=""
    PVE_REPO_TYPE=""
    SSL_TYPE=""
    DEFAULT_SHELL=""
    INSTALL_AUDITD=""
    INSTALL_VNSTAT=""
    INSTALL_UNATTENDED_UPGRADES=""
    CPU_GOVERNOR=""
    IPV6_MODE=""
    IPV6_GATEWAY=""
    IPV6_ADDRESS=""
    SSH_PUBLIC_KEY=""
}

# =============================================================================
# BRIDGE_MODE validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: BRIDGE_MODE ===${NC}"

reset_config
BRIDGE_MODE="internal"
assert_true "valid BRIDGE_MODE: internal" validate_config

reset_config
BRIDGE_MODE="external"
assert_true "valid BRIDGE_MODE: external" validate_config

reset_config
BRIDGE_MODE="both"
assert_true "valid BRIDGE_MODE: both" validate_config

reset_config
BRIDGE_MODE="invalid"
assert_false "invalid BRIDGE_MODE: invalid" validate_config

# =============================================================================
# ZFS_RAID validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: ZFS_RAID ===${NC}"

reset_config
ZFS_RAID="single"
assert_true "valid ZFS_RAID: single" validate_config

reset_config
ZFS_RAID="raid0"
assert_true "valid ZFS_RAID: raid0" validate_config

reset_config
ZFS_RAID="raid1"
assert_true "valid ZFS_RAID: raid1" validate_config

reset_config
ZFS_RAID="raid5"
assert_false "invalid ZFS_RAID: raid5" validate_config

# =============================================================================
# PVE_REPO_TYPE validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: PVE_REPO_TYPE ===${NC}"

reset_config
PVE_REPO_TYPE="no-subscription"
assert_true "valid PVE_REPO_TYPE: no-subscription" validate_config

reset_config
PVE_REPO_TYPE="enterprise"
assert_true "valid PVE_REPO_TYPE: enterprise" validate_config

reset_config
PVE_REPO_TYPE="test"
assert_true "valid PVE_REPO_TYPE: test" validate_config

reset_config
PVE_REPO_TYPE="community"
assert_false "invalid PVE_REPO_TYPE: community" validate_config

# =============================================================================
# SSL_TYPE validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: SSL_TYPE ===${NC}"

reset_config
SSL_TYPE="self-signed"
assert_true "valid SSL_TYPE: self-signed" validate_config

reset_config
SSL_TYPE="letsencrypt"
assert_true "valid SSL_TYPE: letsencrypt" validate_config

reset_config
SSL_TYPE="custom"
assert_false "invalid SSL_TYPE: custom" validate_config

# =============================================================================
# DEFAULT_SHELL validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: DEFAULT_SHELL ===${NC}"

reset_config
DEFAULT_SHELL="bash"
assert_true "valid DEFAULT_SHELL: bash" validate_config

reset_config
DEFAULT_SHELL="zsh"
assert_true "valid DEFAULT_SHELL: zsh" validate_config

reset_config
DEFAULT_SHELL="fish"
assert_false "invalid DEFAULT_SHELL: fish" validate_config

# =============================================================================
# Boolean option validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: Boolean options ===${NC}"

reset_config
INSTALL_AUDITD="yes"
assert_true "valid INSTALL_AUDITD: yes" validate_config

reset_config
INSTALL_AUDITD="no"
assert_true "valid INSTALL_AUDITD: no" validate_config

reset_config
INSTALL_AUDITD="true"
assert_false "invalid INSTALL_AUDITD: true" validate_config

reset_config
INSTALL_VNSTAT="yes"
assert_true "valid INSTALL_VNSTAT: yes" validate_config

reset_config
INSTALL_VNSTAT="maybe"
assert_false "invalid INSTALL_VNSTAT: maybe" validate_config

reset_config
INSTALL_UNATTENDED_UPGRADES="yes"
assert_true "valid INSTALL_UNATTENDED_UPGRADES: yes" validate_config

reset_config
INSTALL_UNATTENDED_UPGRADES="1"
assert_false "invalid INSTALL_UNATTENDED_UPGRADES: 1" validate_config

# =============================================================================
# CPU_GOVERNOR validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: CPU_GOVERNOR ===${NC}"

reset_config
CPU_GOVERNOR="performance"
assert_true "valid CPU_GOVERNOR: performance" validate_config

reset_config
CPU_GOVERNOR="ondemand"
assert_true "valid CPU_GOVERNOR: ondemand" validate_config

reset_config
CPU_GOVERNOR="powersave"
assert_true "valid CPU_GOVERNOR: powersave" validate_config

reset_config
CPU_GOVERNOR="schedutil"
assert_true "valid CPU_GOVERNOR: schedutil" validate_config

reset_config
CPU_GOVERNOR="conservative"
assert_true "valid CPU_GOVERNOR: conservative" validate_config

reset_config
CPU_GOVERNOR="turbo"
assert_false "invalid CPU_GOVERNOR: turbo" validate_config

# =============================================================================
# IPv6 configuration validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: IPv6 options ===${NC}"

reset_config
IPV6_MODE="auto"
assert_true "valid IPV6_MODE: auto" validate_config

reset_config
IPV6_MODE="manual"
assert_true "valid IPV6_MODE: manual" validate_config

reset_config
IPV6_MODE="disabled"
assert_true "valid IPV6_MODE: disabled" validate_config

reset_config
IPV6_MODE="dhcp"
assert_false "invalid IPV6_MODE: dhcp" validate_config

reset_config
IPV6_GATEWAY="auto"
assert_true "valid IPV6_GATEWAY: auto" validate_config

reset_config
IPV6_GATEWAY="fe80::1"
assert_true "valid IPV6_GATEWAY: fe80::1" validate_config

reset_config
IPV6_GATEWAY="invalid"
assert_false "invalid IPV6_GATEWAY: invalid" validate_config

reset_config
IPV6_ADDRESS="2001:db8::1/64"
assert_true "valid IPV6_ADDRESS: 2001:db8::1/64" validate_config

reset_config
IPV6_ADDRESS="2001:db8::1"
assert_false "invalid IPV6_ADDRESS without prefix: 2001:db8::1" validate_config

# =============================================================================
# Combined validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing validate_config: Combined ===${NC}"

reset_config
BRIDGE_MODE="internal"
ZFS_RAID="raid1"
PVE_REPO_TYPE="no-subscription"
SSL_TYPE="self-signed"
DEFAULT_SHELL="zsh"
CPU_GOVERNOR="performance"
IPV6_MODE="auto"
assert_true "valid combined config" validate_config

reset_config
BRIDGE_MODE="invalid"
ZFS_RAID="raid1"
assert_false "combined with one invalid value" validate_config

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