# shellcheck shell=bash
# =============================================================================
# Base system configuration via SSH
# =============================================================================

# Configures base system via SSH into QEMU VM.
# Copies templates, configures repositories, installs packages.
# Side effects: Modifies remote system configuration
configure_base_system() {
  # Copy template files to VM (parallel for better performance)
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

  # Wait for all copies to complete
  local exit_code=0
  for pid in "${copy_pids[@]}"; do
    wait "$pid" || exit_code=1
  done

  if [[ $exit_code -eq 0 ]]; then
    printf '\r\e[K%s✓ Configuration files copied%s\n' "${CLR_CYAN}" "${CLR_RESET}"
  else
    printf '\r\e[K%s✗ Copying configuration files%s\n' "${CLR_RED}" "${CLR_RESET}"
    log "ERROR: Failed to copy some configuration files"
    return 1
  fi

  # Basic system configuration
  (
    remote_exec "[ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak" || exit 1
    remote_exec "echo '$PVE_HOSTNAME' > /etc/hostname" || exit 1
    remote_exec "systemctl disable --now rpcbind rpcbind.socket 2>/dev/null" || true
  ) >/dev/null 2>&1 &
  show_progress $! "Applying basic system settings" "Basic system settings applied"

  # Configure ZFS ARC memory limits using template script
  (
    remote_copy "templates/configure-zfs-arc.sh" "/tmp/configure-zfs-arc.sh" || exit 1
    remote_exec "chmod +x /tmp/configure-zfs-arc.sh && /tmp/configure-zfs-arc.sh && rm -f /tmp/configure-zfs-arc.sh" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring ZFS ARC memory limits" "ZFS ARC memory limits configured"

  # Configure Proxmox repository
  log "configure_base_system: PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
  if [[ ${PVE_REPO_TYPE:-no-subscription} == "enterprise" ]]; then
    log "configure_base_system: configuring enterprise repository"
    # Enterprise: disable default no-subscription repo (template already has enterprise)
    # shellcheck disable=SC2016 # Single quotes intentional - executed on remote system
    run_remote "Configuring enterprise repository" '
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
      run_remote "Registering subscription key" \
        "pvesubscription set '${PVE_SUBSCRIPTION_KEY}' 2>/dev/null || true" \
        "Subscription key registered"
    fi
  else
    # No-subscription or test: disable enterprise repo
    log "configure_base_system: configuring ${PVE_REPO_TYPE:-no-subscription} repository"
    # shellcheck disable=SC2016 # Single quotes intentional - executed on remote system
    run_remote "Configuring ${PVE_REPO_TYPE:-no-subscription} repository" '
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

  # Update all system packages
  run_remote "Updating system packages" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get dist-upgrade -yqq
        apt-get autoremove -yqq
        apt-get clean
        pveupgrade 2>/dev/null || true
        pveam update 2>/dev/null || true
    ' "System packages updated"

  # Install monitoring and system utilities (with individual package error reporting)
  local pkg_output
  pkg_output=$(mktemp)
  # shellcheck disable=SC2086
  (
    remote_exec "
            export DEBIAN_FRONTEND=noninteractive
            failed_pkgs=''
            for pkg in ${SYSTEM_UTILITIES}; do
                if ! apt-get install -yqq \"\$pkg\" 2>&1; then
                    failed_pkgs=\"\${failed_pkgs} \$pkg\"
                fi
            done
            for pkg in ${OPTIONAL_PACKAGES}; do
                apt-get install -yqq \"\$pkg\" 2>/dev/null || true
            done
            if [[ -n \"\$failed_pkgs\" ]]; then
                echo \"FAILED_PACKAGES:\$failed_pkgs\"
            fi
        " 2>&1
  ) >"$pkg_output" &
  show_progress $! "Installing system utilities" "System utilities installed"

  # Check for failed packages and show warning to user
  if grep -q "FAILED_PACKAGES:" "$pkg_output" 2>/dev/null; then
    local failed_list
    failed_list=$(grep "FAILED_PACKAGES:" "$pkg_output" | sed 's/FAILED_PACKAGES://')
    print_warning "Some packages failed to install:$failed_list" true
    log "WARNING: Failed to install packages:$failed_list"
  fi
  cat "$pkg_output" >>"$LOG_FILE"
  rm -f "$pkg_output"

  # Configure UTF-8 locales using template files
  # Generate the user's selected locale plus common fallbacks
  local locale_name="${LOCALE%%.UTF-8}" # Remove .UTF-8 suffix for sed pattern
  run_remote "Configuring UTF-8 locales" "
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq locales
        # Enable user's selected locale
        sed -i 's/# ${locale_name}.UTF-8/${locale_name}.UTF-8/' /etc/locale.gen
        # Also enable en_US as fallback (many tools expect it)
        sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
        locale-gen
        update-locale LANG=${LOCALE} LC_ALL=${LOCALE}
    " "UTF-8 locales configured"

  # Copy locale template files
  (
    remote_copy "templates/locale.sh" "/etc/profile.d/locale.sh" || exit 1
    remote_exec "chmod +x /etc/profile.d/locale.sh" || exit 1
    remote_copy "templates/default-locale" "/etc/default/locale" || exit 1
    remote_copy "templates/environment" "/etc/environment" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing locale configuration files" "Locale files installed"

  # Configure fastfetch to run on shell login
  (
    remote_copy "templates/fastfetch.sh" "/etc/profile.d/fastfetch.sh" || exit 1
    remote_exec "chmod +x /etc/profile.d/fastfetch.sh" || exit 1
    # Also source from bash.bashrc for non-login interactive shells
    remote_exec "grep -q 'profile.d/fastfetch.sh' /etc/bash.bashrc || echo '[ -f /etc/profile.d/fastfetch.sh ] && . /etc/profile.d/fastfetch.sh' >> /etc/bash.bashrc" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring fastfetch" "Fastfetch configured"

  # Configure bat with Visual Studio Dark+ theme
  (
    remote_exec "mkdir -p /root/.config/bat" || exit 1
    remote_copy "templates/bat-config" "/root/.config/bat/config" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring bat" "Bat configured"
}

# Configures default shell for root user.
# Optionally installs ZSH with Oh-My-Zsh and Powerlevel10k theme.
configure_shell() {
  # Configure default shell for root
  if [[ $SHELL_TYPE == "zsh" ]]; then
    run_remote "Installing ZSH and Git" '
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -yqq zsh git curl
        ' "ZSH and Git installed"

    # shellcheck disable=SC2016 # Single quotes intentional - executed on remote system
    run_remote "Installing Oh-My-Zsh" '
            export RUNZSH=no
            export CHSH=no
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        ' "Oh-My-Zsh installed"

    run_remote "Installing Powerlevel10k theme" '
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/.oh-my-zsh/custom/themes/powerlevel10k
        ' "Powerlevel10k theme installed"

    run_remote "Installing ZSH plugins" '
            git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions
            git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
        ' "ZSH plugins installed"

    (
      remote_copy "templates/zshrc" "/root/.zshrc" || exit 1
      remote_copy "templates/p10k.zsh" "/root/.p10k.zsh" || exit 1
      remote_exec "chsh -s /bin/zsh root" || exit 1
    ) >/dev/null 2>&1 &
    show_progress $! "Configuring ZSH" "ZSH with Powerlevel10k configured"
  else
    print_success "Default shell:" "Bash"
  fi
}

# Configures system services: NTP, unattended upgrades, conntrack, CPU governor.
# Removes subscription notice for non-enterprise installations.
configure_system_services() {
  # Configure NTP time synchronization with chrony
  run_remote "Installing NTP (chrony)" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq chrony
        systemctl stop chrony
    ' "NTP (chrony) installed"
  (
    remote_copy "templates/chrony" "/etc/chrony/chrony.conf" || exit 1
    # Enable chrony to start on boot (don't start now - will activate after reboot)
    remote_exec "systemctl enable chrony" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring chrony" "Chrony configured"

  # Configure Unattended Upgrades (security updates, kernel excluded)
  run_remote "Installing Unattended Upgrades" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq unattended-upgrades apt-listchanges
    ' "Unattended Upgrades installed"
  (
    remote_copy "templates/50unattended-upgrades" "/etc/apt/apt.conf.d/50unattended-upgrades" || exit 1
    remote_copy "templates/20auto-upgrades" "/etc/apt/apt.conf.d/20auto-upgrades" || exit 1
    remote_exec "systemctl enable unattended-upgrades" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring Unattended Upgrades" "Unattended Upgrades configured"

  # Configure nf_conntrack module (sysctl params already in 99-proxmox.conf.tmpl)
  run_remote "Configuring nf_conntrack" '
        if ! grep -q "nf_conntrack" /etc/modules 2>/dev/null; then
            echo "nf_conntrack" >> /etc/modules
        fi
    ' "nf_conntrack configured"

  # Configure CPU governor using template
  local governor="${CPU_GOVERNOR:-performance}"
  (
    remote_copy "templates/cpufrequtils" "/tmp/cpufrequtils" || exit 1
    remote_exec "
            apt-get update -qq && apt-get install -yqq cpufrequtils 2>/dev/null || true
            mv /tmp/cpufrequtils /etc/default/cpufrequtils
            systemctl enable cpufrequtils 2>/dev/null || true
            if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
                for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                    [ -f \"\$cpu\" ] && echo '$governor' > \"\$cpu\" 2>/dev/null || true
                done
            fi
        " || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring CPU governor (${governor})" "CPU governor configured"

  # Configure I/O scheduler udev rules (NVMe: none, SSD: mq-deadline, HDD: bfq)
  (
    remote_copy "templates/60-io-scheduler.rules" "/etc/udev/rules.d/60-io-scheduler.rules" || exit 1
    remote_exec "udevadm control --reload-rules && udevadm trigger" || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Configuring I/O scheduler" "I/O scheduler configured"

  # Remove Proxmox subscription notice (only for non-enterprise)
  if [[ ${PVE_REPO_TYPE:-no-subscription} != "enterprise" ]]; then
    log "configure_system_services: removing subscription notice (non-enterprise)"
    (
      remote_copy "templates/remove-subscription-nag.sh" "/tmp/remove-subscription-nag.sh" || exit 1
      remote_exec "chmod +x /tmp/remove-subscription-nag.sh && /tmp/remove-subscription-nag.sh && rm -f /tmp/remove-subscription-nag.sh" || exit 1
    ) >/dev/null 2>&1 &
    show_progress $! "Removing Proxmox subscription notice" "Subscription notice removed"
  fi
}
