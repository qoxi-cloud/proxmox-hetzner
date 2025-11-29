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

1. `00-header.sh` - Shebang, colors, CLI args, config loading
2. `01-display.sh` - Box/table display utilities using `boxes` command
3. `02-utils.sh` - Download, password input, progress spinners
4. `03-ssh.sh` - SSH helpers for remote execution into QEMU VM
5. `04-menu.sh` - Interactive arrow-key menu system
6. `05-validation.sh` - Input validators (hostname, email, subnet, etc.)
7. `06-system-check.sh` - Pre-flight checks (root, RAM, KVM, NVMe detection)
8. `07-input.sh` - User input collection (interactive and non-interactive modes)
9. `08-packages.sh` - Package installation, ISO download, answer.toml generation
10. `09-qemu.sh` - QEMU VM management for installation and boot
11. `10-configure.sh` - Post-install configuration via SSH into VM
12. `99-main.sh` - Main execution flow, calls functions in order

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
- `remote_exec_with_progress "message" 'script' "done_msg"` - Run with spinner
- `remote_copy "local" "remote"` - SCP file to VM

## Conventions

- All scripts share global variables (no `local` for exported values)
- Progress indicators use spinner chars: `SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'`
- Menu width is fixed: `MENU_BOX_WIDTH=60`
- Colors: `CLR_RED`, `CLR_GREEN`, `CLR_YELLOW`, `CLR_BLUE`, `CLR_CYAN`, `CLR_RESET`
- Status markers: `[OK]`, `[WARN]`, `[ERROR]` - colorized by `colorize_status` function
