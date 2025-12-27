# SSL Certificates

Configure SSL certificates for the Proxmox Web UI.

## Available Options

| Option | Description |
|--------|-------------|
| Self-signed | Default Proxmox certificate (recommended for most users) |
| Let's Encrypt | Free auto-renewing certificate from Let's Encrypt |

> **Note:** SSL selection is only available when Tailscale is **not** enabled. Tailscale provides its own HTTPS via `tailscale serve`.

## Self-Signed Certificate (Default)

Uses Proxmox's built-in self-signed certificate. Works immediately but browsers show a security warning.

**Pros:**

- No external dependencies
- Works immediately
- No domain configuration required

**Cons:**

- Browser security warning on first visit
- Not suitable for production requiring trusted certificates

## Let's Encrypt Certificate

Automatically obtain a free, trusted SSL certificate with automatic renewal.

### Requirements

Before selecting Let's Encrypt, ensure:

1. **Domain resolves to server IP** - Your FQDN must resolve to the server's public IP
2. **Port 80 accessible** - HTTP challenge requires port 80 during issuance
3. **Valid email address** - Required for Let's Encrypt notifications

### DNS Validation

The installer validates DNS configuration before proceeding:

- Queries public DNS servers (Cloudflare, Google, Quad9)
- Verifies FQDN resolves to server's public IP

**On validation failure:**

```text
✗ DNS Error: proxmox.example.com does not resolve
ℹ Required: DNS A record proxmox.example.com → 88.99.12.34
ℹ Falling back to self-signed certificate.
```

**On success:**

```text
✓ SSL: Let's Encrypt (DNS verified: proxmox.example.com → 88.99.12.34)
```

### How It Works

1. **During Installation**
   - Certbot is installed
   - First-boot systemd service is configured
   - Deploy hook for auto-renewal is set up

2. **On First Boot**
   - First-boot service runs when server is accessible from internet
   - Certificate obtained via HTTP-01 challenge (port 80)
   - Certificate copied to Proxmox location
   - pveproxy restarted with new certificate
   - Marker file prevents re-running

3. **Auto-Renewal**
   - Systemd timer runs certbot renewal twice daily
   - Deploy hook copies renewed certificate to Proxmox
   - pveproxy automatically restarted

> **Why first boot?** During installation, the server runs inside QEMU in rescue mode. Port 80 is not accessible from the internet, so Let's Encrypt would fail. The first-boot service ensures the certificate is obtained when the server is operational.

### Certificate Locations

| File | Location |
|------|----------|
| Certificate | `/etc/pve/local/pveproxy-ssl.pem` |
| Private Key | `/etc/pve/local/pveproxy-ssl.key` |
| Let's Encrypt files | `/etc/letsencrypt/live/<domain>/` |
| First-boot script | `/usr/local/bin/obtain-letsencrypt-cert.sh` |
| First-boot log | `/var/log/letsencrypt-firstboot.log` |

### Verifying Certificate

After the first boot completes:

```bash
# Check first-boot service
systemctl status letsencrypt-firstboot.service

# Check first-boot log
cat /var/log/letsencrypt-firstboot.log

# Check certificate details
openssl x509 -in /etc/pve/local/pveproxy-ssl.pem -noout -issuer -dates

# Check certbot timer
systemctl status certbot.timer

# Test renewal (dry run)
certbot renew --dry-run
```

**Expected output for Let's Encrypt:**

```text
issuer=C = US, O = Let's Encrypt, CN = R3
notBefore=Nov 29 12:00:00 2024 GMT
notAfter=Feb 27 12:00:00 2025 GMT
```

### Troubleshooting

**First-boot certificate failed:**

```bash
# Check service logs
journalctl -u letsencrypt-firstboot.service

# Check detailed log
cat /var/log/letsencrypt-firstboot.log

# Check certbot logs
cat /var/log/letsencrypt/letsencrypt.log

# Verify domain resolves
dig +short your-domain.com

# Verify port 80 accessible
curl -I http://your-domain.com
```

**Re-run certificate obtainment:**

```bash
# Remove marker file
rm -f /etc/letsencrypt/.certificate-obtained

# Run script manually
/usr/local/bin/obtain-letsencrypt-cert.sh

# Or restart service
systemctl restart letsencrypt-firstboot.service
```

**Renewal failed:**

```bash
# Check certificates
certbot certificates

# Force renewal
certbot renew --force-renewal

# Check deploy hook
cat /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh
```

### Manual Certificate Installation

For certificates from other CAs:

```bash
# Copy certificate files
cp /path/to/fullchain.pem /etc/pve/local/pveproxy-ssl.pem
cp /path/to/privkey.pem /etc/pve/local/pveproxy-ssl.key

# Set permissions
chmod 640 /etc/pve/local/pveproxy-ssl.pem
chmod 600 /etc/pve/local/pveproxy-ssl.key

# Restart pveproxy
systemctl restart pveproxy
```

## Comparison

| Feature | Self-Signed | Let's Encrypt |
|---------|-------------|---------------|
| Browser warning | Yes | No |
| Auto-renewal | N/A | Yes (90 days) |
| Domain required | No | Yes |
| Port 80 required | No | Yes (issuance only) |
| External dependency | No | Yes (ACME servers) |
| Setup complexity | None | Low |

---

**Next:** [Tailscale Setup](Tailscale-Setup) | [Post-Installation](Post-Installation)
