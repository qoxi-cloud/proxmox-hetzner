<div align="center">

# Qoxi - Proxmox Automated Installer
  <img src="https://github.com/qoxi-cloud/proxmox-installer/raw/main/icons/proxmox.png" alt="Proxmox" height="64" />
  <h3>Automated Proxmox VE Installation for Dedicated Servers</h3>

  ![Version](https://img.shields.io/endpoint?url=https://qoxi-cloud.github.io/proxmox-installer/version.json&style=for-the-badge)
  ![GitHub Stars](https://img.shields.io/github/stars/qoxi-cloud/proxmox-installer?style=for-the-badge&logo=github)
  ![GitHub License](https://img.shields.io/github/license/qoxi-cloud/proxmox-installer?style=for-the-badge)
</div>

## Overview

Automated Proxmox VE installer for dedicated servers **without console access**. Runs in any Linux rescue environment with KVM support.

### Key Features

**Installation & Configuration**
- Interactive TUI wizard with arrow key navigation
- Proxmox VE version selection (last 5 releases)
- ZFS RAID configuration (single, RAID-0, RAID-1, RAID-Z1/Z2/Z3, RAID-10)
- Repository selection (No-Subscription, Enterprise, Test)

**Networking**
- Dual-stack IPv4/IPv6 support (auto-detect, manual, or disabled)
- Network bridge modes: Internal NAT, External bridged, or both
- Jumbo frames (MTU 9000) for VM-to-VM traffic
- nftables firewall with multiple modes

**Security**
- SSH hardening with key-only authentication
- Non-root admin user (root SSH disabled)
- nftables firewall: Stealth, Strict, Standard, or Disabled
- Optional Tailscale VPN with stealth mode
- Fail2Ban brute-force protection
- Optional security tools: AppArmor, auditd, AIDE, chkrootkit, lynis

**Monitoring & Tools**
- vnstat bandwidth monitoring
- Netdata real-time dashboard
- Promtail log collector
- ZSH with Powerlevel10k or Bash
- Optional: yazi file manager, Neovim

**SSL Certificates**
- Self-signed (default)
- Let's Encrypt with auto-renewal

**Compatible:** Any dedicated server with KVM-enabled rescue system (Hetzner, OVH, Scaleway, etc.)

## Quick Start

1. Boot server into **Rescue Mode** (Linux 64-bit with KVM support)
2. SSH to the rescue system
3. Run:
   ```bash
   bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-installer/pve-install.min.sh)
   ```
4. Follow the interactive wizard
5. Access Proxmox: `https://YOUR-IP:8006`

## CLI Options

| Option | Description |
|--------|-------------|
| `--qemu-ram MB` | Set QEMU RAM in MB (default: auto) |
| `--qemu-cores N` | Set QEMU CPU cores (default: auto) |
| `--iso-version FILE` | Use specific Proxmox ISO version |
| `-h, --help` | Show help message |
| `-v, --version` | Show version |

## Time Savings

| Task | Manual | Automated |
|------|--------|-----------|
| Proxmox installation | 20-30 min | ~10 min |
| ZFS RAID configuration | 15-20 min | Included |
| Network bridge setup | 10-15 min | Included |
| SSH hardening | 10-15 min | Included |
| Firewall configuration | 15-20 min | Included |
| Security updates config | 5-10 min | Included |
| Shell + plugins setup | 10-15 min | Included |
| Let's Encrypt SSL | 10-15 min | Included |
| Tailscale + firewall | 15-20 min | Included |
| **Total** | **~2 hours** | **~10 minutes** |

## Documentation

Full documentation available in the **[Wiki](../../wiki)**:

- [Installation Guide](../../wiki/Installation-Guide) - Step-by-step instructions
- [Configuration Reference](../../wiki/Configuration-Reference) - All options explained
- [Network Modes](../../wiki/Network-Modes) - Bridge configurations
- [Security](../../wiki/Security) - Firewall, Fail2Ban, hardening
- [SSL Certificates](../../wiki/SSL-Certificates) - Let's Encrypt setup
- [Tailscale Setup](../../wiki/Tailscale-Setup) - VPN configuration
- [Post-Installation](../../wiki/Post-Installation) - Packages and optimizations
- [Development](../../wiki/Development) - Contributing guide

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and testing instructions.

## License

[MIT License](LICENSE)
