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
  # Includes validation to catch download failures (empty files)
  remote_exec '
    set -e
    YAZI_VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep "tag_name" | cut -d "\"" -f 4 | sed "s/^v//")
    if [ -z "$YAZI_VERSION" ]; then
      echo "ERROR: Failed to get yazi version from GitHub API" >&2
      exit 1
    fi
    # -f fails on HTTP errors, --retry for transient failures
    if ! curl -fsSL --retry 3 "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip; then
      echo "ERROR: Failed to download yazi v${YAZI_VERSION}" >&2
      exit 1
    fi
    # Validate zip file (should be > 1MB and valid zip)
    if [ "$(stat -c%s /tmp/yazi.zip 2>/dev/null || echo 0)" -lt 1000000 ]; then
      echo "ERROR: Yazi download too small (corrupt?)" >&2
      rm -f /tmp/yazi.zip
      exit 1
    fi
    if ! unzip -tq /tmp/yazi.zip >/dev/null 2>&1; then
      echo "ERROR: Yazi zip file is corrupt" >&2
      rm -f /tmp/yazi.zip
      exit 1
    fi
    unzip -oq /tmp/yazi.zip -d /tmp/
    # Verify extracted binaries before moving
    if [ ! -x /tmp/yazi-x86_64-unknown-linux-gnu/yazi ] || \
       [ "$(stat -c%s /tmp/yazi-x86_64-unknown-linux-gnu/yazi 2>/dev/null || echo 0)" -lt 1000000 ]; then
      echo "ERROR: Extracted yazi binary invalid" >&2
      rm -rf /tmp/yazi.zip /tmp/yazi-x86_64-unknown-linux-gnu
      exit 1
    fi
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
  # Note: ya pack may fail if network is unavailable - log warning but don't fail
  # Yazi still works without plugins, user can install later
  # shellcheck disable=SC2016
  remote_exec 'su - '"${ADMIN_USERNAME}"' -c "
    ya pack -a kalidyasin/yazi-flavors:tokyonight-night || echo \"WARNING: Failed to install yazi flavor\" >&2
    ya pack -a yazi-rs/plugins:chmod || echo \"WARNING: Failed to install chmod plugin\" >&2
    ya pack -a yazi-rs/plugins:smart-enter || echo \"WARNING: Failed to install smart-enter plugin\" >&2
    ya pack -a yazi-rs/plugins:smart-filter || echo \"WARNING: Failed to install smart-filter plugin\" >&2
    ya pack -a yazi-rs/plugins:full-border || echo \"WARNING: Failed to install full-border plugin\" >&2
  "' || {
    log "WARNING: Failed to install some yazi plugins (yazi will still work)"
  }

  deploy_user_configs \
    "templates/yazi.toml:.config/yazi/yazi.toml" \
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
