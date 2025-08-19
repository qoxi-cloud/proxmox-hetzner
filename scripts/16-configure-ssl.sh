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

    # Install certbot and obtain certificate
    if ! remote_exec_with_progress "Installing Certbot" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq certbot
    ' "Certbot installed"; then
        print_error "Failed to install Certbot. Check log file: $LOG_FILE"
        exit 1
    fi

    # Stop pveproxy temporarily to free port 8006 and use standalone mode on port 80
    if ! remote_exec_with_progress "Obtaining Let's Encrypt certificate" "
        systemctl stop pveproxy

        # Obtain certificate using standalone mode (port 80)
        certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email '${EMAIL}' \
            --domain '${cert_domain}' \
            --preferred-challenges http \
            || { systemctl start pveproxy; exit 1; }

        # Copy certificates to Proxmox location
        cp /etc/letsencrypt/live/${cert_domain}/fullchain.pem /etc/pve/local/pveproxy-ssl.pem
        cp /etc/letsencrypt/live/${cert_domain}/privkey.pem /etc/pve/local/pveproxy-ssl.key

        # Set proper permissions
        chmod 640 /etc/pve/local/pveproxy-ssl.pem
        chmod 600 /etc/pve/local/pveproxy-ssl.key

        systemctl start pveproxy
    " "Let's Encrypt certificate obtained"; then
        print_error "Failed to obtain Let's Encrypt certificate. Check log file: $LOG_FILE"
        exit 1
    fi

    # Setup auto-renewal with deploy hook
    if ! remote_exec_with_progress "Configuring certificate auto-renewal" "
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy

        cat > /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh << HOOKEOF
#!/bin/bash
# Deploy renewed certificate to Proxmox
cp /etc/letsencrypt/live/${cert_domain}/fullchain.pem /etc/pve/local/pveproxy-ssl.pem
cp /etc/letsencrypt/live/${cert_domain}/privkey.pem /etc/pve/local/pveproxy-ssl.key
chmod 640 /etc/pve/local/pveproxy-ssl.pem
chmod 600 /etc/pve/local/pveproxy-ssl.key
systemctl restart pveproxy
HOOKEOF

        chmod +x /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh

        # Enable certbot timer for auto-renewal
        systemctl enable certbot.timer
        systemctl start certbot.timer
    " "Auto-renewal configured"; then
        print_error "Failed to configure auto-renewal. Check log file: $LOG_FILE"
        exit 1
    fi

    # Store the domain for summary
    LETSENCRYPT_DOMAIN="$cert_domain"
}
