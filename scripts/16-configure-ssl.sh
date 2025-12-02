# shellcheck shell=bash
# =============================================================================
# SSL certificate configuration via SSH
# =============================================================================

# Configures SSL certificates for Proxmox Web UI.
# For Let's Encrypt, sets up first-boot certificate acquisition.
# Side effects: Installs certbot, configures systemd service for cert renewal
configure_ssl_certificate() {
    log "configure_ssl_certificate: SSL_TYPE=$SSL_TYPE"

    # Skip if not using Let's Encrypt
    if [[ "$SSL_TYPE" != "letsencrypt" ]]; then
        log "configure_ssl_certificate: skipping (self-signed)"
        return 0
    fi

    # Build FQDN if not set
    local cert_domain="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
    log "configure_ssl_certificate: domain=$cert_domain, email=$EMAIL"

    # Install certbot (will be used on first boot)
    run_remote "Installing Certbot" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq certbot
    ' "Certbot installed"

    # Apply template substitutions locally before copying
    if ! apply_template_vars "./templates/letsencrypt-firstboot.sh" \
        "CERT_DOMAIN=${cert_domain}" \
        "CERT_EMAIL=${EMAIL}"; then
        log "ERROR: Failed to apply template variables to letsencrypt-firstboot.sh"
        exit 1
    fi

    # Copy Let's Encrypt templates to VM
    if ! remote_copy "./templates/letsencrypt-deploy-hook.sh" "/tmp/letsencrypt-deploy-hook.sh"; then
        log "ERROR: Failed to copy letsencrypt-deploy-hook.sh"
        exit 1
    fi
    if ! remote_copy "./templates/letsencrypt-firstboot.sh" "/tmp/letsencrypt-firstboot.sh"; then
        log "ERROR: Failed to copy letsencrypt-firstboot.sh"
        exit 1
    fi
    if ! remote_copy "./templates/letsencrypt-firstboot.service" "/tmp/letsencrypt-firstboot.service"; then
        log "ERROR: Failed to copy letsencrypt-firstboot.service"
        exit 1
    fi

    # Configure first-boot certificate script
    run_remote "Configuring Let's Encrypt templates" '
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy

        # Install deploy hook for renewals
        mv /tmp/letsencrypt-deploy-hook.sh /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh

        # Install first-boot script (already has substituted values)
        mv /tmp/letsencrypt-firstboot.sh /usr/local/bin/obtain-letsencrypt-cert.sh
        chmod +x /usr/local/bin/obtain-letsencrypt-cert.sh

        # Install and enable systemd service
        mv /tmp/letsencrypt-firstboot.service /etc/systemd/system/letsencrypt-firstboot.service
        systemctl daemon-reload
        systemctl enable letsencrypt-firstboot.service
    ' "First-boot certificate service configured"

    # Store the domain for summary
    LETSENCRYPT_DOMAIN="$cert_domain"
    LETSENCRYPT_FIRSTBOOT=true
}
