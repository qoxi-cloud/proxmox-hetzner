# =============================================================================
# Post-installation configuration
# =============================================================================

make_templates() {
    mkdir -p ./templates
    local interfaces_template="interfaces.${BRIDGE_MODE:-internal}"

    # Download template files in background with progress
    (
        download_file "./templates/99-proxmox.conf" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/99-proxmox.conf"
        download_file "./templates/hosts" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/hosts"
        download_file "./templates/debian.sources" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/debian.sources"
        download_file "./templates/proxmox.sources" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/proxmox.sources"
        download_file "./templates/sshd_config" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/sshd_config"
        download_file "./templates/zshrc" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/zshrc"
        download_file "./templates/chrony" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/chrony"
        download_file "./templates/motd-dynamic" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/motd-dynamic"
        download_file "./templates/50unattended-upgrades" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/50unattended-upgrades"
        download_file "./templates/20auto-upgrades" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/20auto-upgrades"
        download_file "./templates/interfaces" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/${interfaces_template}"
    ) > /dev/null 2>&1 &
    show_progress $! "Downloading template files"

    # Modify template files in background with progress
    (
        sed -i "s|{{MAIN_IPV4}}|$MAIN_IPV4|g" ./templates/hosts
        sed -i "s|{{FQDN}}|$FQDN|g" ./templates/hosts
        sed -i "s|{{HOSTNAME}}|$PVE_HOSTNAME|g" ./templates/hosts
        sed -i "s|{{MAIN_IPV6}}|$MAIN_IPV6|g" ./templates/hosts
        sed -i "s|{{INTERFACE_NAME}}|$INTERFACE_NAME|g" ./templates/interfaces
        sed -i "s|{{MAIN_IPV4}}|$MAIN_IPV4|g" ./templates/interfaces
        sed -i "s|{{MAIN_IPV4_GW}}|$MAIN_IPV4_GW|g" ./templates/interfaces
        sed -i "s|{{MAIN_IPV6}}|$MAIN_IPV6|g" ./templates/interfaces
        sed -i "s|{{PRIVATE_IP_CIDR}}|$PRIVATE_IP_CIDR|g" ./templates/interfaces
        sed -i "s|{{PRIVATE_SUBNET}}|$PRIVATE_SUBNET|g" ./templates/interfaces
        sed -i "s|{{FIRST_IPV6_CIDR}}|$FIRST_IPV6_CIDR|g" ./templates/interfaces
    ) &
    show_progress $! "Modifying template files"
}

# Configure the installed Proxmox via SSH
configure_proxmox_via_ssh() {
    make_templates
    ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:5555" 2>/dev/null || true

    # Copy template files
    remote_copy "templates/hosts" "/etc/hosts"
    remote_copy "templates/interfaces" "/etc/network/interfaces"
    remote_copy "templates/99-proxmox.conf" "/etc/sysctl.d/99-proxmox.conf"
    remote_copy "templates/debian.sources" "/etc/apt/sources.list.d/debian.sources"
    remote_copy "templates/proxmox.sources" "/etc/apt/sources.list.d/proxmox.sources"

    # Basic system configuration
    remote_exec "[ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak"
    remote_exec "echo -e 'nameserver 1.1.1.1\nnameserver 1.0.0.1\nnameserver 8.8.8.8\nnameserver 8.8.4.4' > /etc/resolv.conf"
    remote_exec "echo '$PVE_HOSTNAME' > /etc/hostname"
    remote_exec "systemctl disable --now rpcbind rpcbind.socket 2>/dev/null"

    # Configure ZFS ARC memory limits
    remote_exec_with_progress "Configuring ZFS ARC memory limits" '
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

    # Disable enterprise repositories
    remote_exec_with_progress "Disabling enterprise repositories" '
        for repo_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
            [ -f "$repo_file" ] || continue
            if grep -q "enterprise.proxmox.com" "$repo_file" 2>/dev/null; then
                mv "$repo_file" "${repo_file}.disabled"
            fi
        done

        if [ -f /etc/apt/sources.list ] && grep -q "enterprise.proxmox.com" /etc/apt/sources.list 2>/dev/null; then
            sed -i "s|^deb.*enterprise.proxmox.com|# &|g" /etc/apt/sources.list
        fi
    ' "Enterprise repositories disabled"

    # Update all system packages
    remote_exec_with_progress "Updating system packages" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get dist-upgrade -yqq
        apt-get autoremove -yqq
        apt-get clean
        pveupgrade 2>/dev/null || true
        pveam update 2>/dev/null || true
    ' "System packages updated"

    # Install monitoring and system utilities
    remote_exec_with_progress "Installing system utilities" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq btop iotop ncdu tmux pigz smartmontools jq bat zsh zsh-autosuggestions zsh-syntax-highlighting 2>/dev/null || {
            for pkg in btop iotop ncdu tmux pigz smartmontools jq bat zsh zsh-autosuggestions zsh-syntax-highlighting; do
                apt-get install -yqq "$pkg" 2>/dev/null || true
            done
        }
        apt-get install -yqq libguestfs-tools 2>/dev/null || true
    ' "System utilities installed"

    # Configure UTF-8 locales (fix for btop and other apps)
    remote_exec_with_progress "Configuring UTF-8 locales" '
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

    # Configure ZSH as default shell for root
    (
        remote_copy "templates/zshrc" "/root/.zshrc"
        remote_exec "chsh -s /bin/zsh root"
    ) > /dev/null 2>&1 &
    show_progress $! "Configuring ZSH" "ZSH configured"

    # Configure NTP time synchronization with chrony
    remote_exec_with_progress "Installing NTP (chrony)" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq chrony
        systemctl stop chrony
    ' "NTP (chrony) installed"
    remote_copy "templates/chrony" "/etc/chrony/chrony.conf"
    remote_exec "systemctl enable chrony && systemctl start chrony" > /dev/null 2>&1

    # Configure dynamic MOTD
    (
        remote_exec "rm -f /etc/motd"
        remote_exec "chmod -x /etc/update-motd.d/* 2>/dev/null || true"
        remote_copy "templates/motd-dynamic" "/etc/update-motd.d/10-proxmox-status"
        remote_exec "chmod +x /etc/update-motd.d/10-proxmox-status"
    ) > /dev/null 2>&1 &
    show_progress $! "Configuring dynamic MOTD" "Dynamic MOTD configured"

    # Configure Unattended Upgrades (security updates, kernel excluded)
    remote_exec_with_progress "Installing Unattended Upgrades" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq unattended-upgrades apt-listchanges
    ' "Unattended Upgrades installed"
    remote_copy "templates/50unattended-upgrades" "/etc/apt/apt.conf.d/50unattended-upgrades"
    remote_copy "templates/20auto-upgrades" "/etc/apt/apt.conf.d/20auto-upgrades"
    remote_exec "systemctl enable unattended-upgrades" > /dev/null 2>&1

    # Configure nf_conntrack
    remote_exec_with_progress "Configuring nf_conntrack" '
        if ! grep -q "nf_conntrack" /etc/modules 2>/dev/null; then
            echo "nf_conntrack" >> /etc/modules
        fi

        if ! grep -q "nf_conntrack_max" /etc/sysctl.d/99-proxmox.conf 2>/dev/null; then
            echo "net.netfilter.nf_conntrack_max=1048576" >> /etc/sysctl.d/99-proxmox.conf
            echo "net.netfilter.nf_conntrack_tcp_timeout_established=28800" >> /etc/sysctl.d/99-proxmox.conf
        fi
    ' "nf_conntrack configured"

    # Configure CPU governor
    remote_exec_with_progress "Configuring CPU governor" '
        apt-get update -qq && apt-get install -yqq cpufrequtils 2>/dev/null || true
        echo "GOVERNOR=\"performance\"" > /etc/default/cpufrequtils
        if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
            for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                [ -f "$cpu" ] && echo "performance" > "$cpu" 2>/dev/null || true
            done
        fi
    ' "CPU governor configured"

    # Remove Proxmox subscription notice
    remote_exec_with_progress "Removing Proxmox subscription notice" '
        if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then
            sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('"'"'No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
            systemctl restart pveproxy.service
        fi
    ' "Subscription notice removed"

    # Install Tailscale if requested
    if [[ "$INSTALL_TAILSCALE" == "yes" ]]; then
        remote_exec_with_progress "Installing Tailscale VPN" '
            curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
            curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
            apt-get update -qq
            apt-get install -yqq tailscale
            systemctl enable tailscaled
            systemctl start tailscaled
        ' "Tailscale VPN installed"

        # Build tailscale up command with selected options
        TAILSCALE_UP_CMD="tailscale up"
        if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
            TAILSCALE_UP_CMD="$TAILSCALE_UP_CMD --authkey='$TAILSCALE_AUTH_KEY'"
        fi
        if [[ "$TAILSCALE_SSH" == "yes" ]]; then
            TAILSCALE_UP_CMD="$TAILSCALE_UP_CMD --ssh"
        fi

        # If auth key is provided, authenticate Tailscale
        if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
            (
                remote_exec "$TAILSCALE_UP_CMD"
                remote_exec "tailscale ip -4" > /tmp/tailscale_ip.txt 2>/dev/null
                remote_exec "tailscale status --json | grep -o '\"DNSName\":\"[^\"]*\"' | head -1 | cut -d'\"' -f4 | sed 's/\\.$//' " > /tmp/tailscale_hostname.txt 2>/dev/null
            ) > /dev/null 2>&1 &
            show_progress $! "Authenticating Tailscale"

            # Get Tailscale IP and hostname for display
            TAILSCALE_IP=$(cat /tmp/tailscale_ip.txt 2>/dev/null || echo "pending")
            TAILSCALE_HOSTNAME=$(cat /tmp/tailscale_hostname.txt 2>/dev/null || echo "")
            rm -f /tmp/tailscale_ip.txt /tmp/tailscale_hostname.txt
            # Overwrite completion line with IP
            printf "\033[1A\r${CLR_GREEN}✓ Tailscale authenticated. IP: ${TAILSCALE_IP}${CLR_RESET}                              \n"

            # Configure Tailscale Serve for Proxmox Web UI
            if [[ "$TAILSCALE_WEBUI" == "yes" ]]; then
                remote_exec "tailscale serve --bg --https=443 https://127.0.0.1:8006" > /dev/null 2>&1 &
                show_progress $! "Configuring Tailscale Serve" "Proxmox Web UI available via Tailscale Serve"
            fi
        else
            TAILSCALE_IP="not authenticated"
            TAILSCALE_HOSTNAME=""
            print_warning "Tailscale installed but not authenticated."
            print_info "After reboot, run these commands to enable SSH and Web UI:"
            print_info "  tailscale up --ssh"
            print_info "  tailscale serve --bg --https=443 https://127.0.0.1:8006"
        fi
    fi

    # Deploy SSH hardening LAST (after all other operations)
    (
        remote_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
        remote_exec "echo '$SSH_PUBLIC_KEY' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
        remote_copy "templates/sshd_config" "/etc/ssh/sshd_config"
    ) > /dev/null 2>&1 &
    show_progress $! "Deploying SSH hardening" "Security hardening configured"

    # Power off the VM
    remote_exec "poweroff" > /dev/null 2>&1 &
    show_progress $! "Powering off the VM"

    # Wait for QEMU to exit
    wait_with_progress "Waiting for QEMU process to exit" 120 "! kill -0 $QEMU_PID 2>/dev/null" 1 "QEMU process exited"
}
