# shellcheck shell=bash
# =============================================================================
# Base system configuration via SSH
# =============================================================================

configure_base_system() {
    # Copy template files to VM
    (
        remote_copy "templates/hosts" "/etc/hosts"
        remote_copy "templates/interfaces" "/etc/network/interfaces"
        remote_copy "templates/99-proxmox.conf" "/etc/sysctl.d/99-proxmox.conf"
        remote_copy "templates/debian.sources" "/etc/apt/sources.list.d/debian.sources"
        remote_copy "templates/proxmox.sources" "/etc/apt/sources.list.d/proxmox.sources"
    ) > /dev/null 2>&1 &
    show_progress $! "Copying configuration files" "Configuration files copied"

    # Basic system configuration
    (
        remote_exec "[ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak"
        remote_exec "echo -e 'nameserver 1.1.1.1\nnameserver 1.0.0.1\nnameserver 8.8.8.8\nnameserver 8.8.4.4' > /etc/resolv.conf"
        remote_exec "echo '$PVE_HOSTNAME' > /etc/hostname"
        remote_exec "systemctl disable --now rpcbind rpcbind.socket 2>/dev/null"
    ) > /dev/null 2>&1 &
    show_progress $! "Applying basic system settings" "Basic system settings applied"

    # Configure ZFS ARC memory limits
    run_remote "Configuring ZFS ARC memory limits" '
        TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk "{print \$2}")
        TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))

        if [ $TOTAL_RAM_GB -ge 128 ]; then
            ARC_MIN=$((16 * 1024 * 1024 * 1024))
            ARC_MAX=$((64 * 1024 * 1024 * 1024))
        elif [ $TOTAL_RAM_GB -ge 64 ]; then
            ARC_MIN=$((8 * 1024 * 1024 * 1024))
            ARC_MAX=$((32 * 1024 * 1024 * 1024))
        elif [ $TOTAL_RAM_GB -ge 32 ]; then
            ARC_MIN=$((4 * 1024 * 1024 * 1024))
            ARC_MAX=$((16 * 1024 * 1024 * 1024))
        else
            ARC_MIN=$((1 * 1024 * 1024 * 1024))
            ARC_MAX=$((TOTAL_RAM_KB * 1024 / 2))
        fi

        mkdir -p /etc/modprobe.d
        echo "options zfs zfs_arc_min=$ARC_MIN" > /etc/modprobe.d/zfs.conf
        echo "options zfs zfs_arc_max=$ARC_MAX" >> /etc/modprobe.d/zfs.conf
    ' "ZFS ARC memory limits configured"

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

    # Install monitoring and system utilities
    run_remote "Installing system utilities" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq btop iotop ncdu tmux pigz smartmontools jq bat 2>/dev/null || {
            for pkg in btop iotop ncdu tmux pigz smartmontools jq bat; do
                apt-get install -yqq "$pkg" 2>/dev/null || true
            done
        }
        apt-get install -yqq libguestfs-tools 2>/dev/null || true
    ' "System utilities installed"

    # Configure UTF-8 locales (fix for btop and other apps)
    run_remote "Configuring UTF-8 locales" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq locales
        sed -i "s/# en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
        sed -i "s/# ru_RU.UTF-8/ru_RU.UTF-8/" /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

        # Create locale profile for all shells (fixes btop display issues)
        cat > /etc/profile.d/locale.sh << "LOCALEEOF"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
LOCALEEOF
        chmod +x /etc/profile.d/locale.sh

        # Also set in /etc/default/locale for systemd services
        cat > /etc/default/locale << "DEFLOCEOF"
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LANGUAGE=en_US.UTF-8
DEFLOCEOF

        # Set in /etc/environment for PAM (all sessions including non-login)
        cat > /etc/environment << "ENVEOF"
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LANGUAGE=en_US.UTF-8
ENVEOF
    ' "UTF-8 locales configured"
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

    # Configure CPU governor for maximum performance
    run_remote "Configuring CPU governor" '
        apt-get update -qq && apt-get install -yqq cpufrequtils 2>/dev/null || true
        echo "GOVERNOR=\"performance\"" > /etc/default/cpufrequtils
        systemctl enable cpufrequtils 2>/dev/null || true
        if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
            for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                [ -f "$cpu" ] && echo "performance" > "$cpu" 2>/dev/null || true
            done
        fi
    ' "CPU governor configured"

    # Remove Proxmox subscription notice (only for non-enterprise)
    if [[ "${PVE_REPO_TYPE:-no-subscription}" != "enterprise" ]]; then
        log "configure_system_services: removing subscription notice (non-enterprise)"
        run_remote "Removing Proxmox subscription notice" '
            if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then
                sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('"'"'No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
                systemctl restart pveproxy.service
            fi
        ' "Subscription notice removed"
    fi
}
