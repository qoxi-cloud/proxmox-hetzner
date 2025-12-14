# shellcheck shell=bash
# =============================================================================
# Yazi file manager configuration
# Modern terminal file manager with image preview support
# =============================================================================

# Installs and configures yazi file manager with Catppuccin theme.
# Deploys custom theme configuration.
# Side effects: Sets YAZI_INSTALLED global, installs yazi package
configure_yazi() {
  # Skip if yazi installation is not requested
  if [[ $INSTALL_YAZI != "yes" ]]; then
    log "Skipping yazi (not requested)"
    return 0
  fi

  log "Installing and configuring yazi"

  # Install yazi from GitHub releases (not available in Debian repos)
  # shellcheck disable=SC2016
  run_remote "Installing yazi" '
        # Install dependencies
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -yqq curl file

        # Get latest yazi version and download
        YAZI_VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep "tag_name" | cut -d "\"" -f 4 | sed "s/^v//")
        curl -sL "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip

        # Extract and install
        apt-get install -yqq unzip
        unzip -q /tmp/yazi.zip -d /tmp/
        chmod +x /tmp/yazi-x86_64-unknown-linux-gnu/yazi
        mv /tmp/yazi-x86_64-unknown-linux-gnu/yazi /usr/local/bin/
        rm -rf /tmp/yazi.zip /tmp/yazi-x86_64-unknown-linux-gnu
    ' "Yazi installed"

  # Deploy theme configuration (already downloaded in make_templates)
  (
    # Create config directory and copy theme
    remote_exec '
            mkdir -p /root/.config/yazi
        ' || exit 1

    remote_copy "templates/yazi-theme.toml" "/root/.config/yazi/theme.toml" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring yazi theme" "Yazi configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: Yazi configuration failed"
    print_warning "Yazi configuration failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  YAZI_INSTALLED="yes"
}
