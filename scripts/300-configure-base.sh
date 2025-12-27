# shellcheck shell=bash
# Base system configuration via SSH

# Helper functions for run_with_progress

# Copy config files to remote (hosts, interfaces, sysctl, sources, resolv)
_copy_config_files() {
  run_parallel_copies \
    "templates/hosts:/etc/hosts" \
    "templates/interfaces:/etc/network/interfaces" \
    "templates/99-proxmox.conf:/etc/sysctl.d/99-proxmox.conf" \
    "templates/debian.sources:/etc/apt/sources.list.d/debian.sources" \
    "templates/proxmox.sources:/etc/apt/sources.list.d/proxmox.sources" \
    "templates/resolv.conf:/etc/resolv.conf"
}

# Apply basic system settings (backup sources, set hostname, disable unused services)
_apply_basic_settings() {
  remote_exec "[ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak" || return 1
  remote_exec "echo '$PVE_HOSTNAME' > /etc/hostname" || return 1
  # Disable NFS-related services (not needed on typical Proxmox install)
  # rpcbind: NFS RPC portmapper
  # nfs-blkmap: pNFS block layout mapper (causes "open pipe file failed" errors)
  remote_exec "systemctl disable --now rpcbind rpcbind.socket nfs-blkmap.service 2>/dev/null" || {
    log "WARNING: Failed to disable rpcbind/nfs-blkmap"
  }
  # Mask nfs-blkmap to prevent it from starting on boot
  remote_exec "systemctl mask nfs-blkmap.service 2>/dev/null" || true
}

# Copy locale files (locale.sh, default-locale, environment)
_install_locale_files() {
  remote_copy "templates/locale.sh" "/etc/profile.d/locale.sh" || return 1
  remote_exec "chmod +x /etc/profile.d/locale.sh" || return 1
  remote_copy "templates/default-locale" "/etc/default/locale" || return 1
  remote_copy "templates/environment" "/etc/environment" || return 1
  # Also source locale from bash.bashrc for non-login interactive shells
  remote_exec "grep -q 'profile.d/locale.sh' /etc/bash.bashrc || echo '[ -f /etc/profile.d/locale.sh ] && . /etc/profile.d/locale.sh' >> /etc/bash.bashrc" || return 1
}

# Configure fastfetch shell integration
_configure_fastfetch() {
  remote_copy "templates/fastfetch.sh" "/etc/profile.d/fastfetch.sh" || return 1
  remote_exec "chmod +x /etc/profile.d/fastfetch.sh" || return 1
}

# Configure bat with theme and symlink
_configure_bat() {
  remote_exec "ln -sf /usr/bin/batcat /usr/local/bin/bat" || return 1
  deploy_user_config "templates/bat-config" ".config/bat/config" || return 1
}

# Configure ZSH with .zshrc and p10k
_configure_zsh_files() {
  deploy_user_config "templates/zshrc" ".zshrc" "LOCALE=${LOCALE}" || return 1
  deploy_user_config "templates/p10k.zsh" ".p10k.zsh" || return 1
  # shellcheck disable=SC2016
  remote_exec 'chsh -s /bin/zsh '"$ADMIN_USERNAME"'' || return 1
}

# Private implementation functions

# Main base system configuration implementation
_config_base_system() {
  # Copy template files to VM (parallel for better performance)
  run_with_progress "Copying configuration files" "Configuration files copied" _copy_config_files

  # Apply sysctl settings to running kernel
  run_with_progress "Applying sysctl settings" "Sysctl settings applied" remote_exec "sysctl --system"

  # Basic system configuration
  run_with_progress "Applying basic system settings" "Basic system settings applied" _apply_basic_settings

  # Configure Proxmox repository
  log "configure_base_system: PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
  if [[ ${PVE_REPO_TYPE:-no-subscription} == "enterprise" ]]; then
    log "configure_base_system: configuring enterprise repository"
    # Enterprise: disable default no-subscription repo (template already has enterprise)
    # shellcheck disable=SC2016 # Single quotes intentional - executed on remote system
    remote_run "Configuring enterprise repository" '
            for repo_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
                [ -f "$repo_file" ] || continue
                if grep -q "pve-no-subscription\|pvetest" "$repo_file" 2>/dev/null; then
                    mv "$repo_file" "${repo_file}.disabled"
                fi
            done
        ' "Enterprise repository configured"

    # Register subscription key if provided
    if [[ -n $PVE_SUBSCRIPTION_KEY ]]; then
      log "configure_base_system: registering subscription key"
      remote_run "Registering subscription key" \
        "pvesubscription set '${PVE_SUBSCRIPTION_KEY}' 2>/dev/null || true" \
        "Subscription key registered"
    fi
  else
    # No-subscription or test: disable enterprise repo
    log "configure_base_system: configuring ${PVE_REPO_TYPE:-no-subscription} repository"
    # shellcheck disable=SC2016 # Single quotes intentional - executed on remote system
    remote_run "Configuring ${PVE_REPO_TYPE:-no-subscription} repository" '
            for repo_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
                [ -f "$repo_file" ] || continue
                if grep -q "enterprise.proxmox.com" "$repo_file" 2>/dev/null; then
                    mv "$repo_file" "${repo_file}.disabled"
                fi
            done

            if [ -f /etc/apt/sources.list ] && grep -q "enterprise.proxmox.com" /etc/apt/sources.list 2>/dev/null; then
                sed -i "s|^deb.*enterprise.proxmox.com|# &|g" /etc/apt/sources.list
            fi
        ' "Repository configured"
  fi

  # Install all base system packages in one batch (includes dist-upgrade)
  install_base_packages

  # Configure UTF-8 locales using template files
  # Generate the user's selected locale plus common fallbacks
  # Note: locales package already installed via install_base_packages()
  local locale_name="${LOCALE%%.UTF-8}" # Remove .UTF-8 suffix for sed pattern
  # Enable user's selected locale + en_US as fallback (many tools expect it)
  remote_run "Configuring UTF-8 locales" "
        set -e
        sed -i 's/# ${locale_name}.UTF-8/${locale_name}.UTF-8/' /etc/locale.gen
        sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
        locale-gen
        update-locale LANG=${LOCALE} LC_ALL=${LOCALE}
    " "UTF-8 locales configured"

  # Copy locale template files
  run_with_progress "Installing locale configuration files" "Locale files installed" _install_locale_files

  # Configure fastfetch to run on shell login
  run_with_progress "Configuring fastfetch" "Fastfetch configured" _configure_fastfetch

  # Configure bat with Visual Studio Dark+ theme
  # Note: Debian packages bat as 'batcat', create symlink for 'bat' command
  run_with_progress "Configuring bat" "Bat configured" _configure_bat
}

# Configure admin shell (installs Oh-My-Zsh + p10k if ZSH)
_config_shell() {
  # Configure default shell for admin user (root login is disabled)
  if [[ $SHELL_TYPE == "zsh" ]]; then
    # Install Oh-My-Zsh for admin user
    # shellcheck disable=SC2016 # Single quotes intentional - executed on remote system
    remote_run "Installing Oh-My-Zsh" '
            set -e
            export RUNZSH=no
            export CHSH=no
            export HOME=/home/'"$ADMIN_USERNAME"'
            su - '"$ADMIN_USERNAME"' -c "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended"
        ' "Oh-My-Zsh installed"

    # Parallel git clones for theme and plugins (all independent after Oh-My-Zsh)
    # shellcheck disable=SC2016 # $pid vars expand on remote; ADMIN_USERNAME uses quote concatenation
    remote_run "Installing ZSH theme and plugins" '
            set -e
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /home/'"$ADMIN_USERNAME"'/.oh-my-zsh/custom/themes/powerlevel10k &
            pid1=$!
            git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /home/'"$ADMIN_USERNAME"'/.oh-my-zsh/custom/plugins/zsh-autosuggestions &
            pid2=$!
            git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /home/'"$ADMIN_USERNAME"'/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting &
            pid3=$!
            # Wait and check exit codes (set -e doesnt catch background failures)
            failed=0
            wait $pid1 || failed=1
            wait $pid2 || failed=1
            wait $pid3 || failed=1
            if [ $failed -eq 1 ]; then
              echo "ERROR: Failed to clone ZSH plugins" >&2
              exit 1
            fi
            # Validate directories exist
            for dir in themes/powerlevel10k plugins/zsh-autosuggestions plugins/zsh-syntax-highlighting; do
              if [ ! -d "/home/'"$ADMIN_USERNAME"'/.oh-my-zsh/custom/$dir" ]; then
                echo "ERROR: ZSH plugin directory missing: $dir" >&2
                exit 1
              fi
            done
            chown -R '"$ADMIN_USERNAME"':'"$ADMIN_USERNAME"' /home/'"$ADMIN_USERNAME"'/.oh-my-zsh
        ' "ZSH theme and plugins installed"

    run_with_progress "Configuring ZSH" "ZSH with Powerlevel10k configured" _configure_zsh_files
  else
    add_log "${CLR_ORANGE}├─${CLR_RESET} Default shell: Bash ${CLR_CYAN}✓${CLR_RESET}"
  fi
}

# Public wrappers

# Configure base system via SSH into QEMU VM
configure_base_system() {
  _config_base_system
}

# Configure default shell (ZSH with Oh-My-Zsh + p10k if selected)
configure_shell() {
  _config_shell
}
