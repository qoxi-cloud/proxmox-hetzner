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
        download_template "./templates/99-proxmox.conf" || exit 1
        download_template "./templates/hosts" || exit 1
        download_template "./templates/debian.sources" || exit 1
        download_template "./templates/proxmox.sources" "$proxmox_sources_template" || exit 1
        download_template "./templates/sshd_config" || exit 1
        download_template "./templates/zshrc" || exit 1
        download_template "./templates/p10k.zsh" || exit 1
        download_template "./templates/chrony" || exit 1
        download_template "./templates/50unattended-upgrades" || exit 1
        download_template "./templates/20auto-upgrades" || exit 1
        download_template "./templates/interfaces" "$interfaces_template" || exit 1
        download_template "./templates/resolv.conf" || exit 1
        download_template "./templates/configure-zfs-arc.sh" || exit 1
        download_template "./templates/locale.sh" || exit 1
        download_template "./templates/default-locale" || exit 1
        download_template "./templates/environment" || exit 1
        download_template "./templates/cpufrequtils" || exit 1
        download_template "./templates/remove-subscription-nag.sh" || exit 1
        # Let's Encrypt templates
        download_template "./templates/letsencrypt-deploy-hook.sh" || exit 1
        download_template "./templates/letsencrypt-firstboot.sh" || exit 1
        download_template "./templates/letsencrypt-firstboot.service" || exit 1
    ) > /dev/null 2>&1 &
    if ! show_progress $! "Downloading template files"; then
        log "ERROR: Failed to download template files"
        exit 1
    fi

    # Modify template files in background with progress
    (
        apply_common_template_vars "./templates/hosts"
        apply_common_template_vars "./templates/interfaces"
        apply_common_template_vars "./templates/resolv.conf"
    ) &
    show_progress $! "Modifying template files"
}
