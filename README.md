# Qoxi - Proxmox Automated Installer

<div align="center">
  <img src="https://github.com/qoxi-cloud/proxmox-installer/raw/main/icons/proxmox.png" alt="Proxmox" height="64" />
  <h3>Automated Proxmox VE Installation for Dedicated Servers</h3>

  ![Version](https://img.shields.io/endpoint?url=https://qoxi-cloud.github.io/proxmox-installer/version.json&style=for-the-badge)
  ![Tests](https://img.shields.io/github/actions/workflow/status/qoxi-cloud/proxmox-installer/test.yml?style=for-the-badge&logo=github&label=tests)
  [![codecov](https://img.shields.io/codecov/c/github/qoxi-cloud/proxmox-installer?style=for-the-badge&logo=codecov)](https://codecov.io/gh/qoxi-cloud/proxmox-installer)
  ![GitHub Stars](https://img.shields.io/github/stars/qoxi-cloud/proxmox-installer?style=for-the-badge&logo=github)
  ![GitHub Forks](https://img.shields.io/github/forks/qoxi-cloud/proxmox-installer?style=for-the-badge&logo=github)
  ![GitHub License](https://img.shields.io/github/license/qoxi-cloud/proxmox-installer?style=for-the-badge)
</div>

## Overview

Automated Proxmox VE installer for dedicated servers **without console access**. Runs in any Linux rescue environment with KVM support.

### Features

- Interactive menus with arrow key navigation
- Full dual-stack IPv6 support (auto-detect, manual, or disabled)
- Network bridge modes: Internal NAT, External bridged, or both
- ZFS RAID selection: RAID-1, RAID-0, or single drive
- Repository selection: No-Subscription, Enterprise, or Test
- SSL certificates: Self-signed or Let's Encrypt with auto-renewal
- Default shell selection: ZSH with plugins or Bash
- SSH hardening with key-only auth
- Automatic security updates
- Fail2Ban brute-force protection (when Tailscale not used)
- Optional audit logging (auditd) for security compliance
- Optional Tailscale VPN integration
- Stealth firewall mode (blocks all incoming on public IP when Tailscale is enabled)

**Compatible:** Any dedicated server with KVM-enabled rescue system (Hetzner, OVH, Scaleway, etc.)

## Time Savings

| Task | Manual Install | This Script |
|------|----------------|-------------|
| Proxmox installation | 20-30 min | ~5 min (automated) |
| ZFS RAID configuration | 15-20 min | Included |
| Network bridge setup | 10-15 min | Included |
| SSH hardening | 10-15 min | Included |
| Security updates config | 5-10 min | Included |
| ZSH + plugins setup | 10-15 min | Included |
| NTP configuration | 5 min | Included |
| Let's Encrypt SSL | 10-15 min | Included |
| Tailscale + firewall | 15-20 min | Included |
| **Total** | **1.5-2.5 hours** | **~5 minutes** |

One command replaces hours of manual configuration with battle-tested defaults.

## Quick Start

1. Boot server into **Rescue Mode** (Linux 64-bit with KVM support)
2. SSH to the rescue system
3. Run: `bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-installer/pve-install.min.sh)`
4. Access Proxmox: `https://YOUR-IP:8006`

## CLI Options

| Option | Description |
|--------|-------------|
| `--qemu-ram MB` | Set QEMU RAM in MB (default: auto 4096-8192) |
| `--qemu-cores N` | Set QEMU CPU cores (default: auto, max 16) |
| `--iso-version FILE` | Use specific Proxmox ISO version |

## Documentation

Full documentation available in the **[Wiki](../../wiki)**:

- [Installation Guide](../../wiki/Installation-Guide) - Step-by-step instructions
- [Configuration Reference](../../wiki/Configuration-Reference) - All options and env vars
- [Network Modes](../../wiki/Network-Modes) - Bridge configurations explained
- [SSL Certificates](../../wiki/SSL-Certificates) - Let's Encrypt setup
- [Security](../../wiki/Security) - Fail2Ban and security hardening
- [Post-Installation](../../wiki/Post-Installation) - Packages and optimizations
- [Tailscale Setup](../../wiki/Tailscale-Setup) - Remote access via VPN

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for:

- Development setup
- Code style guidelines
- Pull request process
- Testing instructions

PRs are automatically tested and deployed for easy verification.

## Support

<div align="center">

**If this project saved you time, please consider giving it a star!**

[![Star on GitHub](https://img.shields.io/github/stars/qoxi-cloud/proxmox-installer?style=for-the-badge&logo=github)](https://github.com/qoxi-cloud/proxmox-installer)

</div>

## License

[MIT License](LICENSE)

