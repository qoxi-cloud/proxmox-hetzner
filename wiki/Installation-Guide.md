# Installation Guide

Complete guide to installing Proxmox VE on dedicated servers using Qoxi.

## Prerequisites

- Dedicated server with KVM-enabled rescue system
- SSH access to the rescue system
- Minimum 4GB RAM (8GB+ recommended)
- At least 6GB free disk space

## Step 1: Boot into Rescue Mode

### Hetzner

1. Log in to [Hetzner Robot](https://robot.hetzner.com/)
2. Select your server → **Rescue** tab
3. Configure: Linux 64-bit, optionally add your SSH key
4. Click **Activate rescue system**
5. Go to **Reset** tab → check "Execute an automatic hardware reset" → click **Send**
6. Wait 2-3 minutes, then SSH to your server

### OVH

1. Log in to [OVH Manager](https://www.ovh.com/manager/)
2. Select your server → **Boot** tab
3. Set to **Rescue mode** and select Linux distribution
4. Reboot the server
5. Wait for rescue mode credentials via email

### Other Providers

Boot into your provider's Linux rescue mode with KVM support. The rescue system needs access to `/dev/kvm`.

## Step 2: Connect via SSH

```bash
ssh root@YOUR-SERVER-IP
```

## Step 3: Run Installation

```bash
bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-installer/pve-install.min.sh)
```

### Optional: CLI Arguments

```bash
# Use specific Proxmox version
bash <(curl -sSL ...) --iso-version proxmox-ve_8.3-1.iso

# Custom QEMU resources
bash <(curl -sSL ...) --qemu-ram 16384 --qemu-cores 8
```

## Step 4: Interactive Wizard

The wizard guides you through configuration in 6 screens:

### Basic Settings
- **Hostname** - Server hostname (e.g., `pve`, `node1`)
- **Domain** - Domain suffix (e.g., `local`, `example.com`)
- **Email** - Admin email for notifications
- **Password** - Root password (or auto-generate)
- **Timezone** - System timezone
- **Keyboard** - Keyboard layout
- **Country** - ISO country code

### Proxmox Settings
- **ISO Version** - Proxmox VE version to install
- **Repository** - No-subscription, Enterprise, or Test

### Network Settings
- **Interface** - Primary network interface
- **Bridge Mode** - Internal NAT, External, or Both
- **Private Subnet** - NAT subnet for internal VMs
- **Bridge MTU** - 9000 (jumbo) or 1500 (standard)
- **IPv6** - Auto, Manual, or Disabled
- **Firewall** - Stealth, Strict, Standard, or Disabled

### Storage Settings
- **Boot Disk** - Disk for Proxmox installation
- **Pool Disks** - Disks for ZFS data pool
- **ZFS Mode** - Single, RAID-0/1, RAID-Z1/Z2/Z3, RAID-10
- **ZFS ARC** - Memory allocation strategy

### Services
- **Tailscale** - VPN with optional stealth mode
- **SSL** - Self-signed or Let's Encrypt
- **Shell** - ZSH with Powerlevel10k or Bash
- **Power Profile** - CPU frequency governor
- **Security Features** - AppArmor, auditd, AIDE, chkrootkit, lynis, needrestart
- **Monitoring** - vnstat, Netdata, Promtail
- **Tools** - yazi, nvim, ringbuffer tuning

### Access Settings
- **Admin Username** - Non-root admin user for SSH/UI access
- **Admin Password** - Password for admin user
- **SSH Key** - Public key for admin user
- **API Token** - Optional automation token

### Navigation

| Key | Action |
|-----|--------|
| ↑/↓ | Move within screen |
| ←/→ | Switch screens |
| Enter | Edit field |
| Space | Toggle checkbox |
| S | Start installation |
| Q | Quit |

## Step 5: Installation Progress

The installer will:

1. Download Proxmox VE ISO
2. Create auto-install configuration
3. Install Proxmox in QEMU VM
4. Configure system via SSH
5. Apply security hardening
6. Validate installation
7. Show completion screen with credentials

**Save the credentials shown on the completion screen!**

## Step 6: Access Proxmox

After pressing Enter to reboot:

1. Wait 2-3 minutes for the server to boot
2. Access Web UI: `https://YOUR-IP:8006`
3. Login with admin user credentials
4. SSH: `ssh ADMIN_USER@YOUR-IP`

> **Note:** Root SSH is disabled. Use the admin user you configured.

## Troubleshooting

### Installation Hangs

Check the log file:
```bash
cat /root/pve-install-*.log
```

### Cannot Connect After Reboot

- Wait 2-3 minutes for services to start
- Try SSH before Web UI: `ssh ADMIN_USER@YOUR-IP`
- Use provider's KVM/IPMI console if available

### Web UI Not Accessible

```bash
# Check if services are running
systemctl status pveproxy pvedaemon

# Check firewall mode
nft list ruleset
```

### Wrong Firewall Mode

If you chose Stealth mode without Tailscale:
```bash
# Access via provider's KVM console
nft flush ruleset
systemctl disable nftables
```

---

**Next:** [Configuration Reference](Configuration-Reference) | [Network Modes](Network-Modes)
