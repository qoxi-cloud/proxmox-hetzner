#!/usr/bin/env bash
# =============================================================================
# Test script for live logs integration
# =============================================================================

set -euo pipefail

# Source color definitions (minimal set for testing)
CLR_RED=$'\033[1;31m'
CLR_CYAN=$'\033[38;2;0;177;255m'
CLR_YELLOW=$'\033[1;33m'
CLR_ORANGE=$'\033[38;5;208m'
CLR_GRAY=$'\033[38;5;240m'
CLR_HETZNER=$'\033[38;5;160m'
CLR_RESET=$'\033[m'

HEX_CYAN="#00b1ff"

# Minimal config
LOG_FILE="/tmp/test-live-logs-$(date +%Y%m%d-%H%M%S).log"

# Source the live logs module
source scripts/07-live-logs.sh

# Minimal log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

# Mock show_progress_original (simulates the original gum-based version)
show_progress_original() {
  local pid=$1
  local message="${2:-Processing}"
  local done_message="${3:-$message}"

  echo "  [Original] $message..."
  wait "$pid" 2>/dev/null
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "  [Original] ✓ $done_message"
  else
    echo "  [Original] ✗ $message"
  fi

  return $exit_code
}

# Test functions
test_task_1() {
  sleep 2
  echo "Task 1 completed" >>"$LOG_FILE"
}

test_task_2() {
  sleep 1
  echo "Task 2 completed" >>"$LOG_FILE"
}

test_task_3() {
  sleep 1.5
  echo "Task 3 completed" >>"$LOG_FILE"
}

# Main test
main() {
  echo "Testing live logs integration..."
  echo ""

  # Start live installation display
  start_live_installation || {
    echo "Failed to start live installation display"
    exit 1
  }

  # Rescue System Preparation
  live_log_system_preparation

  # Simulate some tasks with subtask details
  test_task_1 &
  local task_pid=$!
  show_progress $task_pid "Adding Proxmox repository" "Proxmox repository added"
  live_log_subtask "Configuring APT sources"

  test_task_2 &
  task_pid=$!
  show_progress $task_pid "Updating package lists" "Package lists updated"
  live_log_subtask "Downloading package lists"

  test_task_1 &
  task_pid=$!
  show_progress $task_pid "Installing required packages" "Required packages installed"
  live_log_subtask "Installing proxmox-auto-install-assistant"
  live_log_subtask "Installing xorriso and ovmf"

  # Proxmox ISO Download
  live_log_iso_download

  test_task_3 &
  task_pid=$!
  show_progress $task_pid "Downloading Proxmox ISO" "Proxmox ISO downloaded"

  test_task_1 &
  task_pid=$!
  show_progress $task_pid "Verifying checksum" "Checksum verified"
  live_log_subtask "SHA256: OK"

  test_task_2 &
  task_pid=$!
  show_progress $task_pid "Creating autoinstall ISO" "Autoinstall ISO created"
  live_log_subtask "Creating answer.toml"
  live_log_subtask "Packing ISO with xorriso"

  # Proxmox Installation
  live_log_proxmox_installation

  live_log_subtask "QEMU started (16 vCPUs, 8192MB RAM)"
  test_task_3 &
  task_pid=$!
  show_progress $task_pid "Installing Proxmox VE" "Proxmox VE installed"

  live_log_subtask "Waiting for SSH port 5555"
  test_task_2 &
  task_pid=$!
  show_progress $task_pid "Booting installed Proxmox" "Proxmox booted"
  live_log_subtask "SSH connection established"

  # System Configuration
  live_log_system_configuration

  test_task_1 &
  task_pid=$!
  show_progress $task_pid "Configuring network" "Network configured"
  live_log_subtask "Creating bridge vmbr0"
  live_log_subtask "Setting up NAT"

  test_task_2 &
  task_pid=$!
  show_progress $task_pid "Installing system utilities" "System utilities installed"
  live_log_subtask "Installing btop, iotop, ncdu"
  live_log_subtask "Installing tmux, jq, bat"

  test_task_1 &
  task_pid=$!
  show_progress $task_pid "Configuring ZSH" "ZSH configured"
  live_log_subtask "Installing Oh My Zsh"
  live_log_subtask "Configuring Powerlevel10k"

  # Security Configuration (simulated)
  INSTALL_TAILSCALE="yes"
  live_log_security_configuration

  test_task_2 &
  task_pid=$!
  show_progress $task_pid "Configuring Tailscale" "Tailscale configured"
  live_log_subtask "Installing Tailscale"
  live_log_subtask "Authenticating with auth key"
  live_log_subtask "Configuring Tailscale SSH"

  # SSL Configuration (simulated)
  SSL_TYPE="letsencrypt"
  live_log_ssl_configuration

  test_task_1 &
  task_pid=$!
  show_progress $task_pid "Configuring Let's Encrypt" "Let's Encrypt configured"
  live_log_subtask "Requesting certificate"
  live_log_subtask "Validating domain"
  live_log_subtask "Installing certificate"

  # Validation & Finalization
  live_log_validation_finalization

  test_task_2 &
  task_pid=$!
  show_progress $task_pid "Validating installation" "Validation complete"
  live_log_subtask "Checking services: OK"
  live_log_subtask "Checking network: OK"
  live_log_subtask "Checking storage: OK"

  test_task_1 &
  task_pid=$!
  show_progress $task_pid "Deploying SSH hardening" "SSH hardening deployed"
  live_log_subtask "Disabling password authentication"
  live_log_subtask "Installing SSH key"

  # Installation Complete
  live_log_installation_complete

  # Finish live installation display
  finish_live_installation

  echo ""
  echo "Test completed! Check log file: $LOG_FILE"
  echo "Press Enter to exit..."
  read -r
}

main "$@"
