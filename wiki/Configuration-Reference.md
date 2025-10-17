# Configuration Reference

Complete reference for all configuration options available in the installer.

## Command Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --version` | Show version |
| `-c, --config FILE` | Load configuration from file |
| `-s, --save-config FILE` | Save configuration to file after input |
| `-n, --non-interactive` | Run without prompts (requires `--config`) |
| `-t, --test` | Test mode (TCG emulation, no KVM required) |
| `-d, --dry-run` | Simulate installation without making changes |
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

# Dry-run mode (simulate without making changes)
bash pve-install.sh -d

# Dry-run with config file
bash pve-install.sh -c proxmox.conf -n -d

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
| `PVE_HOSTNAME` | Server hostname | `pve` |
| `DOMAIN_SUFFIX` | Domain suffix for FQDN | `local` |
| `TIMEZONE` | System timezone | `Europe/Kyiv` |
| `EMAIL` | Admin email | `admin@example.com` |

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
| `DEFAULT_BRIDGE_MTU` | MTU for private bridges (jumbo frames) | `9000` |

### Storage Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `ZFS_RAID` | ZFS mode: `single`, `raid0`, `raid1` | `raid1` (if 2+ disks) |

### Shell Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `DEFAULT_SHELL` | Default shell for root: `zsh`, `bash` | `zsh` |

### Repository Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `PVE_REPO_TYPE` | Repository type: `no-subscription`, `enterprise`, `test` | `no-subscription` |
| `PVE_SUBSCRIPTION_KEY` | Proxmox subscription key (only for enterprise) | - |

> **Note:** When using `enterprise` repository, you can provide your subscription key to register it automatically. Without a key, the enterprise repo will be enabled but you'll see a subscription warning in the UI.

### SSL Certificate Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `SSL_TYPE` | SSL certificate type: `self-signed`, `letsencrypt` | `self-signed` |

> **Note:** Let's Encrypt requires your domain (FQDN) to resolve to the server's IP address. The installer validates DNS using public servers (Cloudflare, Google, Quad9) before proceeding. The SSL menu is only shown if Tailscale is not enabled (Tailscale provides its own HTTPS via `tailscale serve`).

### Security Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `INSTALL_AUDITD` | Install auditd for audit logging: `yes`, `no` | `no` |

> **Note:** Auditd provides comprehensive audit logging for security compliance and forensics. It monitors administrative actions including Proxmox CLI commands, user changes, SSH config, firewall modifications, and more. See [Security](Security#audit-logging-auditd) for details.

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
| `GITHUB_REPO` | GitHub repository for templates | `qoxi-cloud/proxmox-hetzner` |
| `GITHUB_BRANCH` | GitHub branch for templates | `main` |

### Timeout and Retry Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `DNS_LOOKUP_TIMEOUT` | DNS resolution timeout in seconds | `5` |
| `DNS_RETRY_DELAY` | Delay between DNS retry attempts in seconds | `10` |
| `SSH_CONNECT_TIMEOUT` | SSH connection timeout in seconds | `10` |
| `SSH_READY_TIMEOUT` | SSH ready check timeout in seconds | `120` |
| `QEMU_BOOT_TIMEOUT` | QEMU boot timeout in seconds | `300` |
| `DOWNLOAD_RETRY_COUNT` | Number of download retry attempts | `3` |
| `DOWNLOAD_RETRY_DELAY` | Delay between download retries in seconds | `2` |

### QEMU Resource Limits

| Variable | Description | Default |
|----------|-------------|---------|
| `DEFAULT_QEMU_RAM` | Default QEMU RAM in MB | `8192` |
| `MIN_QEMU_RAM` | Minimum QEMU RAM in MB | `4096` |
| `MAX_QEMU_CORES` | Maximum QEMU CPU cores | `16` |
| `QEMU_MIN_RAM_RESERVE` | Minimum RAM to reserve for host in MB | `2048` |
| `QEMU_LOW_RAM_THRESHOLD` | Threshold for low RAM systems in MB | `16384` |

### Password Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `DEFAULT_PASSWORD_LENGTH` | Length of auto-generated passwords | `16` |

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

### Fully automated with config file

```bash
# Create minimal config
cat > proxmox.conf << 'EOF'
NEW_ROOT_PASSWORD=MySecurePass123
SSH_PUBLIC_KEY=ssh-ed25519 AAAA... user@host
EOF

bash pve-install.sh -c proxmox.conf -n
```

### Minimal automated (auto-generate password)

```bash
# SSH key will be auto-detected from rescue system
# Password will be auto-generated and shown in final summary
cat > proxmox.conf << 'EOF'
# All other settings use defaults
EOF

bash pve-install.sh -c proxmox.conf -n
```

### Single-line with env vars + config

```bash
# Env vars override config file values
NEW_ROOT_PASSWORD="pass" bash pve-install.sh -c proxmox.conf -n
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

# Repository (no-subscription, enterprise, test)
PVE_REPO_TYPE=no-subscription
# PVE_SUBSCRIPTION_KEY=pve1c-xxxxxxxxxx  # Only for enterprise

# SSL certificate (self-signed, letsencrypt)
SSL_TYPE=self-signed

# Audit logging (yes, no) - disabled by default
INSTALL_AUDITD=no

# Tailscale
INSTALL_TAILSCALE=no

# Advanced: use custom fork (optional)
# GITHUB_REPO=your-org/proxmox-hetzner
# GITHUB_BRANCH=custom-branch
```

> **Security Tip:** Use environment variables for sensitive data (passwords, auth keys) instead of storing them in config files.

## Configuration Validation

When loading a configuration file (`-c` option), the installer validates all values:

| Setting | Valid Values |
|---------|--------------|
| `BRIDGE_MODE` | `internal`, `external`, `both` |
| `ZFS_RAID` | `single`, `raid0`, `raid1` |
| `PVE_REPO_TYPE` | `no-subscription`, `enterprise`, `test` |
| `SSL_TYPE` | `self-signed`, `letsencrypt` |
| `DEFAULT_SHELL` | `bash`, `zsh` |
| `INSTALL_AUDITD` | `yes`, `no` |

Invalid values will cause the installer to exit with an error message.

Use `--validate` to check configuration without running the installation:

```bash
bash pve-install.sh -c proxmox.conf --validate
```

---

**Next:** [Network Modes](Network-Modes) | [SSL Certificates](SSL-Certificates) | [Post-Installation](Post-Installation)
