# shellcheck shell=bash
# =============================================================================
# Yazi file manager configuration
# Modern terminal file manager with image preview support
# Dependencies (curl, file, unzip) installed via batch_install_packages()
# Config is deployed to admin user's home directory (not root)
# =============================================================================

# Installation function for yazi - downloads binary from GitHub
# shellcheck disable=SC2016
_install_yazi() {
  # Download latest yazi release, extract, and install to /usr/local/bin
  remote_run "Installing yazi" '
    set -e
    YAZI_VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep "tag_name" | cut -d "\"" -f 4 | sed "s/^v//")
    curl -sL "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip
    unzip -q /tmp/yazi.zip -d /tmp/
    chmod +x /tmp/yazi-x86_64-unknown-linux-gnu/yazi
    mv /tmp/yazi-x86_64-unknown-linux-gnu/yazi /usr/local/bin/
    rm -rf /tmp/yazi.zip /tmp/yazi-x86_64-unknown-linux-gnu
  ' "Yazi installed"
}

# Configuration function for yazi
_config_yazi() {
  # Create config directory for admin user
  # shellcheck disable=SC2016
  remote_exec 'mkdir -p /home/$ADMIN_USERNAME/.config/yazi' || {
    log "ERROR: Failed to create yazi config directory"
    return 1
  }

  # Copy theme
  remote_copy "templates/yazi-theme.toml" "/home/${ADMIN_USERNAME}/.config/yazi/theme.toml" || {
    log "ERROR: Failed to deploy yazi theme"
    return 1
  }

  # Set correct ownership
  # shellcheck disable=SC2016
  remote_exec 'chown -R $ADMIN_USERNAME:$ADMIN_USERNAME /home/$ADMIN_USERNAME/.config/yazi' || {
    log "ERROR: Failed to set yazi config ownership"
    return 1
  }
}

# Combined install and config for run_with_progress
_install_and_config_yazi() {
  _install_yazi || return 1
  _config_yazi || return 1
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

  if ! run_with_progress "Installing yazi" "Yazi configured" _install_and_config_yazi; then
    log "WARNING: Yazi setup failed"
  fi
  return 0 # Non-fatal error
}
