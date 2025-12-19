# shellcheck shell=bash
# =============================================================================
# Yazi file manager configuration
# Modern terminal file manager with image preview support
# Dependencies (curl, file, unzip) installed via batch_install_packages()
# =============================================================================

# Installation function for yazi - downloads binary from GitHub
# shellcheck disable=SC2016
_install_yazi() {
  run_remote "Installing yazi" '
    # Get latest yazi version and download
    YAZI_VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep "tag_name" | cut -d "\"" -f 4 | sed "s/^v//")
    curl -sL "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip

    # Extract and install
    unzip -q /tmp/yazi.zip -d /tmp/
    chmod +x /tmp/yazi-x86_64-unknown-linux-gnu/yazi
    mv /tmp/yazi-x86_64-unknown-linux-gnu/yazi /usr/local/bin/
    rm -rf /tmp/yazi.zip /tmp/yazi-x86_64-unknown-linux-gnu
  ' "Yazi installed"
}

# Configuration function for yazi
_config_yazi() {
  # Create config directory
  remote_exec 'mkdir -p /root/.config/yazi' || return 1

  # Copy theme
  remote_copy "templates/yazi-theme.toml" "/root/.config/yazi/theme.toml" || return 1
}

# Installs and configures yazi file manager with Catppuccin theme.
# Deploys custom theme configuration.
configure_yazi() {
  # Skip if yazi installation is not requested
  if [[ $INSTALL_YAZI != "yes" ]]; then
    log "Skipping yazi (not requested)"
    return 0
  fi

  log "Installing and configuring yazi"

  # Install and configure using helper (with background progress)
  (
    _install_yazi || exit 1
    _config_yazi || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing and configuring yazi" "Yazi configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: Yazi setup failed"
    print_warning "Yazi setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

}
