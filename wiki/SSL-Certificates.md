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

### How It Works

1. **Certificate Issuance**
   - Certbot is installed on the server
   - pveproxy is temporarily stopped
   - Certificate is obtained via HTTP-01 challenge (port 80)
   - Certificate is copied to Proxmox location
   - pveproxy is restarted with new certificate

2. **Auto-Renewal**
   - Systemd timer runs certbot renewal twice daily
   - Deploy hook automatically copies renewed certificate to Proxmox
   - pveproxy is restarted after renewal

### Certificate Locations

| File | Location |
|------|----------|
| Certificate | `/etc/pve/local/pveproxy-ssl.pem` |
| Private Key | `/etc/pve/local/pveproxy-ssl.key` |
| Let's Encrypt files | `/etc/letsencrypt/live/<domain>/` |

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

After installation, verify your certificate:

```bash
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

**Certificate issuance failed:**

```bash
# Check certbot logs
journalctl -u certbot

# Verify domain resolves correctly
dig +short proxmox.example.com

# Verify port 80 is accessible
curl -I http://proxmox.example.com
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
