# SSL Certificates

Configure SSL certificates for the Proxmox Web UI.

## Available Options

| Option | Description |
|--------|-------------|
| `self-signed` | Default Proxmox certificate (recommended for most users) |
| `letsencrypt` | Free auto-renewing certificate from Let's Encrypt |

> **Note:** SSL certificate selection is only available when Tailscale is **not** enabled. Tailscale provides its own HTTPS via `tailscale serve`.

## Self-Signed Certificate (Default)

The default option uses Proxmox's built-in self-signed certificate. This works out of the box but browsers will show a security warning.

**Pros:**

- No external dependencies
- Works immediately
- No domain configuration required

**Cons:**

- Browser security warning on first visit
- Not suitable for production environments requiring trusted certificates

## Let's Encrypt Certificate

Automatically obtain a free, trusted SSL certificate from Let's Encrypt with automatic renewal.

### Requirements

Before selecting Let's Encrypt, ensure:

1. **Domain resolves to server IP** - Your FQDN (hostname.domain) must resolve to the server's public IP address
2. **Port 80 accessible** - HTTP challenge requires port 80 to be open during certificate issuance
3. **Valid email address** - Required for Let's Encrypt notifications

### DNS Validation

The installer automatically validates DNS configuration before proceeding with Let's Encrypt:

- Queries public DNS servers (Cloudflare 1.1.1.1, Google 8.8.8.8, Quad9 9.9.9.9) to bypass local cache
- Verifies that your FQDN resolves to the server's public IP address

**Interactive mode:**

If DNS validation fails, the installer retries 3 times with 10-second intervals, then exits with instructions:

```text
✗ DNS Error: proxmox.example.com does not resolve
ℹ Required: DNS A record proxmox.example.com → 88.99.12.34
ℹ Retrying in 10 seconds... (Press Ctrl+C to cancel)
...
✗ DNS validation failed after 3 attempts
✗ Let's Encrypt requires proxmox.example.com to resolve to 88.99.12.34

ℹ To fix this:
ℹ   1. Go to your DNS provider
ℹ   2. Create/update A record: proxmox.example.com → 88.99.12.34
ℹ   3. Wait for DNS propagation (usually 1-5 minutes)
ℹ   4. Run this installer again
```

**Non-interactive mode:**

DNS validation fails immediately without retries if the domain doesn't resolve correctly.

**On success:**

```text
✓ SSL: Let's Encrypt (DNS verified: proxmox.example.com → 88.99.12.34)
```

### How It Works

1. **During Installation**
   - Certbot is installed on the server
   - First-boot systemd service (`letsencrypt-firstboot.service`) is configured
   - Deploy hook for auto-renewal is set up

2. **On First Boot** (after server reboot from rescue mode)
   - The first-boot service runs automatically when the server is accessible from the internet
   - pveproxy is temporarily stopped to free port 80
   - Certificate is obtained via HTTP-01 challenge (port 80)
   - Certificate is copied to Proxmox location (`/etc/pve/local/pveproxy-ssl.pem`)
   - pveproxy is restarted with the new certificate
   - Marker file is created to prevent re-running

3. **Auto-Renewal**
   - Systemd timer runs certbot renewal twice daily
   - Deploy hook automatically copies renewed certificate to Proxmox
   - pveproxy is restarted after renewal

> **Why first boot?** During installation, the server runs inside QEMU in Hetzner Rescue System. Port 80 is not accessible from the internet, so Let's Encrypt HTTP-01 challenge would fail. The first-boot service ensures the certificate is obtained when the server is fully operational.

### Certificate Locations

| File | Location |
|------|----------|
| Certificate | `/etc/pve/local/pveproxy-ssl.pem` |
| Private Key | `/etc/pve/local/pveproxy-ssl.key` |
| Let's Encrypt files | `/etc/letsencrypt/live/<domain>/` |
| First-boot script | `/usr/local/bin/obtain-letsencrypt-cert.sh` |
| First-boot log | `/var/log/letsencrypt-firstboot.log` |
| Marker file | `/etc/letsencrypt/.certificate-obtained` |

### Configuration

**Interactive mode:**

Select "Let's Encrypt" from the SSL Certificate menu. The installer will use your configured FQDN (hostname + domain suffix).

**Non-interactive mode:**

```bash
cat > proxmox.conf << 'EOF'
SSL_TYPE=letsencrypt
PVE_HOSTNAME=proxmox
DOMAIN_SUFFIX=example.com
EMAIL=admin@example.com
EOF

bash pve-install.sh -c proxmox.conf -n
```

### Verifying Certificate

After the first boot completes, verify your certificate:

```bash
# Check first-boot service status
systemctl status letsencrypt-firstboot.service

# Check first-boot log
cat /var/log/letsencrypt-firstboot.log

# Check certificate issuer and dates
openssl x509 -in /etc/pve/local/pveproxy-ssl.pem -noout -issuer -dates

# Check certbot timer status
systemctl status certbot.timer

# Test renewal (dry run)
certbot renew --dry-run
```

**Expected output for Let's Encrypt:**

```
issuer=C = US, O = Let's Encrypt, CN = R3
notBefore=Nov 29 12:00:00 2024 GMT
notAfter=Feb 27 12:00:00 2025 GMT
```

### Troubleshooting

**First-boot certificate failed:**

```bash
# Check first-boot service logs
journalctl -u letsencrypt-firstboot.service

# Check detailed first-boot log
cat /var/log/letsencrypt-firstboot.log

# Check certbot logs
cat /var/log/letsencrypt/letsencrypt.log

# Verify domain resolves correctly
dig +short proxmox.example.com

# Verify port 80 is accessible
curl -I http://proxmox.example.com
```

**Re-run certificate obtainment manually:**

```bash
# Remove marker file to allow re-run
rm -f /etc/letsencrypt/.certificate-obtained

# Run the first-boot script manually
/usr/local/bin/obtain-letsencrypt-cert.sh

# Or restart the service
systemctl restart letsencrypt-firstboot.service
```

**Renewal failed:**

```bash
# Check renewal status
certbot certificates

# Force renewal
certbot renew --force-renewal

# Check deploy hook
cat /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh
```

### Manual Certificate Installation

If you need to install a certificate manually (e.g., from a different CA):

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

**Next:** [Post-Installation](Post-Installation) | [Tailscale Setup](Tailscale-Setup)
