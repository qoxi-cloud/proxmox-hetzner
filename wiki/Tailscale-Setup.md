# Tailscale Setup

Secure remote access to your Proxmox server using Tailscale VPN.

## What is Tailscale?

[Tailscale](https://tailscale.com/) is a zero-config VPN that creates a secure network between your devices. With Tailscale, you can access your Proxmox server from anywhere without exposing ports to the internet.

## Installation Options

### During Proxmox Installation

The installer offers Tailscale as an optional component:

| Setting | Options | Default |
|---------|---------|---------|
| Install Tailscale | `yes` / `no` | `no` |
| Auth Key | Your Tailscale auth key | - |
| Enable SSH | `yes` / `no` | `yes` |
| Enable Web UI | `yes` / `no` | `yes` |

### Environment Variables

```bash
export INSTALL_TAILSCALE="yes"
export TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"
export TAILSCALE_SSH="yes"
export TAILSCALE_WEBUI="yes"
bash pve-install.sh
```

## Getting an Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Configure the key:
   - **Reusable**: No (single use is more secure)
   - **Ephemeral**: No (you want the node to persist)
   - **Tags**: Optional, for ACL management
4. Copy the generated key (starts with `tskey-auth-`)

> **Note:** Auth keys expire after 90 days by default. Generate a new one just before installation.

## Access Methods

After installation with Tailscale enabled:

### Web UI Access

Access Proxmox through your Tailscale network:

```
https://YOUR-HOSTNAME.your-tailnet.ts.net
```

Or using the Tailscale IP:

```
https://100.x.x.x:8006
```

### SSH Access

```bash
ssh root@YOUR-HOSTNAME
# or
ssh root@100.x.x.x
```

With Tailscale SSH enabled, you don't need SSH keys - Tailscale handles authentication.

## Manual Setup (Without Auth Key)

If you didn't provide an auth key during installation, complete the setup manually:

1. SSH to your server using the public IP
2. Authenticate with Tailscale:
   ```bash
   tailscale up --ssh
   ```
3. Follow the URL to authenticate in your browser
4. Enable the web UI proxy:
   ```bash
   tailscale serve --bg --https=443 https://127.0.0.1:8006
   ```

## Tailscale Features

### Tailscale SSH

When enabled (`TAILSCALE_SSH=yes`), Tailscale manages SSH authentication:
- No need to manage SSH keys
- Access controlled via Tailscale ACLs
- Session logging available in admin console

### Web UI Proxy

When enabled (`TAILSCALE_WEBUI=yes`), the Proxmox web interface is served over HTTPS via Tailscale:
- Valid TLS certificate (no browser warnings)
- Accessible at `https://hostname.tailnet.ts.net`
- Only accessible from your Tailscale network

## Security Benefits

| Feature | Benefit |
|---------|---------|
| No public ports | Web UI and SSH not exposed to internet |
| Zero-trust | Every connection authenticated |
| Encrypted | All traffic encrypted end-to-end |
| ACLs | Fine-grained access control |
| Audit logs | Track who accessed what |

## Verifying Tailscale Status

```bash
# Check Tailscale status
tailscale status

# Check Tailscale IP
tailscale ip

# Check serve status
tailscale serve status

# View Tailscale logs
journalctl -u tailscaled -f
```

## Troubleshooting

### Cannot connect via Tailscale

1. Verify Tailscale is running:
   ```bash
   systemctl status tailscaled
   ```

2. Check if authenticated:
   ```bash
   tailscale status
   ```

3. Re-authenticate if needed:
   ```bash
   tailscale up --ssh
   ```

### Web UI not accessible via Tailscale

1. Check serve configuration:
   ```bash
   tailscale serve status
   ```

2. Re-enable serve:
   ```bash
   tailscale serve --bg --https=443 https://127.0.0.1:8006
   ```

### Tailscale shows as offline

- Check internet connectivity
- Verify no firewall blocking UDP port 41641
- Restart Tailscale: `systemctl restart tailscaled`

## Removing Tailscale

If you need to remove Tailscale:

```bash
# Leave the Tailscale network
tailscale logout

# Remove the package
apt remove tailscale

# Remove from your Tailscale admin console
# Go to: https://login.tailscale.com/admin/machines
```

---

**Back to:** [Home](Home) | [Installation Guide](Installation-Guide)
