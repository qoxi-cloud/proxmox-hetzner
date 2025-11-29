# Proxmox on Hetzner Without Console Access

<div align="center">
  <img src="https://github.com/qoxi-cloud/proxmox-hetzner/raw/main/icons/proxmox.png" alt="Proxmox" height="64" />
  <img src="https://github.com/qoxi-cloud/proxmox-hetzner/raw/main/icons/hetzner.png" alt="Hetzner" height="50" />
  <h3>Automated Installation for Hetzner Dedicated Servers</h3>

  ![GitHub Stars](https://img.shields.io/github/stars/qoxi-cloud/proxmox-hetzner.svg)
  ![GitHub Watchers](https://img.shields.io/github/watchers/qoxi-cloud/proxmox-hetzner.svg)
  ![GitHub Forks](https://img.shields.io/github/forks/qoxi-cloud/proxmox-hetzner.svg)
</div>

## Overview

Automated Proxmox VE installer for Hetzner dedicated servers **without console access**. Runs in Hetzner Rescue System.

### Features

- Interactive menus with arrow key navigation
- Network bridge modes: Internal NAT, External bridged, or both
- ZFS RAID selection: RAID-1, RAID-0, or single drive
- SSH hardening with key-only auth
- Automatic security updates
- Optional Tailscale VPN integration

**Compatible:** [AX](https://www.hetzner.com/dedicated-rootserver/matrix-ax), [EX](https://www.hetzner.com/dedicated-rootserver/matrix-ex), [SX](https://www.hetzner.com/dedicated-rootserver/matrix-sx) series servers

## Quick Start

1. Boot server into **Rescue Mode** (Hetzner Robot → Rescue → Linux 64-bit → Reset)
2. SSH to the rescue system
3. Run: `bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-hetzner/pve-install.sh)`
4. Access Proxmox: `https://YOUR-IP:8006`

## CLI Options

| Option | Description |
|--------|-------------|
| `-c, --config FILE` | Load configuration from file |
| `-s, --save-config FILE` | Save configuration to file |
| `-n, --non-interactive` | Automated mode (requires config/env vars) |
| `-t, --test` | Test mode (no KVM required) |

## Documentation

Full documentation available in the **[Wiki](../../wiki)**:

- [Installation Guide](../../wiki/Installation-Guide) - Step-by-step instructions
- [Configuration Reference](../../wiki/Configuration-Reference) - All options and env vars
- [Network Modes](../../wiki/Network-Modes) - Bridge configurations explained
- [Post-Installation](../../wiki/Post-Installation) - Packages and optimizations
- [Tailscale Setup](../../wiki/Tailscale-Setup) - Remote access via VPN

## Support

If this project saved you time, please consider giving it a star! [![Star on GitHub](https://img.shields.io/github/stars/qoxi-cloud/proxmox-hetzner?style=social)](https://github.com/qoxi-cloud/proxmox-hetzner)

## License

[MIT License](LICENSE)

