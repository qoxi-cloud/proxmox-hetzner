# Qoxi - Proxmox Automated Installer

Welcome to the **Qoxi** documentation — an automated solution for installing Proxmox VE on dedicated servers **without requiring console access**.

## Quick Navigation

| Page | Description |
|------|-------------|
| [Installation Guide](Installation-Guide) | Step-by-step installation instructions |
| [Configuration Reference](Configuration-Reference) | CLI options and wizard settings |
| [Network Modes](Network-Modes) | Bridge configurations explained |
| [Security](Security) | Firewall, SSH hardening, security tools |
| [SSL Certificates](SSL-Certificates) | Let's Encrypt and self-signed certificates |
| [Tailscale Setup](Tailscale-Setup) | Remote access via Tailscale VPN |
| [Post-Installation](Post-Installation) | Packages, optimizations, shell setup |
| [Development Guide](Development) | Contributing and script structure |

## Quick Start

```bash
bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-installer/pve-install.min.sh)
```

## How It Works

The installer runs a local QEMU VM with the Proxmox ISO inside your server's rescue environment. It automates the installation, then configures the system via SSH before rebooting into the installed Proxmox VE.

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Rescue Mode   │     │    QEMU VM      │     │  Target Server  │
│                 │     │  (Proxmox ISO)  │     │   (Proxmox)     │
│  ┌───────────┐  │     │                 │     │                 │
│  │  Wizard   │──┼────►│  Installation   │────►│  Configuration  │
│  │   (TUI)   │  │ SSH │                 │     │                 │
│  └───────────┘  │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Compatible Providers

Works on any dedicated server with a KVM-enabled rescue system:

- **Hetzner** - AX, EX, SX series
- **OVH** - Rise, Advance, Scale servers
- **Scaleway** - Dedibox
- **Any provider** with Linux rescue mode and KVM support

## Requirements

- Linux rescue mode with KVM support (`/dev/kvm`)
- Minimum 4GB RAM (8GB+ recommended)
- At least 6GB free disk space
- Root access to rescue system

## Support

If you encounter issues, please [open an issue](https://github.com/qoxi-cloud/proxmox-installer/issues) on GitHub with:
- Server provider and model
- Error messages from the log file (`/root/pve-install-*.log`)
- Configuration choices made in the wizard
