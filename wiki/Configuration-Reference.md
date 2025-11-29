# Configuration Reference

Complete reference for all configuration options available in the installer.

## Command Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --version` | Show version |
| `-c, --config FILE` | Load configuration from file |
| `-s, --save-config FILE` | Save configuration to file after input |
| `-n, --non-interactive` | Run without prompts (requires `--config` or env vars) |
| `-t, --test` | Test mode (TCG emulation, no KVM required) |
| `--validate` | Validate configuration only, do not install |
| `--qemu-ram MB` | Set QEMU RAM in MB (default: auto 4096-8192) |
| `--qemu-cores N` | Set QEMU CPU cores (default: auto, max 16) |
| `--iso-version FILE` | Use specific Proxmox ISO (e.g., `proxmox-ve_8.3-1.iso`) |

## Usage Examples

```bash
# Interactive installation (default)
bash pve-install.sh

# Save config for future use
bash pve-install.sh -s proxmox.conf

# Load config, prompt for missing values
bash pve-install.sh -c proxmox.conf

# Fully automated installation
bash pve-install.sh -c proxmox.conf -n

# Test mode (for systems without KVM support)
bash pve-install.sh -t

# Validate configuration without installing
bash pve-install.sh -c proxmox.conf --validate

# Use specific Proxmox version
bash pve-install.sh --iso-version proxmox-ve_8.2-1.iso

# Custom QEMU resources (for high-memory servers)
bash pve-install.sh --qemu-ram 16384 --qemu-cores 8
```

## Environment Variables

You can pre-configure any setting via environment variables.

- **Interactive mode:** Pre-set variables will be skipped (shown with checkmark)
- **Non-interactive mode (`-n`):** Variables provide required values

### Basic Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `PVE_HOSTNAME` | Server hostname | `pve-qoxi-cloud` |
| `DOMAIN_SUFFIX` | Domain suffix for FQDN | `local` |
| `TIMEZONE` | System timezone | `Europe/Kyiv` |
| `EMAIL` | Admin email | `admin@qoxi.cloud` |

### Password and SSH Key

| Variable | Description | Default |
|----------|-------------|---------|
| `NEW_ROOT_PASSWORD` | Root password (min 8 chars) | Auto-generated if not set |
| `SSH_PUBLIC_KEY` | SSH public key for authentication | Auto-detected from rescue system |

> **Note:** If `NEW_ROOT_PASSWORD` is not provided, a secure 16-character password will be auto-generated and displayed in the final summary table. **Make sure to save it!**

### Network Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `INTERFACE_NAME` | Network interface | Auto-detected |
| `BRIDGE_MODE` | Network mode: `internal`, `external`, `both` | `internal` |
| `PRIVATE_SUBNET` | NAT subnet (CIDR notation) | `10.0.0.0/24` |

### Storage Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `ZFS_RAID` | ZFS mode: `single`, `raid0`, `raid1` | `raid1` (if 2+ disks) |

### Shell Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `DEFAULT_SHELL` | Default shell for root: `zsh`, `bash` | `zsh` |

### Tailscale Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `INSTALL_TAILSCALE` | Install Tailscale: `yes`, `no` | `no` |
| `TAILSCALE_AUTH_KEY` | Tailscale auth key | - |
| `TAILSCALE_SSH` | Enable Tailscale SSH | `yes` |
| `TAILSCALE_WEBUI` | Enable Tailscale Web UI | `yes` |
| `TAILSCALE_DISABLE_SSH` | Disable OpenSSH on first boot: `yes`, `no` | `no` |
| `STEALTH_MODE` | Block all incoming on public IP: `yes`, `no` | `yes` when `TAILSCALE_DISABLE_SSH=yes` |

### Advanced Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `PROXMOX_ISO_VERSION` | Specific ISO filename | Latest (interactive menu) |
| `QEMU_RAM_OVERRIDE` | QEMU VM RAM in MB | Auto (4096-8192) |
| `QEMU_CORES_OVERRIDE` | QEMU VM CPU cores | Auto (half of available, max 16) |

## Examples with Environment Variables

### Semi-interactive (password from env)

```bash
export NEW_ROOT_PASSWORD="MySecurePass123"
bash pve-install.sh
```

### Multiple pre-configured values

```bash
export NEW_ROOT_PASSWORD="MySecurePass123"
export PVE_HOSTNAME="proxmox1"
export TIMEZONE="Europe/Berlin"
export INSTALL_TAILSCALE="yes"
export TAILSCALE_AUTH_KEY="tskey-auth-xxx"
bash pve-install.sh
```

### Fully automated (no config file)

```bash
export NEW_ROOT_PASSWORD="MySecurePass123"
export SSH_PUBLIC_KEY="ssh-ed25519 AAAA... user@host"
bash pve-install.sh -n
```

### Minimal automated (auto-generate password)

```bash
# Password will be auto-generated and shown in final summary
export SSH_PUBLIC_KEY="ssh-ed25519 AAAA... user@host"
bash pve-install.sh -n
```

### Single-line command

```bash
NEW_ROOT_PASSWORD="pass" SSH_PUBLIC_KEY="ssh-ed25519 ..." bash pve-install.sh -n
```

## Configuration File Format

Configuration files use simple `KEY=VALUE` format:

```bash
# proxmox.conf
PVE_HOSTNAME=proxmox1
DOMAIN_SUFFIX=example.com
TIMEZONE=Europe/Berlin
EMAIL=admin@example.com
BRIDGE_MODE=internal
PRIVATE_SUBNET=10.0.0.0/24
ZFS_RAID=raid1
DEFAULT_SHELL=zsh
INSTALL_TAILSCALE=no
```

> **Security Tip:** Use environment variables for sensitive data (passwords, auth keys) instead of storing them in config files.

---

**Next:** [Network Modes](Network-Modes) | [Post-Installation](Post-Installation)
