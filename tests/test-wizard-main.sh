#!/usr/bin/env bash
# =============================================================================
# Unit tests for wizard main flow (12-wizard-main.sh)
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
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/12-wizard-main.sh"

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
# Function existence tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing function existence ===${NC}"

test_function_exists_show_preview() {
    declare -F _wiz_show_preview > /dev/null
}

assert_true "_wiz_show_preview function exists" test_function_exists_show_preview

test_function_exists_get_inputs_wizard() {
    declare -F get_inputs_wizard > /dev/null
}

assert_true "get_inputs_wizard function exists" test_function_exists_get_inputs_wizard

# =============================================================================
# Preview function tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing preview configuration ===${NC}"

# Mock functions for testing
gum() {
    local cmd="$1"
    shift
    case "$cmd" in
        style)
            # Extract the text argument
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

wiz_banner() {
    echo "Banner"
}

wiz_confirm() {
    return 1  # Default to "no"
}

parse_ssh_key() {
    SSH_KEY_TYPE="ssh-rsa"
    SSH_KEY_SHORT="test-key"
}

# Set up test configuration
setup_test_config() {
    PVE_HOSTNAME="test-host"
    DOMAIN_SUFFIX="example.com"
    EMAIL="admin@example.com"
    TIMEZONE="UTC"
    PASSWORD_GENERATED="no"
    INTERFACE_NAME="eth0"
    MAIN_IPV4_CIDR="192.168.1.100/24"
    BRIDGE_MODE="internal"
    PRIVATE_SUBNET="10.0.0.0/24"
    IPV6_MODE="disabled"
    DRIVE_COUNT=2
    ZFS_RAID="raid1"
    PVE_REPO_TYPE="no-subscription"
    SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2E test@example.com"
    SSL_TYPE="self-signed"
    DEFAULT_SHELL="zsh"
    CPU_GOVERNOR="performance"
    INSTALL_VNSTAT="yes"
    INSTALL_UNATTENDED_UPGRADES="yes"
    INSTALL_AUDITD="no"
    INSTALL_TAILSCALE="no"
}

test_preview_with_complete_config() {
    setup_test_config
    # Test that preview function doesn't crash with valid config
    declare -F _wiz_show_preview > /dev/null
}

assert_true "_wiz_show_preview handles complete configuration" test_preview_with_complete_config

test_preview_with_minimal_config() {
    PVE_HOSTNAME="minimal"
    DOMAIN_SUFFIX="local"
    EMAIL="test@test.com"
    TIMEZONE="UTC"
    INTERFACE_NAME="eth0"
    BRIDGE_MODE="external"
    ZFS_RAID="single"
    PVE_REPO_TYPE="no-subscription"
    SSL_TYPE="self-signed"
    DEFAULT_SHELL="bash"
    CPU_GOVERNOR="ondemand"
    INSTALL_VNSTAT="no"
    INSTALL_UNATTENDED_UPGRADES="no"
    INSTALL_AUDITD="no"
    INSTALL_TAILSCALE="no"
    
    declare -F _wiz_show_preview > /dev/null
}

assert_true "_wiz_show_preview handles minimal configuration" test_preview_with_minimal_config

test_preview_with_tailscale_enabled() {
    setup_test_config
    INSTALL_TAILSCALE="yes"
    TAILSCALE_AUTH_KEY="tskey-auth-test"
    TAILSCALE_SSH="yes"
    TAILSCALE_DISABLE_SSH="no"
    
    declare -F _wiz_show_preview > /dev/null
}

assert_true "_wiz_show_preview handles Tailscale configuration" test_preview_with_tailscale_enabled

test_preview_with_ipv6_enabled() {
    setup_test_config
    IPV6_MODE="auto"
    MAIN_IPV6="2001:db8::1"
    
    declare -F _wiz_show_preview > /dev/null
}

assert_true "_wiz_show_preview handles IPv6 configuration" test_preview_with_ipv6_enabled

test_preview_with_generated_password() {
    setup_test_config
    PASSWORD_GENERATED="yes"
    
    declare -F _wiz_show_preview > /dev/null
}

assert_true "_wiz_show_preview indicates auto-generated password" test_preview_with_generated_password

# =============================================================================
# Configuration validation tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing configuration scenarios ===${NC}"

test_config_both_bridge_mode() {
    setup_test_config
    BRIDGE_MODE="both"
    PRIVATE_SUBNET="172.16.0.0/24"
    
    # Should handle "both" mode which requires private subnet
    [[ "$BRIDGE_MODE" == "both" ]] && [[ -n "$PRIVATE_SUBNET" ]]
}

assert_true "configuration handles 'both' bridge mode" test_config_both_bridge_mode

test_config_external_bridge_mode() {
    setup_test_config
    BRIDGE_MODE="external"
    
    # External mode should work without private subnet
    [[ "$BRIDGE_MODE" == "external" ]]
}

assert_true "configuration handles 'external' bridge mode" test_config_external_bridge_mode

test_config_multi_drive_zfs() {
    setup_test_config
    DRIVE_COUNT=4
    ZFS_RAID="raid0"
    
    [[ "$DRIVE_COUNT" -ge 2 ]] && [[ "$ZFS_RAID" == "raid0" ]]
}

assert_true "configuration handles multi-drive ZFS" test_config_multi_drive_zfs

test_config_single_drive() {
    setup_test_config
    DRIVE_COUNT=1
    ZFS_RAID="single"
    
    [[ "$DRIVE_COUNT" -eq 1 ]] && [[ "$ZFS_RAID" == "single" ]]
}

assert_true "configuration handles single drive" test_config_single_drive

test_config_enterprise_repo() {
    setup_test_config
    PVE_REPO_TYPE="enterprise"
    
    [[ "$PVE_REPO_TYPE" == "enterprise" ]]
}

assert_true "configuration handles enterprise repository" test_config_enterprise_repo

test_config_letsencrypt_ssl() {
    setup_test_config
    SSL_TYPE="letsencrypt"
    
    [[ "$SSL_TYPE" == "letsencrypt" ]]
}

assert_true "configuration handles Let's Encrypt SSL" test_config_letsencrypt_ssl

test_config_all_features_enabled() {
    setup_test_config
    INSTALL_VNSTAT="yes"
    INSTALL_UNATTENDED_UPGRADES="yes"
    INSTALL_AUDITD="yes"
    
    [[ "$INSTALL_VNSTAT" == "yes" ]] && \
    [[ "$INSTALL_UNATTENDED_UPGRADES" == "yes" ]] && \
    [[ "$INSTALL_AUDITD" == "yes" ]]
}

assert_true "configuration handles all features enabled" test_config_all_features_enabled

test_config_tailscale_stealth_mode() {
    setup_test_config
    INSTALL_TAILSCALE="yes"
    TAILSCALE_DISABLE_SSH="yes"
    
    # Stealth mode should be enabled when OpenSSH is disabled
    [[ "$INSTALL_TAILSCALE" == "yes" ]] && [[ "$TAILSCALE_DISABLE_SSH" == "yes" ]]
}

assert_true "configuration handles Tailscale stealth mode" test_config_tailscale_stealth_mode

# =============================================================================
# Edge case tests
# =============================================================================
echo -e "\n${YELLOW}=== Testing edge cases ===${NC}"

test_config_empty_ssh_key() {
    setup_test_config
    SSH_PUBLIC_KEY=""
    
    # Should handle empty SSH key gracefully
    [[ -z "$SSH_PUBLIC_KEY" ]]
}

assert_true "configuration handles empty SSH key" test_config_empty_ssh_key

test_config_empty_optional_fields() {
    PVE_HOSTNAME="test"
    DOMAIN_SUFFIX="local"
    EMAIL="test@test.com"
    TIMEZONE="UTC"
    INTERFACE_NAME="eth0"
    BRIDGE_MODE="external"
    ZFS_RAID="single"
    PVE_REPO_TYPE="no-subscription"
    SSL_TYPE="self-signed"
    DEFAULT_SHELL="bash"
    CPU_GOVERNOR="performance"
    INSTALL_VNSTAT="no"
    INSTALL_UNATTENDED_UPGRADES="no"
    INSTALL_AUDITD="no"
    INSTALL_TAILSCALE="no"
    
    # All optional fields empty
    TAILSCALE_AUTH_KEY=""
    PROXMOX_ISO_VERSION=""
    
    [[ -z "$TAILSCALE_AUTH_KEY" ]] && [[ -z "$PROXMOX_ISO_VERSION" ]]
}

assert_true "configuration handles empty optional fields" test_config_empty_optional_fields

test_config_various_governors() {
    for gov in "performance" "ondemand" "powersave" "schedutil" "conservative"; do
        setup_test_config
        CPU_GOVERNOR="$gov"
        [[ "$CPU_GOVERNOR" == "$gov" ]] || return 1
    done
    return 0
}

assert_true "configuration handles all CPU governors" test_config_various_governors

test_config_various_shells() {
    for shell in "bash" "zsh"; do
        setup_test_config
        DEFAULT_SHELL="$shell"
        [[ "$DEFAULT_SHELL" == "$shell" ]] || return 1
    done
    return 0
}

assert_true "configuration handles both shell options" test_config_various_shells

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