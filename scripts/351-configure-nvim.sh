# shellcheck shell=bash
# Neovim configuration
# Modern extensible text editor
# Package installed via batch_install_packages() in 037-parallel-helpers.sh

# Configuration function for neovim
# Creates vi/vim aliases via update-alternatives
_config_nvim() {
  # Install nvim as vi/vim/editor alternatives and set as default
  remote_exec '
    update-alternatives --install /usr/bin/vi vi /usr/bin/nvim 60
    update-alternatives --install /usr/bin/vim vim /usr/bin/nvim 60
    update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 60
    update-alternatives --set vi /usr/bin/nvim
    update-alternatives --set vim /usr/bin/nvim
    update-alternatives --set editor /usr/bin/nvim
  ' || {
    log "ERROR: Failed to configure nvim alternatives"
    return 1
  }

  parallel_mark_configured "nvim"
}

# Public wrapper (generated via factory)
make_feature_wrapper "nvim" "INSTALL_NVIM"
