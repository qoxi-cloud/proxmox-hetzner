# shellcheck shell=bash
# =============================================================================
# Template preparation and download
# =============================================================================

make_templates() {
    log "Starting template preparation"
    mkdir -p ./templates
    local interfaces_template="interfaces.${BRIDGE_MODE:-internal}"
    log "Using interfaces template: $interfaces_template"

    # Select Proxmox repository template based on PVE_REPO_TYPE
    local proxmox_sources_template="proxmox.sources"
    case "${PVE_REPO_TYPE:-no-subscription}" in
        enterprise) proxmox_sources_template="proxmox-enterprise.sources" ;;
        test)       proxmox_sources_template="proxmox-test.sources" ;;
    esac
    log "Using repository template: $proxmox_sources_template"

    # Download template files in background with progress
    (
        download_template "./templates/99-proxmox.conf"
        download_template "./templates/hosts"
        download_template "./templates/debian.sources"
        download_template "./templates/proxmox.sources" "$proxmox_sources_template"
        download_template "./templates/sshd_config"
        download_template "./templates/zshrc"
        download_template "./templates/p10k.zsh"
        download_template "./templates/chrony"
        download_template "./templates/50unattended-upgrades"
        download_template "./templates/20auto-upgrades"
        download_template "./templates/interfaces" "$interfaces_template"
        download_template "./templates/resolv.conf"
        download_template "./templates/configure-zfs-arc.sh"
        download_template "./templates/locale.sh"
        download_template "./templates/default-locale"
        download_template "./templates/environment"
        download_template "./templates/cpufrequtils"
        download_template "./templates/remove-subscription-nag.sh"
        # Let's Encrypt templates
        download_template "./templates/letsencrypt-deploy-hook.sh"
        download_template "./templates/letsencrypt-firstboot.sh"
        download_template "./templates/letsencrypt-firstboot.service"
    ) > /dev/null 2>&1 &
    show_progress $! "Downloading template files"

    # Modify template files in background with progress
    (
        apply_common_template_vars "./templates/hosts"
        apply_common_template_vars "./templates/interfaces"
        apply_common_template_vars "./templates/resolv.conf"
    ) &
    show_progress $! "Modifying template files"
}
