# shellcheck shell=bash
# =============================================================================
# Base system configuration via SSH
# =============================================================================

configure_base_system() {
    # Copy template files to VM (parallel for better performance)
    remote_copy "templates/hosts" "/etc/hosts" > /dev/null 2>&1 &
    local pid1=$!
    remote_copy "templates/interfaces" "/etc/network/interfaces" > /dev/null 2>&1 &
    local pid2=$!
    remote_copy "templates/99-proxmox.conf" "/etc/sysctl.d/99-proxmox.conf" > /dev/null 2>&1 &
    local pid3=$!
    remote_copy "templates/debian.sources" "/etc/apt/sources.list.d/debian.sources" > /dev/null 2>&1 &
    local pid4=$!
    remote_copy "templates/proxmox.sources" "/etc/apt/sources.list.d/proxmox.sources" > /dev/null 2>&1 &
    local pid5=$!
    remote_copy "templates/resolv.conf" "/etc/resolv.conf" > /dev/null 2>&1 &
    local pid6=$!
    
    # Wait for all copies to complete and check each exit code
    local exit_code=0
    wait $pid1 || exit_code=1
    wait $pid2 || exit_code=1
    wait $pid3 || exit_code=1
    wait $pid4 || exit_code=1
    wait $pid5 || exit_code=1
    wait $pid6 || exit_code=1
    
    if [[ $exit_code -eq 0 ]]; then
        printf "\r\e[K${CLR_GREEN}✓ Configuration files copied${CLR_RESET}\n"
    else
        printf "\r\e[K${CLR_RED}✗ Copying configuration files${CLR_RESET}\n"
        log "ERROR: Failed to copy some configuration files"
        exit 1
    fi

    # Basic system configuration
    (
        remote_exec "[ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak"
        remote_exec "echo '$PVE_HOSTNAME' > /etc/hostname"
        remote_exec "systemctl disable --now rpcbind rpcbind.socket 2>/dev/null"
    ) > /dev/null 2>&1 &
    show_progress $! "Applying basic system settings" "Basic system settings applied"

    # Configure ZFS ARC memory limits using template script
    (
        remote_copy "templates/configure-zfs-arc.sh" "/tmp/configure-zfs-arc.sh"
        remote_exec "chmod +x /tmp/configure-zfs-arc.sh && /tmp/configure-zfs-arc.sh && rm -f /tmp/configure-zfs-arc.sh"
    ) > /dev/null 2>&1 &
    show_progress $! "Configuring ZFS ARC memory limits" "ZFS ARC memory limits configured"

    # Configure Proxmox repository
    log "configure_base_system: PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
    if [[ "${PVE_REPO_TYPE:-no-subscription}" == "enterprise" ]]; then
        log "configure_base_system: configuring enterprise repository"
        # Enterprise: disable default no-subscription repo (template already has enterprise)
        run_remote "Configuring enterprise repository" '
            for repo_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
                [ -f "$repo_file" ] || continue
                if grep -q "pve-no-subscription\|pvetest" "$repo_file" 2>/dev/null; then
                    mv "$repo_file" "${repo_file}.disabled"
                fi
            done
        ' "Enterprise repository configured"

        # Register subscription key if provided
        if [[ -n "$PVE_SUBSCRIPTION_KEY" ]]; then
            log "configure_base_system: registering subscription key"
            run_remote "Registering subscription key" \
                "pvesubscription set '${PVE_SUBSCRIPTION_KEY}' 2>/dev/null || true" \
                "Subscription key registered"
        fi
    else
        # No-subscription or test: disable enterprise repo
        log "configure_base_system: configuring ${PVE_REPO_TYPE:-no-subscription} repository"
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
    ) > "$pkg_output" &
    show_progress $! "Installing system utilities" "System utilities installed"

    # Check for failed packages and show warning to user
    if grep -q "FAILED_PACKAGES:" "$pkg_output" 2>/dev/null; then
        local failed_list
        failed_list=$(grep "FAILED_PACKAGES:" "$pkg_output" | sed 's/FAILED_PACKAGES://')
        print_warning "Some packages failed to install:$failed_list"
        log "WARNING: Failed to install packages:$failed_list"
    fi
    cat "$pkg_output" >> "$LOG_FILE"
    rm -f "$pkg_output"

    # Configure UTF-8 locales using template files
    run_remote "Configuring UTF-8 locales" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq locales
        sed -i "s/# en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
        sed -i "s/# ru_RU.UTF-8/ru_RU.UTF-8/" /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    ' "UTF-8 locales configured"

    # Copy locale template files
    (
        remote_copy "templates/locale.sh" "/etc/profile.d/locale.sh"
        remote_exec "chmod +x /etc/profile.d/locale.sh"
        remote_copy "templates/default-locale" "/etc/default/locale"
        remote_copy "templates/environment" "/etc/environment"
    ) > /dev/null 2>&1 &
    show_progress $! "Installing locale configuration files" "Locale files installed"

    # Configure fastfetch to run on shell login
    (
        remote_copy "templates/fastfetch.sh" "/etc/profile.d/fastfetch.sh"
        remote_exec "chmod +x /etc/profile.d/fastfetch.sh"
    ) > /dev/null 2>&1 &
    show_progress $! "Configuring fastfetch" "Fastfetch configured"
}

configure_shell() {
    # Configure default shell for root
    if [[ "$DEFAULT_SHELL" == "zsh" ]]; then
        run_remote "Installing ZSH and Git" '
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -yqq zsh git curl
        ' "ZSH and Git installed"

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
            remote_copy "templates/zshrc" "/root/.zshrc"
            remote_copy "templates/p10k.zsh" "/root/.p10k.zsh"
            remote_exec "chsh -s /bin/zsh root"
        ) > /dev/null 2>&1 &
        show_progress $! "Configuring ZSH" "ZSH with Powerlevel10k configured"
    else
        print_success "Bash configured as default shell"
    fi
}

configure_system_services() {
    # Configure NTP time synchronization with chrony
    run_remote "Installing NTP (chrony)" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq chrony
        systemctl stop chrony
    ' "NTP (chrony) installed"
    (
        remote_copy "templates/chrony" "/etc/chrony/chrony.conf"
        remote_exec "systemctl enable chrony && systemctl start chrony"
    ) > /dev/null 2>&1 &
    show_progress $! "Configuring chrony" "Chrony configured"

    # Configure Unattended Upgrades (security updates, kernel excluded)
    run_remote "Installing Unattended Upgrades" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq unattended-upgrades apt-listchanges
    ' "Unattended Upgrades installed"
    (
        remote_copy "templates/50unattended-upgrades" "/etc/apt/apt.conf.d/50unattended-upgrades"
        remote_copy "templates/20auto-upgrades" "/etc/apt/apt.conf.d/20auto-upgrades"
        remote_exec "systemctl enable unattended-upgrades"
    ) > /dev/null 2>&1 &
    show_progress $! "Configuring Unattended Upgrades" "Unattended Upgrades configured"

    # Configure nf_conntrack
    run_remote "Configuring nf_conntrack" '
        if ! grep -q "nf_conntrack" /etc/modules 2>/dev/null; then
            echo "nf_conntrack" >> /etc/modules
        fi

        if ! grep -q "nf_conntrack_max" /etc/sysctl.d/99-proxmox.conf 2>/dev/null; then
            echo "net.netfilter.nf_conntrack_max=1048576" >> /etc/sysctl.d/99-proxmox.conf
            echo "net.netfilter.nf_conntrack_tcp_timeout_established=28800" >> /etc/sysctl.d/99-proxmox.conf
        fi
    ' "nf_conntrack configured"

    # Configure CPU governor for maximum performance using template
    (
        remote_copy "templates/cpufrequtils" "/tmp/cpufrequtils"
        remote_exec '
            apt-get update -qq && apt-get install -yqq cpufrequtils 2>/dev/null || true
            mv /tmp/cpufrequtils /etc/default/cpufrequtils
            systemctl enable cpufrequtils 2>/dev/null || true
            if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
                for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                    [ -f "$cpu" ] && echo "performance" > "$cpu" 2>/dev/null || true
                done
            fi
        '
    ) > /dev/null 2>&1 &
    show_progress $! "Configuring CPU governor" "CPU governor configured"

    # Remove Proxmox subscription notice (only for non-enterprise)
    if [[ "${PVE_REPO_TYPE:-no-subscription}" != "enterprise" ]]; then
        log "configure_system_services: removing subscription notice (non-enterprise)"
        (
            remote_copy "templates/remove-subscription-nag.sh" "/tmp/remove-subscription-nag.sh"
            remote_exec "chmod +x /tmp/remove-subscription-nag.sh && /tmp/remove-subscription-nag.sh && rm -f /tmp/remove-subscription-nag.sh"
        ) > /dev/null 2>&1 &
        show_progress $! "Removing Proxmox subscription notice" "Subscription notice removed"
    fi
}
