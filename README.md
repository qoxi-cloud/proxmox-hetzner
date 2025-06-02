# Proxmox on Hetzner Without Console Access

<div align="center">
  <img src="https://github.com/qoxi-cloud/proxmox-hetzner/raw/main/icons/proxmox.png" alt="Proxmox" height="64" />
  <img src="https://github.com/qoxi-cloud/proxmox-hetzner/raw/main/icons/hetzner.png" alt="Hetzner" height="50" />
  <h3>Automated Installation for Hetzner Dedicated Servers</h3>

  ![GitHub Stars](https://img.shields.io/github/stars/qoxi-cloud/proxmox-hetzner.svg)
  ![GitHub Watchers](https://img.shields.io/github/watchers/qoxi-cloud/proxmox-hetzner.svg)
  ![GitHub Forks](https://img.shields.io/github/forks/qoxi-cloud/proxmox-hetzner.svg)
</div>

## 📑 Overview

This project provides an automated solution for installing Proxmox VE on Hetzner dedicated servers **without requiring console access**. It streamlines the installation process using a custom script that handles all the complex configuration steps automatically.

### Features

- **Interactive menus** for easy configuration (arrow keys navigation)
- **Network bridge modes**: Internal NAT, External bridged, or both
- **ZFS RAID selection**: RAID-1 (mirror), RAID-0 (stripe), or single drive
- **SSH hardening**: Key-only auth, modern ciphers, secure defaults
- **Automatic security updates**: Unattended upgrades (kernel excluded)
- **NTP time sync**: Chrony with Hetzner NTP servers
- **ZSH shell**: Pre-configured with autosuggestions and syntax highlighting
- **Dynamic MOTD**: System status on every login
- Clean progress indicators with spinners for all operations
- Full logging to file for troubleshooting
- Pre-flight hardware and connectivity checks
- Configuration file support for repeatable installations
- Non-interactive mode for fully automated deployments
- Total installation time tracking

**Compatible Hetzner Server Series:**
- [AX Series](https://www.hetzner.com/dedicated-rootserver/matrix-ax)
- [EX Series](https://www.hetzner.com/dedicated-rootserver/matrix-ex)
- [SX Series](https://www.hetzner.com/dedicated-rootserver/matrix-sx)

> ⚠️ **Note:** This script has been primarily tested on AX-102 servers and configures disks in RAID-1 (ZFS) format.

<div align="center">
  <br>
  <h3>❤️ Love This Tool? ❤️</h3>
  <p>If this project has saved you time and effort, please consider starring it!</p>
  <p>
    <a href="https://github.com/qoxi-cloud/proxmox-hetzner" target="_blank">
      <img src="https://img.shields.io/github/stars/qoxi-cloud/proxmox-hetzner?style=social" alt="Star on GitHub">
    </a>
  </p>
  <p><b>Every star motivates me to create more awesome tools for the community!</b></p>
  <br>
</div>

## 🚀 Installation Process

### 1. Prepare Rescue Mode

1. Access the Hetzner Robot Manager for your server
2. Navigate to the **Rescue** tab and configure:
   - Operating system: **Linux**
   - Architecture: **64 bit**
   - Public key: *optional*
3. Click **Activate rescue system**
4. Go to the **Reset** tab
5. Check: **Execute an automatic hardware reset**
6. Click **Send**
7. Wait a few minutes for the server to boot into rescue mode
8. Connect via SSH to the rescue system

### 2. Run Installation Script

Execute this single command in the rescue system terminal:

```bash
bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-hetzner/pve-install.sh)
```

#### Command Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --version` | Show version |
| `-c, --config FILE` | Load configuration from file |
| `-s, --save-config FILE` | Save configuration to file after input |
| `-n, --non-interactive` | Run without prompts (requires `--config`) |

#### Usage Examples

```bash
# Interactive installation (default)
bash pve-install.sh

# Save config for future use
bash pve-install.sh -s proxmox.conf

# Load config, prompt for missing values
bash pve-install.sh -c proxmox.conf

# Fully automated installation
bash pve-install.sh -c proxmox.conf -n
```

### Environment Variables

You can pre-configure any setting via environment variables. In **interactive mode**, pre-set variables will be skipped (shown with checkmark). In **non-interactive mode** (`-n`), they provide required values.

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PVE_HOSTNAME` | Server hostname | `pve` | No |
| `DOMAIN_SUFFIX` | Domain suffix for FQDN | `local` | No |
| `TIMEZONE` | System timezone | `Europe/Kyiv` | No |
| `EMAIL` | Admin email | `admin@example.com` | No |
| `NEW_ROOT_PASSWORD` | Root password | - | **Yes** (non-interactive) |
| `SSH_PUBLIC_KEY` | SSH public key | From rescue system | **Yes** (non-interactive) |
| `INTERFACE_NAME` | Network interface | Auto-detected | No |
| `BRIDGE_MODE` | Network mode: `internal`, `external`, `both` | `internal` | No |
| `PRIVATE_SUBNET` | NAT subnet (CIDR) | `10.0.0.0/24` | No |
| `ZFS_RAID` | ZFS mode: `single`, `raid0`, `raid1` | `raid1` (2+ disks) | No |
| `INSTALL_TAILSCALE` | Install Tailscale: `yes`, `no` | `no` | No |
| `TAILSCALE_AUTH_KEY` | Tailscale auth key | - | No |
| `TAILSCALE_SSH` | Enable Tailscale SSH | `yes` | No |
| `TAILSCALE_WEBUI` | Enable Tailscale Web UI | `yes` | No |

#### Examples with Environment Variables

```bash
# Semi-interactive: only password from env, rest interactive
export NEW_ROOT_PASSWORD="MySecurePass123"
bash pve-install.sh

# Multiple pre-configured values
export NEW_ROOT_PASSWORD="MySecurePass123"
export PVE_HOSTNAME="proxmox1"
export TIMEZONE="Europe/Berlin"
export INSTALL_TAILSCALE="yes"
export TAILSCALE_AUTH_KEY="tskey-auth-xxx"
bash pve-install.sh

# Fully automated with env vars (no config file needed)
export NEW_ROOT_PASSWORD="MySecurePass123"
export SSH_PUBLIC_KEY="ssh-ed25519 AAAA... user@host"
bash pve-install.sh -n

# Inline (single command)
NEW_ROOT_PASSWORD="pass" SSH_PUBLIC_KEY="ssh-ed25519 ..." bash pve-install.sh -n
```

> **Security Tip:** Use environment variables for sensitive data (passwords, auth keys) instead of storing them in config files.

The script will:
- Download the latest Proxmox VE ISO
- Create an auto-installation configuration
- Install Proxmox VE with your chosen ZFS configuration
- Configure networking based on your bridge mode selection
- Set up proper hostname and FQDN
- Apply recommended system settings
- **Optional:** Install Tailscale VPN with SSH and Web UI access

### Network Bridge Modes

| Mode | Description | Configuration |
|------|-------------|---------------|
| **Internal only** | NAT network - VMs get private IPs | `vmbr0` = NAT bridge (10.0.0.0/24 default) |
| **External only** | Bridged to physical NIC - VMs get IPs from router/DHCP | `vmbr0` = bridged to NIC |
| **Both** | Both internal and external networks | `vmbr0` = external, `vmbr1` = NAT |

> **Tip:** Use "Internal only" for isolated VMs with NAT, "External only" if you have additional IPs from Hetzner, or "Both" for maximum flexibility.

### 3. Automatic Post-Installation Optimizations

The installation script automatically applies the following optimizations:

**Installed Packages:**
| Package | Purpose |
|---------|---------|
| `zsh` | Modern shell with plugins (autosuggestions, syntax highlighting) |
| `btop` | Modern system monitor (CPU, RAM, disk, network) |
| `iotop` | Disk I/O monitoring |
| `ncdu` | Interactive disk usage analyzer |
| `tmux` | Terminal multiplexer (persistent sessions) |
| `pigz` | Parallel gzip (faster backup compression) |
| `smartmontools` | Disk health monitoring (SMART) |
| `jq` | JSON parser (useful for API/scripts) |
| `bat` | Modern `cat` with syntax highlighting |
| `libguestfs-tools` | VM image manipulation tools |
| `chrony` | NTP time synchronization |
| `unattended-upgrades` | Automatic security updates |

**Security Hardening:**
| Feature | Configuration |
|---------|---------------|
| SSH authentication | Key-only (password disabled) |
| SSH ciphers | Modern only (ChaCha20, AES-GCM) |
| SSH limits | Max 3 auth attempts, 30s grace time |
| Root login | Allowed with key only (`prohibit-password`) |
| Security updates | Automatic via unattended-upgrades |
| Kernel updates | Excluded from auto-updates (manual reboot) |

**System Optimizations:**
| Optimization | Details |
|--------------|---------|
| Package updates | All packages updated (`apt dist-upgrade`) |
| ZFS ARC limits | Dynamically calculated based on system RAM |
| nf_conntrack | Optimized for 1M+ connections |
| CPU governor | Set to `performance` mode |
| NTP sync | Chrony with Hetzner NTP servers |
| UTF-8 locales | Properly configured for all apps |
| Dynamic MOTD | System status shown on SSH login |
| Subscription notice | Removed from web UI |
| Enterprise repos | Disabled (no subscription required) |

## ✅ Accessing Your Proxmox Server

After installation completes:

1. Access the Proxmox Web GUI: `https://YOUR-SERVER-IP:8006`
2. Login with:
   - Username: `root`
   - Password: *the password you set during installation*

### Tailscale Remote Access (Optional)

If you enabled Tailscale during installation, you can access your server securely from anywhere:

| Access Method | URL/Command |
|--------------|-------------|
| **Web UI** | `https://YOUR-HOSTNAME.your-tailnet.ts.net` |
| **SSH** | `ssh root@YOUR-TAILSCALE-IP` |

**With Auth Key:** Both SSH and Web UI are configured automatically during installation.

**Without Auth Key:** Run these commands after reboot to complete setup:
```bash
tailscale up --ssh
tailscale serve --bg --https=443 https://127.0.0.1:8006
```

> Get your Tailscale auth key from: https://login.tailscale.com/admin/settings/keys

## License

This project is licensed under the [MIT License](LICENSE).