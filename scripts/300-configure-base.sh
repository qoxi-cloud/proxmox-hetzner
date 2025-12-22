# shellcheck shell=bash
# =============================================================================
# Base system configuration via SSH
# =============================================================================

# =============================================================================
# Helper functions for run_with_progress
# =============================================================================

# Copies all configuration files in parallel
_copy_config_files() {
  local -a copy_pids=()
  remote_copy "templates/hosts" "/etc/hosts" >/dev/null 2>&1 &
  copy_pids+=($!)
  remote_copy "templates/interfaces" "/etc/network/interfaces" >/dev/null 2>&1 &
  copy_pids+=($!)
  remote_copy "templates/99-proxmox.conf" "/etc/sysctl.d/99-proxmox.conf" >/dev/null 2>&1 &
  copy_pids+=($!)
  remote_copy "templates/debian.sources" "/etc/apt/sources.list.d/debian.sources" >/dev/null 2>&1 &
  copy_pids+=($!)
  remote_copy "templates/proxmox.sources" "/etc/apt/sources.list.d/proxmox.sources" >/dev/null 2>&1 &
  copy_pids+=($!)
  remote_copy "templates/resolv.conf" "/etc/resolv.conf" >/dev/null 2>&1 &
  copy_pids+=($!)
  for pid in "${copy_pids[@]}"; do
    wait "$pid" || return 1
  done
}

# Applies basic system settings (hostname, disable rpcbind)
_apply_basic_settings() {
  remote_exec "[ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak" || return 1
  remote_exec "echo '$PVE_HOSTNAME' > /etc/hostname" || return 1
  remote_exec "systemctl disable --now rpcbind rpcbind.socket" || {
    log "WARNING: Failed to disable rpcbind"
  }
}

# Installs locale configuration files
_install_locale_files() {
  remote_copy "templates/locale.sh" "/etc/profile.d/locale.sh" || return 1
  remote_exec "chmod +x /etc/profile.d/locale.sh" || return 1
  remote_copy "templates/default-locale" "/etc/default/locale" || return 1
  remote_copy "templates/environment" "/etc/environment" || return 1
}

# Configures fastfetch shell integration
_configure_fastfetch() {
  remote_copy "templates/fastfetch.sh" "/etc/profile.d/fastfetch.sh" || return 1
  remote_exec "chmod +x /etc/profile.d/fastfetch.sh" || return 1
  # Also source from bash.bashrc for non-login interactive shells
  remote_exec "grep -q 'profile.d/fastfetch.sh' /etc/bash.bashrc || echo '[ -f /etc/profile.d/fastfetch.sh ] && . /etc/profile.d/fastfetch.sh' >> /etc/bash.bashrc" || return 1
}

# Configures bat with Visual Studio Dark+ theme for admin user
_configure_bat() {
  remote_exec "ln -sf /usr/bin/batcat /usr/local/bin/bat" || return 1
  # shellcheck disable=SC2016
  remote_exec 'mkdir -p /home/$ADMIN_USERNAME/.config/bat' || return 1
  remote_copy "templates/bat-config" "/home/${ADMIN_USERNAME}/.config/bat/config" || return 1
  # shellcheck disable=SC2016
  remote_exec 'chown -R $ADMIN_USERNAME:$ADMIN_USERNAME /home/$ADMIN_USERNAME/.config/bat' || return 1
}

# Configures ZSH files and default shell for admin user
_configure_zsh_files() {
  remote_copy "templates/zshrc" "/home/${ADMIN_USERNAME}/.zshrc" || return 1
  remote_copy "templates/p10k.zsh" "/home/${ADMIN_USERNAME}/.p10k.zsh" || return 1
  # shellcheck disable=SC2016
  remote_exec 'chown $ADMIN_USERNAME:$ADMIN_USERNAME /home/$ADMIN_USERNAME/.zshrc /home/$ADMIN_USERNAME/.p10k.zsh' || return 1
  # shellcheck disable=SC2016
  remote_exec 'chsh -s /bin/zsh '"$ADMIN_USERNAME"'' || return 1
}

# Configures chrony NTP service
_configure_chrony() {
  remote_exec "systemctl stop chrony" || true
  remote_copy "templates/chrony" "/etc/chrony/chrony.conf" || return 1
  remote_exec "systemctl enable chrony" || return 1
}

# Configures unattended-upgrades
_configure_unattended_upgrades() {
  remote_copy "templates/50unattended-upgrades" "/etc/apt/apt.conf.d/50unattended-upgrades" || return 1
  remote_copy "templates/20auto-upgrades" "/etc/apt/apt.conf.d/20auto-upgrades" || return 1
  remote_exec "systemctl enable unattended-upgrades" || return 1
}

# Configures CPU governor service
_configure_cpu_governor() {
  local governor="${CPU_GOVERNOR:-performance}"
  remote_copy "templates/cpupower.service" "/etc/systemd/system/cpupower.service" || return 1
  remote_exec "
    systemctl daemon-reload
    systemctl enable cpupower.service
    cpupower frequency-set -g '$governor' 2>/dev/null || true
  " || return 1
}

# Configures I/O scheduler udev rules
_configure_io_scheduler() {
  remote_copy "templates/60-io-scheduler.rules" "/etc/udev/rules.d/60-io-scheduler.rules" || return 1
  remote_exec "udevadm control --reload-rules && udevadm trigger" || return 1
}

# Removes Proxmox subscription notice
_remove_subscription_notice() {
  remote_copy "templates/remove-subscription-nag.sh" "/tmp/remove-subscription-nag.sh" || return 1
  remote_exec "chmod +x /tmp/remove-subscription-nag.sh && /tmp/remove-subscription-nag.sh && rm -f /tmp/remove-subscription-nag.sh" || return 1
}

# =============================================================================
# Private implementation functions
# =============================================================================

# Private implementation - configures base system
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

# Private implementation - configures default shell
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
    # shellcheck disable=SC2016 # Single quotes intentional - executed on remote system
    remote_run "Installing ZSH theme and plugins" '
            set -e
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /home/$ADMIN_USERNAME/.oh-my-zsh/custom/themes/powerlevel10k &
            pid1=$!
            git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /home/$ADMIN_USERNAME/.oh-my-zsh/custom/plugins/zsh-autosuggestions &
            pid2=$!
            git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /home/$ADMIN_USERNAME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting &
            pid3=$!
            wait $pid1 $pid2 $pid3
            chown -R $ADMIN_USERNAME:$ADMIN_USERNAME /home/$ADMIN_USERNAME/.oh-my-zsh
        ' "ZSH theme and plugins installed"

    run_with_progress "Configuring ZSH" "ZSH with Powerlevel10k configured" _configure_zsh_files
  else
    add_log "${CLR_ORANGE}├─${CLR_RESET} Default shell: Bash ${CLR_CYAN}✓${CLR_RESET}"
  fi
}

# Private implementation - configures system services
_config_system_services() {
  # Configure NTP time synchronization with chrony (package already installed)
  run_with_progress "Configuring chrony" "Chrony configured" _configure_chrony

  # Configure Unattended Upgrades (package already installed)
  run_with_progress "Configuring Unattended Upgrades" "Unattended Upgrades configured" _configure_unattended_upgrades

  # Configure nf_conntrack module (sysctl params already in 99-proxmox.conf.tmpl)
  remote_run "Configuring nf_conntrack" '
        if ! grep -q "nf_conntrack" /etc/modules 2>/dev/null; then
            echo "nf_conntrack" >> /etc/modules
        fi
    ' "nf_conntrack configured"

  # Configure CPU governor using linux-cpupower
  # Governor already validated by wizard (only shows available options)
  local governor="${CPU_GOVERNOR:-performance}"
  run_with_progress "Configuring CPU governor (${governor})" "CPU governor configured" _configure_cpu_governor

  # Configure I/O scheduler udev rules (NVMe: none, SSD: mq-deadline, HDD: bfq)
  run_with_progress "Configuring I/O scheduler" "I/O scheduler configured" _configure_io_scheduler

  # Remove Proxmox subscription notice (only for non-enterprise)
  if [[ ${PVE_REPO_TYPE:-no-subscription} != "enterprise" ]]; then
    log "configure_system_services: removing subscription notice (non-enterprise)"
    run_with_progress "Removing Proxmox subscription notice" "Subscription notice removed" _remove_subscription_notice
  fi
}

# =============================================================================
# Public wrappers
# =============================================================================

# Configures base system via SSH into QEMU VM.
# Copies templates, configures repositories, installs packages.
# Side effects: Modifies remote system configuration
configure_base_system() {
  _config_base_system
}

# Configures default shell for admin user.
# Optionally installs ZSH with Oh-My-Zsh and Powerlevel10k theme.
# Note: zsh, git, curl packages already installed via install_base_packages()
configure_shell() {
  _config_shell
}

# Configures system services: NTP, unattended upgrades, conntrack, CPU governor.
# Removes subscription notice for non-enterprise installations.
# Note: chrony, unattended-upgrades, linux-cpupower already installed via install_base_packages()
configure_system_services() {
  _config_system_services
}
