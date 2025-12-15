# shellcheck shell=bash
# =============================================================================
# Neovim configuration
# Modern extensible text editor
# =============================================================================

# Installation function for neovim
_install_nvim() {
  run_remote "Installing neovim" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq neovim
  ' "Neovim installed"
}

# Configuration function for neovim
_config_nvim() {
  # Create alternatives for vi and vim
  remote_exec '
    update-alternatives --install /usr/bin/vi vi /usr/bin/nvim 60
    update-alternatives --install /usr/bin/vim vim /usr/bin/nvim 60
    update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 60

    # Set nvim as default
    update-alternatives --set vi /usr/bin/nvim
    update-alternatives --set vim /usr/bin/nvim
    update-alternatives --set editor /usr/bin/nvim
  ' || exit 1
}

# Installs neovim and creates vi/vim aliases.
# Side effects: Sets NVIM_INSTALLED global, installs neovim package, creates vi alias
configure_nvim() {
  # Skip if nvim installation is not requested
  if [[ $INSTALL_NVIM != "yes" ]]; then
    log "Skipping neovim (not requested)"
    return 0
  fi

  log "Installing and configuring neovim"

  # Install and configure using helper (with background progress)
  (
    _install_nvim || exit 1
    _config_nvim || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing and configuring neovim" "Neovim configured"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: Neovim setup failed"
    print_warning "Neovim setup failed - continuing without it"
    return 0 # Non-fatal error
  fi

  # Set flag for summary display
  # shellcheck disable=SC2034
  NVIM_INSTALLED="yes"
}
