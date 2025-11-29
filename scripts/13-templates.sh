# shellcheck shell=bash
# =============================================================================
# Template preparation and download
# =============================================================================

make_templates() {
    log "Starting template preparation"
    mkdir -p ./templates
    local interfaces_template="interfaces.${BRIDGE_MODE:-internal}"
    log "Using interfaces template: $interfaces_template"

    # Download template files in background with progress
    (
        download_file "./templates/99-proxmox.conf" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/99-proxmox.conf"
        download_file "./templates/hosts" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/hosts"
        download_file "./templates/debian.sources" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/debian.sources"
        download_file "./templates/proxmox.sources" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/proxmox.sources"
        download_file "./templates/sshd_config" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/sshd_config"
        download_file "./templates/zshrc" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/zshrc"
        download_file "./templates/p10k.zsh" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/p10k.zsh"
        download_file "./templates/chrony" "https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/chrony"
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
