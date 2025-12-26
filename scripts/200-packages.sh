# shellcheck shell=bash
# Package preparation for Proxmox installation

# Prepare system packages (Proxmox repo, GPG key, packages)
prepare_packages() {
  log "Starting package preparation"

  log "Adding Proxmox repository"
  printf '%s\n' "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >/etc/apt/sources.list.d/pve.list

  # Download Proxmox GPG key
  log "Downloading Proxmox GPG key"
  curl -fsSL -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg >>"$LOG_FILE" 2>&1 &
  show_progress $! "Adding Proxmox repository" "Proxmox repository added"
  wait $!
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Failed to download Proxmox GPG key"
    print_error "Cannot reach Proxmox repository"
    exit 1
  fi
  log "Proxmox GPG key downloaded successfully"

  # Add live log subtask after completion
  if type live_log_subtask &>/dev/null 2>&1; then
    live_log_subtask "Configuring APT sources"
  fi

  # Update package lists
  log "Updating package lists"
  apt-get clean >>"$LOG_FILE" 2>&1
  apt-get update >>"$LOG_FILE" 2>&1 &
  show_progress $! "Updating package lists" "Package lists updated"
  wait $!
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Failed to update package lists"
    exit 1
  fi
  log "Package lists updated successfully"

  # Add live log subtask after completion
  if type live_log_subtask &>/dev/null 2>&1; then
    live_log_subtask "Downloading package lists"
  fi

  # Install packages
  log "Installing required packages: proxmox-auto-install-assistant xorriso ovmf wget sshpass"
  apt-get install -yq proxmox-auto-install-assistant xorriso ovmf wget sshpass >>"$LOG_FILE" 2>&1 &
  show_progress $! "Installing required packages" "Required packages installed"
  wait $!
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "ERROR: Failed to install required packages"
    exit 1
  fi
  log "Required packages installed successfully"

  # Add live log subtasks after completion
  if type live_log_subtask &>/dev/null 2>&1; then
    live_log_subtask "Installing proxmox-auto-install-assistant"
    live_log_subtask "Installing xorriso and ovmf"
  fi
}
