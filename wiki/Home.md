# Proxmox on Hetzner Wiki

Welcome to the **Proxmox on Hetzner** documentation!

This project provides an automated solution for installing Proxmox VE on Hetzner dedicated servers **without requiring console access**.

## Quick Navigation

| Page | Description |
|------|-------------|
| [Installation Guide](Installation-Guide) | Step-by-step installation instructions |
| [Configuration Reference](Configuration-Reference) | CLI options, environment variables, config files |
| [Network Modes](Network-Modes) | Bridge configurations explained |
| [Post-Installation](Post-Installation) | Packages, security hardening, optimizations |
| [Tailscale Setup](Tailscale-Setup) | Remote access via Tailscale VPN |

## Quick Start

```bash
bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-hetzner/pve-install.sh)
```

## Compatible Servers

- [AX Series](https://www.hetzner.com/dedicated-rootserver/matrix-ax)
- [EX Series](https://www.hetzner.com/dedicated-rootserver/matrix-ex)
- [SX Series](https://www.hetzner.com/dedicated-rootserver/matrix-sx)

> **Note:** This script has been primarily tested on AX-102 servers.

## Support

If you encounter issues, please [open an issue](https://github.com/qoxi-cloud/proxmox-hetzner/issues) on GitHub.
