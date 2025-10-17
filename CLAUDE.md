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

- `00-init.sh` - Shebang, colors, version, configuration constants (see Constants section)
- `00a-cli.sh` - Command line argument parsing
- `00b-config.sh` - Config file load/save functions
- `00c-logging.sh` - Logging functions
- `00d-banner.sh` - ASCII banner and startup display

#### UI and Utilities (01-05)

- `01-display.sh` - Box/table display utilities using `boxes` command
- `02-utils.sh` - Download, password input, progress spinners, template utilities
- `03-ssh.sh` - SSH helpers for remote execution into QEMU VM
- `04-menu.sh` - Interactive arrow-key menu system
- `05-validation.sh` - Input validators (hostname, email, subnet, password, etc.)

#### System Detection (06-07)

- `06-system-check.sh` - Pre-flight checks (root, RAM, KVM, NVMe detection), auto-installs required utilities
- `07-network.sh` - Network interface detection with fallback chain (ip -j | jq → ip | awk → ifconfig/route)

#### Input Collection (08-10)

- `08-input-non-interactive.sh` - Non-interactive input collection
- `09-input-interactive.sh` - Interactive input collection with menus
- `10-input-main.sh` - Main input orchestration function

#### Installation (11-12)

- `11-packages.sh` - Package installation, ISO download (with fallback chain), answer.toml generation
- `12-qemu.sh` - QEMU VM management for installation and boot, drive release with findmnt

#### Post-Install Configuration (13-17)

- `13-templates.sh` - Template download and preparation
- `14-configure-base.sh` - Base system configuration (ZFS, packages, shell)
- `15-configure-tailscale.sh` - Tailscale VPN configuration (uses jq for JSON parsing)
- `15a-configure-fail2ban.sh` - Fail2Ban brute-force protection (when Tailscale not used)
- `15b-configure-auditd.sh` - Auditd audit logging for administrative actions
- `16-configure-ssl.sh` - SSL certificate configuration (self-signed or Let's Encrypt)
- `17-configure-finalize.sh` - SSH hardening and VM finalization

#### Main Flow (99)

- `99-main.sh` - Main execution flow and installation summary

### Key Flow

```text
collect_system_info → show_system_status → get_system_inputs →
prepare_packages → download_proxmox_iso → make_answer_toml →
make_autoinstall_iso → install_proxmox → boot_proxmox_with_port_forwarding →
configure_proxmox_via_ssh → reboot_to_main_os
```

### Configuration Constants

Centralized constants in `00-init.sh` (can be overridden via environment variables):

| Constant Group | Examples |
|----------------|----------|
| GitHub URLs | `GITHUB_REPO`, `GITHUB_BRANCH`, `GITHUB_BASE_URL` |
| Proxmox URLs | `PROXMOX_ISO_BASE_URL`, `PROXMOX_CHECKSUM_URL` |
| DNS servers | `DNS_SERVERS[]`, `DNS_PRIMARY`, `DNS_SECONDARY`, etc. |
| Resource limits | `MIN_DISK_SPACE_MB`, `MIN_RAM_MB`, `MIN_CPU_CORES` |
| QEMU defaults | `DEFAULT_QEMU_RAM`, `MIN_QEMU_RAM`, `MAX_QEMU_CORES`, `QEMU_MIN_RAM_RESERVE` |
| Default values | `DEFAULT_HOSTNAME`, `DEFAULT_TIMEZONE`, `DEFAULT_SUBNET`, `DEFAULT_BRIDGE_MTU`, etc. |
| Packages | `SYSTEM_UTILITIES`, `OPTIONAL_PACKAGES` |
| Timeouts | `DNS_LOOKUP_TIMEOUT`, `SSH_CONNECT_TIMEOUT`, `SSH_READY_TIMEOUT`, `QEMU_BOOT_TIMEOUT` |
| Retry settings | `DNS_RETRY_DELAY`, `DOWNLOAD_RETRY_COUNT`, `DOWNLOAD_RETRY_DELAY` |
| Password | `DEFAULT_PASSWORD_LENGTH` (default: 16) |

### Auto-Installed Utilities

The installer automatically installs required utilities in `06-system-check.sh`:

| Utility | Package | Purpose |
|---------|---------|---------|
| `boxes` | boxes | Box/table display formatting |
| `column` | bsdmainutils | Column alignment in tables |
| `ip` | iproute2 | Network interface detection |
| `udevadm` | udev | Predictable interface name detection |
| `timeout` | coreutils | Command timeouts |
| `curl` | curl | HTTP requests and ISO downloads |
| `jq` | jq | JSON parsing (network info, Tailscale status) |
| `aria2c` | aria2 | Optional multi-connection downloads (fallback: curl, wget) |
| `findmnt` | util-linux | Efficient mount point detection |

### Templates

Configuration files in `templates/` are downloaded at runtime from GitHub raw URLs and customized with placeholder substitution.

**All template files use `.tmpl` extension** (e.g., `hosts.tmpl`, `zshrc.tmpl`). The `download_template()` function automatically adds `.tmpl` when fetching from GitHub, so scripts reference templates without the extension.

#### Template Categories

| Category | Files |
|----------|-------|
| Network config | `interfaces.internal`, `interfaces.external`, `interfaces.both`, `resolv.conf` |
| System config | `hosts`, `sshd_config`, `chrony`, `debian.sources`, `proxmox.sources`, `99-proxmox.conf` |
| Locale | `locale.sh`, `default-locale`, `environment` |
| Shell | `zshrc`, `p10k.zsh`, `fastfetch.sh` |
| Scripts | `configure-zfs-arc.sh`, `remove-subscription-nag.sh` |
| Services | `cpufrequtils`, `50unattended-upgrades`, `20auto-upgrades` |
| SSL | `letsencrypt-deploy-hook.sh`, `letsencrypt-firstboot.sh`, `letsencrypt-firstboot.service` |
| Tailscale | `disable-openssh.service`, `stealth-firewall.service` |
| Security | `fail2ban-jail.local`, `fail2ban-proxmox.conf`, `auditd-rules` |
| Installation | `answer.toml` |

#### Template Placeholders

- `{{MAIN_IPV4}}`, `{{FQDN}}`, `{{HOSTNAME}}` - Network/host values
- `{{INTERFACE_NAME}}`, `{{PRIVATE_IP_CIDR}}`, `{{PRIVATE_SUBNET}}`, `{{BRIDGE_MTU}}` - Bridge config
- `{{DNS_PRIMARY}}`, `{{DNS_SECONDARY}}`, etc. - DNS servers

#### Template Utility Functions

- `download_template "LOCAL_PATH" ["REMOTE_FILENAME"]` - Download template from GitHub
- `apply_template_vars "FILE" "VAR1=VALUE1" ...` - Apply variable substitutions
- `apply_common_template_vars "FILE"` - Apply standard variables (IP, hostname, etc.)

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
| `-d, --dry-run` | Simulate installation without making changes |
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

### Fallback Patterns

The installer uses fallback chains for compatibility across different environments:

#### Network Detection (07-network.sh)

```text
ip -j | jq (JSON) → ip | awk (text) → ifconfig/route (legacy)
```

#### DNS Resolution (05-validation.sh)

```text
dig → host → nslookup → getent hosts
```

All DNS commands use configurable timeout (`DNS_LOOKUP_TIMEOUT`, default: 5s).

#### Mount Detection (12-qemu.sh)

```text
findmnt (efficient) → mount | grep (fallback)
```

#### ISO Download (11-packages.sh)

```text
aria2c (2 connections) → curl (single, resume) → wget (single, resume)
```

Uses a fallback chain for reliability. aria2c is tried first with conservative settings (2 connections to avoid rate limiting), then falls back to curl or wget. All methods support resume and retry.

Helper functions:

- `_download_iso_aria2c()` - Multi-connection download with checksum verification
- `_download_iso_curl()` - Single connection with retry and resume support
- `_download_iso_wget()` - Single connection fallback

### Helper Function Patterns

Large functions are decomposed into smaller helper functions prefixed with `_` for internal use:

#### Network Detection Helpers (07-network.sh)

- `_get_ipv4_via_ip_json()` - IPv4 detection using `ip -j` + `jq`
- `_get_ipv4_via_ip_text()` - IPv4 detection using `ip` text parsing
- `_get_ipv4_via_ifconfig()` - IPv4 detection using legacy `ifconfig`
- `_get_mac_and_ipv6()` - MAC address and IPv6 detection
- `_validate_network_config()` - Network configuration validation
- `_calculate_ipv6_prefix()` - IPv6 prefix calculation for VM network

#### Drive Release Helpers (12-qemu.sh)

- `_signal_process()` - Send signal to process if running
- `_kill_processes_by_pattern()` - Kill processes with graceful→forced termination
- `_stop_mdadm_arrays()` - Stop RAID arrays
- `_deactivate_lvm()` - Deactivate LVM volume groups
- `_unmount_drive_filesystems()` - Unmount filesystems on drives
- `_kill_drive_holders()` - Kill processes holding drives open

### Error Handling Patterns

#### Download Functions (02-utils.sh)

Download functions return error codes instead of calling `exit`:

```bash
# Returns 0 on success, 1 on failure
download_file "output" "url"
download_template "local_path" ["remote_filename"]
```

Callers handle errors appropriately:

```bash
# In subshell with show_progress - exits subshell on error
(
    download_template "./templates/hosts" || exit 1
    download_template "./templates/sshd_config" || exit 1
) > /dev/null 2>&1 &
if ! show_progress $! "Downloading templates"; then
    log "ERROR: Download failed"
    exit 1
fi
```

#### SSH Hardening Pattern (17-configure-finalize.sh)

Critical operations use subshell + `show_progress` pattern with error checking:

```bash
configure_ssh_hardening() {
    local escaped_ssh_key="${SSH_PUBLIC_KEY//\'/\'\\\'\'}"
    (
        remote_exec "mkdir -p /root/.ssh" || exit 1
        remote_exec "echo '${escaped_ssh_key}' >> /root/.ssh/authorized_keys" || exit 1
        remote_copy "templates/sshd_config" "/etc/ssh/sshd_config" || exit 1
    ) > /dev/null 2>&1 &
    show_progress $! "Deploying SSH hardening"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: SSH hardening failed"
        exit 1
    fi
}
```

#### Temporary File Cleanup (15-configure-tailscale.sh)

Use `trap RETURN` for automatic cleanup:

```bash
local tmp_ip=$(mktemp)
trap "rm -f '$tmp_ip'" RETURN
```

### Configuration Validation (00b-config.sh)

The `validate_config()` function validates configuration values:

- `BRIDGE_MODE` - must be: `internal`, `external`, or `both`
- `ZFS_RAID` - must be: `single`, `raid0`, or `raid1`
- `PVE_REPO_TYPE` - must be: `no-subscription`, `enterprise`, or `test`
- `SSL_TYPE` - must be: `self-signed` or `letsencrypt`
- `DEFAULT_SHELL` - must be: `bash` or `zsh`
- `INSTALL_AUDITD` - must be: `yes` or `no`

### Password Validation (05-validation.sh)

Password validation uses `get_password_error()` for consistent error messages:

```bash
password_error=$(get_password_error "$password")
if [[ -n "$password_error" ]]; then
    print_error "$password_error"
fi
```

### Safe Variable Assignment

Use `printf -v` instead of `eval` for dynamic variable assignment:

```bash
# Safe (no command injection risk)
printf -v "$var_name" '%s' "$value"

# Unsafe (avoid)
eval "$var_name=\"\$value\""
```
