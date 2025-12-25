# Tailscale Setup

Secure remote access to your Proxmox server using Tailscale VPN.

## What is Tailscale?

[Tailscale](https://tailscale.com/) is a zero-config VPN that creates a secure network between your devices. With Tailscale, you can access your Proxmox server from anywhere without exposing ports to the internet.

## Installation Options

### During Installation (Recommended)

Enable Tailscale in the wizard's Services screen:

| Setting | Options | Default |
|---------|---------|---------|
| Tailscale | Enabled / Disabled | Disabled |
| Auth Key | Your Tailscale auth key | Required if enabled |
| Web UI | Enabled / Disabled | Yes |

> **Note:** When you provide a Tailscale auth key, the firewall mode automatically defaults to "Stealth" (blocks all public incoming traffic).

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

Via Tailscale hostname:
```
https://YOUR-HOSTNAME.your-tailnet.ts.net
```

Or via Tailscale IP:
```
https://100.x.x.x:8006
```

### SSH Access

```bash
ssh ADMIN_USER@YOUR-HOSTNAME
# or
ssh ADMIN_USER@100.x.x.x
```

> **Note:** Use your admin username, not root. Root SSH is disabled.

## Tailscale + Firewall Modes

When Tailscale is enabled, the firewall mode affects access:

| Firewall Mode | Public IP Access | Tailscale Access |
|---------------|------------------|------------------|
| **Stealth** | Blocked (all ports) | Full access |
| **Strict** | SSH only | Full access |
| **Standard** | SSH + Web UI | Full access |
| **Disabled** | Full access | Full access |

### Recommended: Stealth Mode

When Tailscale is enabled with an auth key, **Stealth mode is automatically suggested**. This provides maximum security:

- All incoming traffic on public IP blocked
- Access only via Tailscale VPN
- VMs still have full internet access via NAT

## Tailscale Features

### Tailscale SSH

When Tailscale is authenticated, you can use Tailscale SSH:
- No need to manage SSH keys
- Access controlled via Tailscale ACLs
- Session logging available in admin console

### Web UI Proxy (Tailscale Serve)

When "Web UI" is enabled, Proxmox is accessible via Tailscale Serve:
- Valid TLS certificate (no browser warnings)
- Accessible at `https://hostname.tailnet.ts.net`
- Only accessible from your Tailscale network

Uses:
```bash
tailscale serve --bg --https=443 https://127.0.0.1:8006
```

## Manual Setup

If you install Tailscale without an auth key, complete setup manually:

1. SSH to your server:
   ```bash
   ssh ADMIN_USER@YOUR-IP
   ```

2. Authenticate with Tailscale:
   ```bash
   sudo tailscale up --ssh
   ```

3. Follow the URL to authenticate in your browser

4. Enable Web UI proxy:
   ```bash
   sudo tailscale serve --bg --https=443 https://127.0.0.1:8006
   ```

5. **Verify Tailscale SSH works** before changing firewall:
   ```bash
   # From another device on your Tailscale network
   ssh ADMIN_USER@YOUR-HOSTNAME
   ```

## Verifying Tailscale Status

```bash
# Check status
tailscale status

# Check IP
tailscale ip

# Check serve status
tailscale serve status

# View logs
journalctl -u tailscaled -f
```

## Troubleshooting

### Cannot Connect via Tailscale

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

### Web UI Not Accessible

1. Check serve configuration:
   ```bash
   tailscale serve status
   ```

2. Re-enable serve:
   ```bash
   tailscale serve --bg --https=443 https://127.0.0.1:8006
   ```

### Tailscale Shows Offline

- Check internet connectivity
- Verify firewall isn't blocking UDP 41641
- Restart Tailscale:
  ```bash
  systemctl restart tailscaled
  ```

### Locked Out (Stealth Mode + Tailscale Issues)

If Tailscale becomes unavailable and you're in stealth mode:

1. Access via provider's KVM/IPMI console
2. Temporarily disable firewall:
   ```bash
   nft flush ruleset
   systemctl disable nftables
   ```
3. Fix Tailscale, then re-enable firewall

## Security Benefits

| Feature | Benefit |
|---------|---------|
| No public ports | Web UI and SSH not exposed |
| Zero-trust | Every connection authenticated |
| Encrypted | All traffic encrypted end-to-end |
| ACLs | Fine-grained access control |
| Audit logs | Track who accessed what |

## Removing Tailscale

```bash
# Leave the network
tailscale logout

# Remove the package
apt remove tailscale

# Remove from admin console
# Go to: https://login.tailscale.com/admin/machines
```

If using stealth firewall, update firewall mode before removing Tailscale.

---

**Back to:** [Home](Home) | [Security](Security)
