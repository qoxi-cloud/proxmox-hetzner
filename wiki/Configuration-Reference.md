# Configuration Reference

Complete reference for all configuration options available in the installer.

## Command Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --version` | Show version |
| `--qemu-ram MB` | Set QEMU RAM in MB (default: auto, min 4096) |
| `--qemu-cores N` | Set QEMU CPU cores (default: auto, max 256) |
| `--iso-version FILE` | Use specific Proxmox ISO (e.g., `proxmox-ve_9.0-1.iso`) |

## Usage Examples

```bash
# Interactive installation (default)
bash pve-install.sh

# Use specific Proxmox version
bash pve-install.sh --iso-version proxmox-ve_9.0-1.iso

# Custom QEMU resources
bash pve-install.sh --qemu-ram 16384 --qemu-cores 8
```

## Wizard Settings Reference

All settings are configured through the interactive wizard. This reference documents each option.

### Basic Settings (Screen 1)

| Setting | Description | Default |
|---------|-------------|---------|
| Hostname | Server hostname | `pve` |
| Domain | Domain suffix for FQDN | `local` |
| Email | Admin email address | Required |
| Password | Root password | Auto-generated if skipped |
| Timezone | System timezone | `UTC` |
| Keyboard | Keyboard layout | `en-us` |
| Country | ISO country code | `us` |

### Proxmox Settings (Screen 2)

| Setting | Description | Default |
|---------|-------------|---------|
| ISO Version | Proxmox VE version (v9+) | Latest 5 available |
| Repository | Package repository type | No-subscription |
| Subscription Key | Enterprise license key | Optional (enterprise only) |

**Repository Types:**

| Type | Description |
|------|-------------|
| No-subscription | Free community repository, subscription nag removed |
| Enterprise | Stable updates, requires license key |
| Test | Latest packages, may be unstable |

### Network Settings (Screen 3)

| Setting | Description | Default |
|---------|-------------|---------|
| Interface | Primary network interface | Auto-detected |
| Bridge Mode | VM network topology | Internal NAT |
| Private Subnet | NAT subnet (CIDR) | `10.0.0.0/24` |
| Bridge MTU | Private bridge MTU | `9000` (jumbo) |
| IPv6 Mode | IPv6 configuration | Auto-detect |
| Firewall Mode | Host firewall rules | Standard |

**Bridge Modes:**

| Mode | Description |
|------|-------------|
| Internal NAT | VMs on private network with NAT |
| External | VMs get public IPs (requires additional IPs) |
| Both | Internal (vmbr0) + External (vmbr1) |

**Firewall Modes:**

| Mode | Allowed Traffic |
|------|-----------------|
| Stealth | Tailscale/bridges only (blocks all public ports) |
| Strict | SSH only (port 22) |
| Standard | SSH + Proxmox Web UI (ports 22, 8006) |
| Disabled | No firewall rules |

**IPv6 Modes:**

| Mode | Description |
|------|-------------|
| Auto | Use detected IPv6 from interface |
| Manual | Specify IPv6 address and gateway |
| Disabled | IPv4 only |

### Storage Settings (Screen 4)

| Setting | Description | Default |
|---------|-------------|---------|
| Boot Disk | Proxmox installation disk (ext4) | First detected |
| Pool Mode | Create new or use existing ZFS pool | Create new |
| Pool Disks | Disks for ZFS data pool | All remaining disks |
| ZFS Mode | ZFS RAID level | RAID-1 if 2+ disks |
| ZFS ARC | Memory allocation strategy | Balanced |

**Pool Modes:**

| Mode | Description |
|------|-------------|
| Create new | Format pool disks, create fresh ZFS pool |
| Use existing | Import existing pool, preserve all VMs and data |

> **Use existing pool:** Allows Proxmox upgrade/reinstall while preserving VMs. Requires separate boot disk. Existing pool will be imported with `zpool import -f` after installation.

**ZFS RAID Modes:**

| Mode | Minimum Disks | Description |
|------|---------------|-------------|
| Single | 1 | No redundancy |
| RAID-0 | 2 | Striped, no redundancy |
| RAID-1 | 2 | Mirror, 50% capacity |
| RAID-Z1 | 3 | Single parity |
| RAID-Z2 | 4 | Double parity |
| RAID-Z3 | 5 | Triple parity |
| RAID-10 | 4 (even) | Striped mirrors |

**ZFS ARC Memory Strategies:**

| Strategy | Allocation | Best For |
|----------|------------|----------|
| VM-focused | Fixed 4GB | Maximum RAM for VMs |
| Balanced | 25-40% of RAM | General use |
| Storage-focused | 50% of RAM | Heavy ZFS workloads |

### Services Settings (Screen 5)

#### Tailscale VPN

| Setting | Description | Default |
|---------|-------------|---------|
| Tailscale | Enable Tailscale VPN | Disabled |
| Auth Key | Pre-authentication key | Required if enabled |
| Web UI | Expose Proxmox via Tailscale Serve | Yes |

#### SSL Certificates

| Type | Description |
|------|-------------|
| Self-signed | Default Proxmox certificate (works immediately) |
| Let's Encrypt | Free trusted certificate (requires public DNS) |

> **Note:** SSL selection only shown when Tailscale is disabled. Tailscale provides its own HTTPS.

#### Shell

| Option | Description |
|--------|-------------|
| ZSH | ZSH with Oh-My-Zsh and Powerlevel10k |
| Bash | Standard bash (minimal changes) |

#### CPU Power Profile

| Profile | Governor | Description |
|---------|----------|-------------|
| Performance | performance | Maximum frequency |
| Balanced | ondemand/powersave | Dynamic scaling |
| Adaptive | schedutil | Kernel-managed |
| Conservative | conservative | Gradual scaling |

#### Security Features (Checkbox)

| Feature | Description |
|---------|-------------|
| AppArmor | Mandatory access control (MAC) |
| auditd | Security audit logging |
| AIDE | File integrity monitoring (daily) |
| chkrootkit | Rootkit scanning (weekly) |
| lynis | Security auditing (weekly) |
| needrestart | Auto-restart services after updates |

#### Monitoring Features (Checkbox)

| Feature | Description |
|---------|-------------|
| vnstat | Network bandwidth monitoring |
| Netdata | Real-time monitoring dashboard (port 19999) |
| Promtail | Log collector for Grafana Loki |

#### Tools (Checkbox)

| Feature | Description |
|---------|-------------|
| yazi | Terminal file manager (Catppuccin theme) |
| nvim | Neovim as default editor |
| ringbuffer | Network ring buffer tuning |

### Access Settings (Screen 6)

| Setting | Description | Default |
|---------|-------------|---------|
| Admin Username | Non-root admin user | Required |
| Admin Password | Admin user password | Auto-generated if skipped |
| SSH Key | Public SSH key | Auto-detected from rescue |
| API Token | Create Proxmox API token | Disabled |

> **Important:** Root SSH login is disabled. All SSH access uses the admin user.

**API Token:**
- Creates privileged token for automation (Terraform, Ansible)
- Full Administrator permissions
- No expiration
- Token ID and secret shown on completion screen

## Environment Variables

You can pre-set some values via environment variables before running the installer:

```bash
# GitHub source configuration
export GITHUB_REPO="qoxi-cloud/proxmox-installer"
export GITHUB_BRANCH="main"
```

## Timeouts and Limits

| Setting | Default | Description |
|---------|---------|-------------|
| `QEMU_BOOT_TIMEOUT` | 300s | Max wait for QEMU boot |
| `QEMU_SSH_READY_TIMEOUT` | 120s | Max wait for SSH ready |
| `SSH_CONNECT_TIMEOUT` | 10s | SSH connection timeout |
| `DNS_LOOKUP_TIMEOUT` | 5s | DNS resolution timeout |
| `DOWNLOAD_RETRY_COUNT` | 3 | Download retry attempts |

## Resource Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 4GB | 8GB+ |
| Disk Space | 6GB | 10GB+ |
| CPU Cores | 2 | 4+ |

---

**Next:** [Network Modes](Network-Modes) | [Security](Security) | [Post-Installation](Post-Installation)
