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
| Disable OpenSSH | `yes` / `no` | `yes` when auth key provided, `no` otherwise |

> **Important:** In **interactive mode**, when you provide a Tailscale auth key, security hardening is **automatically enabled**: OpenSSH is disabled and stealth firewall is activated on first boot. In **non-interactive mode**, you must explicitly set `TAILSCALE_DISABLE_SSH=yes` and `STEALTH_MODE=yes` in your config file.

### Environment Variables

**Interactive mode (env vars skip prompts):**

```bash
export INSTALL_TAILSCALE="yes"
export TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"
# When auth key is provided in interactive mode, security hardening is auto-enabled
bash pve-install.sh
```

**Non-interactive mode with full security hardening:**

```bash
# Non-interactive requires explicit settings
cat > proxmox.conf << 'EOF'
INSTALL_TAILSCALE=yes
TAILSCALE_SSH=yes
TAILSCALE_WEBUI=yes
TAILSCALE_DISABLE_SSH=yes
STEALTH_MODE=yes
EOF

export TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"
bash pve-install.sh -c proxmox.conf -n
```

**Non-interactive without security hardening:**

```bash
cat > proxmox.conf << 'EOF'
INSTALL_TAILSCALE=yes
TAILSCALE_SSH=yes
TAILSCALE_WEBUI=yes
# TAILSCALE_DISABLE_SSH defaults to no in non-interactive mode
EOF

bash pve-install.sh -c proxmox.conf -n
# Manual `tailscale up` required after install
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

If you didn't provide an auth key during installation, Tailscale is installed but not authenticated. Complete the setup manually:

> **Warning:** Without an auth key, security hardening (stealth firewall, OpenSSH disable) is **NOT configured**. Your server remains accessible via public IP until you manually enable these features.

1. SSH to your server using the public IP:
   ```bash
   ssh root@YOUR-SERVER-IP
   ```

2. Authenticate with Tailscale:
   ```bash
   tailscale up --ssh
   ```

3. Follow the URL to authenticate in your browser

4. Enable the web UI proxy:
   ```bash
   tailscale serve --bg --https=443 https://127.0.0.1:8006
   ```

5. **Verify Tailscale SSH works** before proceeding:
   ```bash
   # From another device on your Tailscale network:
   ssh root@YOUR-HOSTNAME
   ```

6. **(Optional but recommended)** Enable security features manually - see next section

### Enabling Security Features Manually

If you want the same security level as auto-configured installations, you can enable these features manually after Tailscale is working:

#### Enable Stealth Firewall

```bash
# Download and install the stealth firewall service
curl -sSL https://github.com/qoxi-cloud/proxmox-hetzner/raw/refs/heads/main/templates/stealth-firewall.service \
  -o /etc/systemd/system/stealth-firewall.service

# Enable and start
systemctl daemon-reload
systemctl enable stealth-firewall.service
systemctl start stealth-firewall.service
```

#### Disable OpenSSH (Use with Caution!)

> **Warning:** Only disable OpenSSH after confirming Tailscale SSH is working! Test by connecting via `ssh root@YOUR-HOSTNAME` through Tailscale first.

```bash
# Stop and disable OpenSSH
systemctl stop ssh.service ssh.socket
systemctl disable ssh.service ssh.socket
systemctl mask ssh.service ssh.socket
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

## Security Hardening

### Automatic vs Manual Setup

| Feature | With Auth Key | Without Auth Key |
|---------|---------------|------------------|
| Tailscale authenticated | Automatic | Manual (`tailscale up`) |
| Stealth firewall | Enabled automatically | Must enable manually |
| OpenSSH disabled | Yes, on first boot | No, stays enabled |
| Public IP accessible | No (blocked) | Yes (open) |

When Tailscale is enabled **with an auth key**, the installer automatically configures security features:

- **OpenSSH is disabled** on first boot (after Tailscale connects)
- **Stealth firewall mode is enabled** - server is invisible from public internet

### Stealth Firewall Mode

This makes your server invisible from the public internet:

| Traffic | Allowed |
|---------|---------|
| Outgoing connections | Yes (internet access works) |
| Incoming on public IP | Blocked (all ports) |
| Incoming on Tailscale | Allowed |
| Incoming on vmbr0/vmbr1 | Allowed (VM traffic) |
| Established connections | Allowed (responses to outgoing) |

#### How It Works

- A systemd service (`stealth-firewall.service`) runs on every boot
- Sets iptables INPUT policy to DROP
- Allows loopback, established connections, Tailscale, and bridge interfaces
- VMs still have full internet access via NAT

#### Disabling Stealth Mode

If you need to disable stealth mode temporarily:

```bash
# Stop the firewall (until next reboot)
systemctl stop stealth-firewall

# Disable permanently
systemctl disable stealth-firewall
```

#### Re-enabling Stealth Mode

```bash
systemctl enable stealth-firewall
systemctl start stealth-firewall
```

### OpenSSH Disabled

OpenSSH is automatically disabled when you provide a Tailscale auth key. This prevents any SSH access via the public IP address (only Tailscale SSH will work).

How it works:

- A systemd service (`disable-openssh.service`) runs once on first boot
- It waits for Tailscale to come online and authenticate
- Once Tailscale is connected, it disables and masks `ssh.service` and `ssh.socket`
- The service then removes itself (runs only once)

#### Warning

> **Important:** Once OpenSSH is disabled, you can ONLY access the server via Tailscale SSH. If Tailscale becomes unavailable (e.g., account issues, network problems), you will need to use Hetzner Rescue Mode to regain access.

#### Re-enabling OpenSSH

If you need to re-enable OpenSSH:

```bash
# Unmask and enable SSH
systemctl unmask ssh.service ssh.socket
systemctl enable ssh.service ssh.socket
systemctl start ssh.service
```

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
