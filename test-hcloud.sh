#!/usr/bin/env bash
set -e

# =============================================================================
# Hetzner Cloud Test Script for Proxmox Installer (Interactive Mode)
# Creates a cloud server, runs installer in test mode (TCG), then cleans up
#
# Note: Cloud VMs don't have nested KVM, so installer uses TCG emulation.
#       This is slower but allows testing the full installation flow.
#
# Environment variables:
#   TAILSCALE_AUTH_KEY - Tailscale auth key (will be passed to installer)
#   SERVER_TYPE        - Hetzner server type (default: ccx13)
# =============================================================================

CLR_RED="\033[1;31m"
CLR_GREEN="\033[1;32m"
CLR_YELLOW="\033[1;33m"
CLR_CYAN="\033[1;36m"
CLR_RESET="\033[m"

# Configuration
SERVER_NAME="test-pve-$(date +%s)"
SERVER_TYPE="${SERVER_TYPE:-ccx13}"
INSTALL_SCRIPT_URL="https://qoxi-cloud.github.io/proxmox-hetzner/pve-install.sh"

# Generate random password for Proxmox (16 chars, alphanumeric + special)
PVE_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 16)

# State file to persist server info between sessions
STATE_FILE="/tmp/test-hcloud-state-$$"

# =============================================================================
# Helper functions
# =============================================================================

log_info() {
    echo -e "${CLR_CYAN}[INFO]${CLR_RESET} $*"
}

log_success() {
    echo -e "${CLR_GREEN}[OK]${CLR_RESET} $*"
}

log_warn() {
    echo -e "${CLR_YELLOW}[WARN]${CLR_RESET} $*"
}

log_error() {
    echo -e "${CLR_RED}[ERROR]${CLR_RESET} $*"
}

cleanup() {
    echo ""
    log_warn "Cleaning up..."
    if [[ -n "$SERVER_ID" ]]; then
        log_info "Deleting server $SERVER_NAME (ID: $SERVER_ID)..."
        hcloud server delete "$SERVER_ID" 2>/dev/null || true
        log_success "Server deleted"
    fi
    rm -f "$STATE_FILE" 2>/dev/null || true
}

save_state() {
    cat > "$STATE_FILE" << EOF
SERVER_ID="$SERVER_ID"
SERVER_IP="$SERVER_IP"
SERVER_NAME="$SERVER_NAME"
RESCUE_PASSWORD="$RESCUE_PASSWORD"
PVE_PASSWORD="$PVE_PASSWORD"
EOF
}

# =============================================================================
# Check prerequisites
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v hcloud &>/dev/null; then
        log_error "hcloud CLI not found. Install with: brew install hcloud"
        exit 1
    fi

    if ! command -v sshpass &>/dev/null; then
        log_error "sshpass not found. Install with: brew install sshpass"
        exit 1
    fi

    # Check if hcloud is configured
    if ! hcloud server list &>/dev/null; then
        log_error "hcloud not configured. Run: hcloud context create <name>"
        exit 1
    fi

    log_success "Prerequisites OK"

    # Show env vars that will be passed
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        log_success "TAILSCALE_AUTH_KEY detected (will be passed to installer)"
    fi
}

# =============================================================================
# Create server
# =============================================================================

create_server() {
    log_info "Creating server $SERVER_NAME (type: $SERVER_TYPE)..."

    # Create server and capture output
    local output
    output=$(hcloud server create \
        --name "$SERVER_NAME" \
        --type "$SERVER_TYPE" \
        --image ubuntu-22.04 \
        --location hel1 \
        2>&1)

    # Parse server ID
    SERVER_ID=$(echo "$output" | grep -oE "Server [0-9]+" | grep -oE "[0-9]+")
    if [[ -z "$SERVER_ID" ]]; then
        log_error "Failed to get server ID"
        exit 1
    fi

    # Parse IPv4
    SERVER_IP=$(echo "$output" | grep "IPv4:" | awk '{print $2}')
    if [[ -z "$SERVER_IP" ]]; then
        log_error "Failed to get server IP"
        exit 1
    fi

    log_success "Server created: ID=$SERVER_ID, IP=$SERVER_IP"
}

# =============================================================================
# Enable rescue mode
# =============================================================================

enable_rescue_mode() {
    log_info "Enabling rescue mode..."

    local output
    output=$(hcloud server enable-rescue "$SERVER_ID" --type linux64 2>&1)

    # Parse rescue password from output
    RESCUE_PASSWORD=$(echo "$output" | grep -i "root password" | awk '{print $NF}')

    log_success "Rescue mode enabled"

    log_info "Resetting server into rescue mode..."
    hcloud server reset "$SERVER_ID" >/dev/null 2>&1
    log_success "Server reset initiated"

    # Wait for server to come back online in rescue mode
    log_info "Waiting for server to boot into rescue mode..."
    sleep 20

    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if sshpass -p "$RESCUE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o UserKnownHostsFile=/dev/null root@"$SERVER_IP" "echo ok" &>/dev/null; then
            echo ""
            log_success "Server is online in rescue mode"
            return 0
        fi
        ((attempt++))
        echo -n "."
        sleep 5
    done
    echo ""

    log_error "Timeout waiting for rescue mode"
    exit 1
}

# =============================================================================
# Run installer interactively
# =============================================================================

run_installer_interactive() {
    echo ""
    log_success "Server is ready!"
    echo ""
    echo -e "${CLR_CYAN}═══════════════════════════════════════════════════════════${CLR_RESET}"
    echo -e "${CLR_GREEN}  Connecting to server in INTERACTIVE mode${CLR_RESET}"
    echo -e "${CLR_CYAN}═══════════════════════════════════════════════════════════${CLR_RESET}"
    echo ""
    echo -e "  Server IP:     ${CLR_YELLOW}$SERVER_IP${CLR_RESET}"
    echo -e "  Server ID:     ${CLR_YELLOW}$SERVER_ID${CLR_RESET}"
    echo -e "  PVE Password:  ${CLR_YELLOW}$PVE_PASSWORD${CLR_RESET} (auto-generated)"
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        echo -e "  Tailscale:     ${CLR_GREEN}Auth key will be passed automatically${CLR_RESET}"
    fi
    echo ""
    echo -e "${CLR_YELLOW}  When installer completes - disconnect with Ctrl+D or 'exit'${CLR_RESET}"
    echo -e "${CLR_YELLOW}  You will then be asked if you want to verify the installation.${CLR_RESET}"
    echo ""
    echo -e "${CLR_CYAN}═══════════════════════════════════════════════════════════${CLR_RESET}"
    echo ""

    # Build environment variables to pass
    local env_vars="export NEW_ROOT_PASSWORD='$PVE_PASSWORD'; "
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        env_vars+="export TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY'; "
    fi

    # Connect interactively - user controls the installer
    # Use --test flag for TCG emulation (cloud VMs don't have nested KVM)
    sshpass -p "$RESCUE_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -t root@"$SERVER_IP" \
        "${env_vars}bash <(curl -sSL $INSTALL_SCRIPT_URL) --test" || true

    echo ""
    log_info "SSH session ended"
}

# =============================================================================
# Verification menu
# =============================================================================

verification_menu() {
    save_state

    while true; do
        echo ""
        echo -e "${CLR_CYAN}═══════════════════════════════════════════════════════════${CLR_RESET}"
        echo -e "${CLR_GREEN}  Installation completed - Verification Menu${CLR_RESET}"
        echo -e "${CLR_CYAN}═══════════════════════════════════════════════════════════${CLR_RESET}"
        echo ""
        echo -e "  Server IP:     ${CLR_YELLOW}$SERVER_IP${CLR_RESET}"
        echo -e "  Server ID:     ${CLR_YELLOW}$SERVER_ID${CLR_RESET}"
        echo ""
        echo -e "  ${CLR_CYAN}1)${CLR_RESET} Reboot server to Proxmox and connect via SSH"
        echo -e "  ${CLR_CYAN}2)${CLR_RESET} Open Proxmox WebUI in browser"
        echo -e "  ${CLR_CYAN}3)${CLR_RESET} Connect to current system (rescue/QEMU)"
        echo -e "  ${CLR_CYAN}4)${CLR_RESET} Delete server and exit"
        echo ""
        read -rp "Select option [1-4]: " choice

        case "$choice" in
            1)
                reboot_and_connect
                ;;
            2)
                open_webui
                ;;
            3)
                connect_current
                ;;
            4)
                echo ""
                log_info "Exiting and cleaning up..."
                break
                ;;
            *)
                log_warn "Invalid option"
                ;;
        esac
    done
}

# =============================================================================
# Reboot to Proxmox and connect
# =============================================================================

reboot_and_connect() {
    log_info "Rebooting server to boot from installed Proxmox..."

    # Disable rescue mode first
    hcloud server disable-rescue "$SERVER_ID" 2>/dev/null || true

    # Reboot
    hcloud server reboot "$SERVER_ID"

    log_info "Waiting for Proxmox to boot (this may take 1-2 minutes)..."
    sleep 30

    local max_attempts=24
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        # Try SSH with password
        if sshpass -p "$PVE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o UserKnownHostsFile=/dev/null root@"$SERVER_IP" "echo ok" &>/dev/null; then
            log_success "Proxmox is online!"
            echo ""

            # Connect interactively with password
            log_info "Connecting to Proxmox via SSH..."
            sshpass -p "$PVE_PASSWORD" ssh -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -t root@"$SERVER_IP" || true
            return 0
        fi
        ((attempt++))
        echo -n "."
        sleep 5
    done
    echo ""

    log_error "Timeout waiting for Proxmox to boot"
    log_warn "Try connecting manually: ssh root@$SERVER_IP (password: $PVE_PASSWORD)"
}

# =============================================================================
# Open WebUI
# =============================================================================

open_webui() {
    local url="https://$SERVER_IP:8006"
    log_info "Opening $url in browser..."

    if [[ "$(uname)" == "Darwin" ]]; then
        open "$url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$url"
    else
        log_warn "Cannot open browser automatically"
        echo -e "  Open manually: ${CLR_YELLOW}$url${CLR_RESET}"
    fi
}

# =============================================================================
# Connect to current system
# =============================================================================

connect_current() {
    log_info "Connecting to current system..."

    # Try rescue password
    if sshpass -p "$RESCUE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -o UserKnownHostsFile=/dev/null root@"$SERVER_IP" "echo ok" &>/dev/null; then
        sshpass -p "$RESCUE_PASSWORD" ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -t root@"$SERVER_IP" || true
    else
        log_error "Cannot connect with rescue password. Server may have rebooted."
        log_info "Use option 1 to reboot and connect to Proxmox"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${CLR_CYAN}═══════════════════════════════════════════════════════════${CLR_RESET}"
    echo -e "${CLR_CYAN}  Hetzner Cloud Proxmox Installer Test (Interactive)${CLR_RESET}"
    echo -e "${CLR_CYAN}═══════════════════════════════════════════════════════════${CLR_RESET}"
    echo ""

    check_prerequisites
    create_server
    enable_rescue_mode

    # Set trap AFTER server is created so we can get SERVER_ID
    trap cleanup EXIT

    run_installer_interactive

    # After installation, show verification menu
    verification_menu

    echo ""
    log_success "Test session completed!"
    echo ""
}

main "$@"
