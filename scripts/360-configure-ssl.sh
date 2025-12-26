# shellcheck shell=bash
# SSL certificate configuration via SSH

# Private implementation - configures SSL certificates
# Called by configure_ssl() public wrapper
_config_ssl() {
  log "_config_ssl: SSL_TYPE=$SSL_TYPE"

  # Build FQDN if not set
  local cert_domain="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
  log "_config_ssl: domain=$cert_domain, email=$EMAIL"

  # Deploy Let's Encrypt templates to /tmp (moved to final locations by remote_run)
  deploy_template "templates/letsencrypt-firstboot.sh" "/tmp/letsencrypt-firstboot.sh" \
    "CERT_DOMAIN=${cert_domain}" "CERT_EMAIL=${EMAIL}" || return 1

  remote_copy "templates/letsencrypt-deploy-hook.sh" "/tmp/letsencrypt-deploy-hook.sh" || return 1
  remote_copy "templates/letsencrypt-firstboot.service" "/tmp/letsencrypt-firstboot.service" || return 1

  # Install deploy hook, first-boot script, and systemd service
  remote_run "Configuring Let's Encrypt templates" '
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

# Public wrapper (generated via factory)
# Configures SSL certificates for Proxmox Web UI.
# For Let's Encrypt, sets up first-boot certificate acquisition.
# Certbot package installed via batch_install_packages() in 037-parallel-helpers.sh
make_condition_wrapper "ssl" "SSL_TYPE" "letsencrypt"

# Alias for backwards compatibility (called as configure_ssl_certificate in 381-configure-phases.sh)
configure_ssl_certificate() { configure_ssl; }
