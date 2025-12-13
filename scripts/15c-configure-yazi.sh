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

  # Install yazi package
  run_remote "Installing yazi" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -yqq yazi
    ' "Yazi installed"

  # Download and deploy theme configuration
  (
    download_template "./templates/yazi-theme.toml" || exit 1

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
