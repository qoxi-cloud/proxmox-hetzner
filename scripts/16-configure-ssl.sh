# shellcheck shell=bash
# =============================================================================
# SSL certificate configuration via SSH
# =============================================================================

configure_ssl_certificate() {
    log "configure_ssl_certificate: SSL_TYPE=$SSL_TYPE"

    # Skip if not using Let's Encrypt
    if [[ "$SSL_TYPE" != "letsencrypt" ]]; then
        log "configure_ssl_certificate: skipping (self-signed)"
        return 0
    fi

    # Build FQDN if not set
    local cert_domain="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
    log "configure_ssl_certificate: domain=$cert_domain"

    # Install certbot (will be used on first boot)
    run_remote "Installing Certbot" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq certbot
    ' "Certbot installed"

    # Download and configure first-boot certificate script
    run_remote "Downloading Let's Encrypt templates" "
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy

        # Download deploy hook for renewals
        curl -fsSL '$TEMPLATE_BASE_URL/letsencrypt-deploy-hook.sh' \
            -o /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh

        # Download first-boot script
        curl -fsSL '$TEMPLATE_BASE_URL/letsencrypt-firstboot.sh' \
            -o /usr/local/bin/obtain-letsencrypt-cert.sh

        # Substitute placeholders
        sed -i 's|{{CERT_DOMAIN}}|${cert_domain}|g' /usr/local/bin/obtain-letsencrypt-cert.sh
        sed -i 's|{{CERT_EMAIL}}|${EMAIL}|g' /usr/local/bin/obtain-letsencrypt-cert.sh
        chmod +x /usr/local/bin/obtain-letsencrypt-cert.sh

        # Download and enable systemd service
        curl -fsSL '$TEMPLATE_BASE_URL/letsencrypt-firstboot.service' \
            -o /etc/systemd/system/letsencrypt-firstboot.service
        systemctl daemon-reload
        systemctl enable letsencrypt-firstboot.service
    " "First-boot certificate service configured"

    # Store the domain for summary
    LETSENCRYPT_DOMAIN="$cert_domain"
    LETSENCRYPT_FIRSTBOOT=true
}
