# shellcheck shell=bash
# =============================================================================
# SSL certificate configuration via SSH
# =============================================================================

# Configures SSL certificates for Proxmox Web UI.
# For Let's Encrypt, sets up first-boot certificate acquisition.
# Certbot package installed via batch_install_packages() in 037-parallel-helpers.sh
# Side effects: Configures systemd service for cert renewal
configure_ssl_certificate() {
  log "configure_ssl_certificate: SSL_TYPE=$SSL_TYPE"

  # Skip if not using Let's Encrypt
  if [[ $SSL_TYPE != "letsencrypt" ]]; then
    log "configure_ssl_certificate: skipping (self-signed)"
    return 0
  fi

  # Build FQDN if not set
  local cert_domain="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
  log "configure_ssl_certificate: domain=$cert_domain, email=$EMAIL"

  # Apply template substitutions locally before copying
  if ! apply_template_vars "./templates/letsencrypt-firstboot.sh" \
    "CERT_DOMAIN=${cert_domain}" \
    "CERT_EMAIL=${EMAIL}"; then
    log "ERROR: Failed to apply template variables to letsencrypt-firstboot.sh"
    return 1
  fi

  # Copy Let's Encrypt templates to VM
  if ! remote_copy "./templates/letsencrypt-deploy-hook.sh" "/tmp/letsencrypt-deploy-hook.sh"; then
    log "ERROR: Failed to copy letsencrypt-deploy-hook.sh"
    return 1
  fi
  if ! remote_copy "./templates/letsencrypt-firstboot.sh" "/tmp/letsencrypt-firstboot.sh"; then
    log "ERROR: Failed to copy letsencrypt-firstboot.sh"
    return 1
  fi
  if ! remote_copy "./templates/letsencrypt-firstboot.service" "/tmp/letsencrypt-firstboot.service"; then
    log "ERROR: Failed to copy letsencrypt-firstboot.service"
    return 1
  fi

  # Install deploy hook, first-boot script, and systemd service
  run_remote "Configuring Let's Encrypt templates" '
        set -e
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        mv /tmp/letsencrypt-deploy-hook.sh /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh
        mv /tmp/letsencrypt-firstboot.sh /usr/local/bin/obtain-letsencrypt-cert.sh
        chmod +x /usr/local/bin/obtain-letsencrypt-cert.sh
        mv /tmp/letsencrypt-firstboot.service /etc/systemd/system/letsencrypt-firstboot.service
        systemctl daemon-reload
        systemctl enable letsencrypt-firstboot.service
    ' "First-boot certificate service configured"

  # Store the domain for summary
  LETSENCRYPT_DOMAIN="$cert_domain"
  LETSENCRYPT_FIRSTBOOT=true
}
