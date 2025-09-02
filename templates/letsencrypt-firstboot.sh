#!/bin/bash
# First-boot Let's Encrypt certificate obtainment
# This script runs once on first boot when the server is accessible from internet

CERT_DOMAIN='{{CERT_DOMAIN}}'
CERT_EMAIL='{{CERT_EMAIL}}'
LOG_FILE='/var/log/letsencrypt-firstboot.log'
MARKER_FILE='/etc/letsencrypt/.certificate-obtained'

# Exit if certificate already obtained
if [[ -f "$MARKER_FILE" ]]; then
    echo "Certificate already obtained, skipping" >> "$LOG_FILE"
    exit 0
fi

echo "Starting Let's Encrypt certificate obtainment at $(date)" >> "$LOG_FILE"

# Wait for network to be fully ready
sleep 10

# Stop pveproxy to free port 443 (we'll use port 80 for challenge)
systemctl stop pveproxy 2>> "$LOG_FILE"

# Obtain certificate using standalone mode on port 80
certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email "$CERT_EMAIL" \
    --domain "$CERT_DOMAIN" \
    --preferred-challenges http \
    >> "$LOG_FILE" 2>&1

CERTBOT_EXIT=$?

if [[ $CERTBOT_EXIT -eq 0 ]]; then
    echo "Certificate obtained successfully" >> "$LOG_FILE"

    # Copy certificates to Proxmox location
    cp "/etc/letsencrypt/live/$CERT_DOMAIN/fullchain.pem" /etc/pve/local/pveproxy-ssl.pem
    cp "/etc/letsencrypt/live/$CERT_DOMAIN/privkey.pem" /etc/pve/local/pveproxy-ssl.key
    chmod 640 /etc/pve/local/pveproxy-ssl.pem
    chmod 600 /etc/pve/local/pveproxy-ssl.key

    # Create marker file
    touch "$MARKER_FILE"

    # Enable certbot timer for auto-renewal
    systemctl enable certbot.timer
    systemctl start certbot.timer

    echo "Certificate deployed to Proxmox" >> "$LOG_FILE"
else
    echo "Failed to obtain certificate (exit code: $CERTBOT_EXIT)" >> "$LOG_FILE"
    echo "Check /var/log/letsencrypt/letsencrypt.log for details" >> "$LOG_FILE"
fi

# Always restart pveproxy (with new cert or self-signed)
systemctl start pveproxy

echo "Completed at $(date)" >> "$LOG_FILE"
