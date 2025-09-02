#!/bin/bash
# Deploy renewed certificate to Proxmox
# Find first certificate directory (excluding README)
for dir in /etc/letsencrypt/live/*/; do
    DOMAIN=$(basename "$dir")
    if [[ "$DOMAIN" != "README" ]]; then
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/pve/local/pveproxy-ssl.pem
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" /etc/pve/local/pveproxy-ssl.key
        chmod 640 /etc/pve/local/pveproxy-ssl.pem
        chmod 600 /etc/pve/local/pveproxy-ssl.key
        systemctl restart pveproxy
        break
    fi
done
