# shellcheck shell=bash
# Yazi file manager configuration
# Modern terminal file manager with image preview support
# Dependencies (file, unzip) installed via batch_install_packages()
# curl installed via SYSTEM_UTILITIES
# Config is deployed to admin user's home directory (not root)

# Installation helper for yazi - downloads binary from GitHub
# Uses remote_exec (not remote_run) because this runs in background subshell
# concurrent with run_parallel_group - multiple gum spin would corrupt terminal
# shellcheck disable=SC2016
_install_yazi() {
  # Download latest yazi release, extract, and install to /usr/local/bin
  remote_exec '
    set -e
    YAZI_VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep "tag_name" | cut -d "\"" -f 4 | sed "s/^v//")
    curl -sL "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip
    unzip -q /tmp/yazi.zip -d /tmp/
    chmod +x /tmp/yazi-x86_64-unknown-linux-gnu/yazi /tmp/yazi-x86_64-unknown-linux-gnu/ya
    mv /tmp/yazi-x86_64-unknown-linux-gnu/yazi /tmp/yazi-x86_64-unknown-linux-gnu/ya /usr/local/bin/
    rm -rf /tmp/yazi.zip /tmp/yazi-x86_64-unknown-linux-gnu
  ' || {
    log "ERROR: Failed to install yazi"
    return 1
  }
  log "Yazi binary installed"
}

# Configuration function for yazi - installs binary and deploys theme
_config_yazi() {
  _install_yazi || return 1

  # Install flavor and plugins as admin user
  # shellcheck disable=SC2016
  remote_exec 'su - '"${ADMIN_USERNAME}"' -c "
    ya pack -a kalidyasin/yazi-flavors:tokyonight-night
    ya pack -a yazi-rs/plugins:chmod
    ya pack -a yazi-rs/plugins:smart-enter
    ya pack -a yazi-rs/plugins:smart-filter
    ya pack -a yazi-rs/plugins:full-border
  "' || {
    log "ERROR: Failed to install yazi plugins"
    return 1
  }

  deploy_user_configs \
    "templates/yazi-theme.toml:.config/yazi/theme.toml" \
    "templates/yazi-init.lua:.config/yazi/init.lua" \
    "templates/yazi-keymap.toml:.config/yazi/keymap.toml" || {
    log "ERROR: Failed to deploy yazi configs"
    return 1
  }
}

# Public wrapper (generated via factory)
# Installs yazi file manager with Tokyo Night theme
make_feature_wrapper "yazi" "INSTALL_YAZI"
