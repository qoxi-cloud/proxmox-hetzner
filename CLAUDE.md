# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language Requirements

**All content in this repository MUST be in English only.** This includes:

- Commit messages
- Pull request titles and descriptions
- Code comments
- Documentation files
- Variable and function names
- Log messages and user-facing strings
- Branch names

## Project Overview

Automated Proxmox VE installer for Hetzner dedicated servers without console access. The installer runs in Hetzner Rescue System and uses QEMU to install Proxmox on NVMe drives.

## Build System

The project uses a modular shell script architecture. Individual scripts in `scripts/` are concatenated into a single `pve-install.sh` by GitHub Actions.

**Build locally (simulates CI):**

```bash
cat scripts/*.sh > pve-install.sh
chmod +x pve-install.sh
```

**Lint scripts:**

```bash
shellcheck scripts/*.sh
# Ignored warnings: SC1091 (sourced files), SC2034 (unused vars), SC2086 (word splitting)
```

## Architecture

### Script Execution Order

Scripts are numbered and concatenated in order:

#### Initialization (00-00d)

- `00-init.sh` - Shebang, colors, version, default values
- `00a-cli.sh` - Command line argument parsing
- `00b-config.sh` - Config file load/save functions
- `00c-logging.sh` - Logging functions
- `00d-banner.sh` - ASCII banner and startup display

#### UI and Utilities (01-05)

- `01-display.sh` - Box/table display utilities using `boxes` command
- `02-utils.sh` - Download, password input, progress spinners
- `03-ssh.sh` - SSH helpers for remote execution into QEMU VM
- `04-menu.sh` - Interactive arrow-key menu system
- `05-validation.sh` - Input validators (hostname, email, subnet, etc.)

#### System Detection (06-07)

- `06-system-check.sh` - Pre-flight checks (root, RAM, KVM, NVMe detection)
- `07-network.sh` - Network interface detection

#### Input Collection (08-10)

- `08-input-non-interactive.sh` - Non-interactive input collection
- `09-input-interactive.sh` - Interactive input collection with menus
- `10-input-main.sh` - Main input orchestration function

#### Installation (11-12)

- `11-packages.sh` - Package installation, ISO download, answer.toml generation
- `12-qemu.sh` - QEMU VM management for installation and boot

#### Post-Install Configuration (13-16)

- `13-templates.sh` - Template download and preparation
- `14-configure-base.sh` - Base system configuration (ZFS, packages, shell)
- `15-configure-tailscale.sh` - Tailscale VPN configuration
- `16-configure-finalize.sh` - SSH hardening and VM finalization

#### Main Flow (99)

- `99-main.sh` - Main execution flow and installation summary

### Key Flow

```text
collect_system_info → show_system_status → get_system_inputs →
prepare_packages → download_proxmox_iso → make_answer_toml →
make_autoinstall_iso → install_proxmox → boot_proxmox_with_port_forwarding →
configure_proxmox_via_ssh → reboot_to_main_os
```

### Templates

Configuration files in `templates/` are downloaded at runtime from GitHub raw URLs and customized with `sed` placeholders:

- `{{MAIN_IPV4}}`, `{{FQDN}}`, `{{HOSTNAME}}` - Network/host values
- `{{INTERFACE_NAME}}`, `{{PRIVATE_IP_CIDR}}`, `{{PRIVATE_SUBNET}}` - Bridge config
- Three interface templates: `interfaces.internal`, `interfaces.external`, `interfaces.both`

### Remote Execution Pattern

Post-install configuration runs via SSH into QEMU VM on port 5555:

- `remote_exec "command"` - Run single command
- `run_remote "message" 'script' "done_msg"` - Run with spinner, exit on failure with log reference
- `remote_exec_with_progress "message" 'script' "done_msg"` - Run with spinner (returns exit code)
- `remote_copy "local" "remote"` - SCP file to VM

## CLI Options

| Option | Description |
|--------|-------------|
| `-c, --config FILE` | Load configuration from file |
| `-s, --save-config FILE` | Save configuration to file |
| `-n, --non-interactive` | Automated mode (requires config) |
| `-t, --test` | Test mode (TCG emulation, no KVM) |
| `--validate` | Validate config only, do not install |
| `--qemu-ram MB` | Override QEMU RAM (default: auto 4096-8192) |
| `--qemu-cores N` | Override QEMU CPU cores (default: auto, max 16) |
| `--iso-version FILE` | Use specific Proxmox ISO (e.g., proxmox-ve_8.3-1.iso) |

## Conventions

- All scripts share global variables (no `local` for exported values)
- Progress indicators use spinner chars: `SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'`
- Menu width is fixed: `MENU_BOX_WIDTH=60`
- Colors: `CLR_RED`, `CLR_GREEN`, `CLR_YELLOW`, `CLR_BLUE`, `CLR_CYAN`, `CLR_RESET`
- Status markers: `[OK]`, `[WARN]`, `[ERROR]` - colorized by `colorize_status` function
- SSH functions use `SSHPASS` env var to avoid password exposure in process list
