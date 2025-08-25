# Post-Installation

Details about packages, security hardening, and system optimizations applied automatically during installation.

## Installed Packages

The installer automatically installs these useful packages:

| Package | Purpose |
|---------|---------|
| `zsh` | Modern shell with plugins (if selected as default shell) |
| `btop` | Modern system monitor (CPU, RAM, disk, network) |
| `iotop` | Disk I/O monitoring |
| `ncdu` | Interactive disk usage analyzer |
| `tmux` | Terminal multiplexer (persistent sessions) |
| `pigz` | Parallel gzip (faster backup compression) |
| `smartmontools` | Disk health monitoring (SMART) |
| `jq` | JSON parser (useful for API/scripts) |
| `bat` | Modern `cat` with syntax highlighting |
| `libguestfs-tools` | VM image manipulation tools |
| `chrony` | NTP time synchronization |
| `unattended-upgrades` | Automatic security updates |

## Security Hardening

### SSH Configuration

| Feature | Configuration |
|---------|---------------|
| Authentication | Key-only (password disabled) |
| Ciphers | Modern only (ChaCha20, AES-GCM) |
| Max auth attempts | 3 |
| Login grace time | 30 seconds |
| Root login | Allowed with key only (`prohibit-password`) |

**Applied SSH ciphers:**
```
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
```

### Automatic Security Updates

| Feature | Configuration |
|---------|---------------|
| Security updates | Automatic via `unattended-upgrades` |
| Kernel updates | Excluded (requires manual reboot) |
| Update frequency | Daily |

**Why kernel updates are excluded:**
Kernel updates require a reboot to take effect. Automatic reboots could disrupt running VMs. You should manually update the kernel and schedule reboots during maintenance windows.

## System Optimizations

### ZFS Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| ARC size | Dynamically calculated | Optimal memory usage based on RAM |
| Compression | `lz4` | Fast compression for all data |

**ARC size calculation:**
- Systems with ≤16GB RAM: 50% for ARC
- Systems with >16GB RAM: Larger ARC allocation

### Network Optimizations

| Setting | Value | Purpose |
|---------|-------|---------|
| `nf_conntrack_max` | 1048576 | Support 1M+ connections |
| `nf_conntrack_tcp_timeout_established` | 28800 | 8h timeout for established connections |

### Performance Settings

| Setting | Configuration |
|---------|---------------|
| CPU governor | `performance` |
| NTP sync | Chrony with Hetzner NTP servers |

**Hetzner NTP servers used:**
```
ntp1.hetzner.de
ntp2.hetzner.com
ntp3.hetzner.net
```

### Locale Configuration

- UTF-8 locales properly configured
- Prevents encoding issues in applications

### Shell Environment

| Feature | Details |
|---------|---------|
| Default shell | ZSH or Bash (user selectable during installation) |
| ZSH framework | Oh-My-Zsh (if ZSH selected) |
| ZSH theme | Powerlevel10k with pre-configured prompt |
| ZSH plugins | autosuggestions, syntax-highlighting, git, sudo, history |

> **Note:** ZSH with Oh-My-Zsh and Powerlevel10k is installed only when selected as the default shell. Selecting Bash results in a lighter installation.

**ZSH features when selected:**

- Powerlevel10k theme with git status, command execution time
- Auto-suggestions from history (gray text)
- Syntax highlighting for commands
- Proxmox-specific aliases (`qml`, `pctl`, `zpl`, `zst`)

## Proxmox-Specific Changes

### Repository Configuration

The installer supports three repository types:

| Repository | Description | Subscription Notice |
|------------|-------------|---------------------|
| `no-subscription` | Free community repository (default) | Removed |
| `enterprise` | Production-ready, requires subscription key | Kept (unless key provided) |
| `test` | Latest packages, may be unstable | Removed |

**When using Enterprise repository:**
- If you provide a subscription key, it will be registered automatically via `pvesubscription set`
- The subscription notice in the web UI is **not** removed (you have a valid subscription)
- Updates come from the stable enterprise repository

**When using No-Subscription or Test:**
- Enterprise repository is disabled
- Subscription notice is removed from web UI
- Updates come from the community repository

### SSL Certificates

| Option | Description |
|--------|-------------|
| `self-signed` | Default Proxmox certificate (no external dependencies) |
| `letsencrypt` | Free auto-renewing certificate via certbot |

**Let's Encrypt requirements:**
- Domain (FQDN) must resolve to the server's public IP
- Port 80 must be accessible during certificate issuance
- Auto-renewal is configured via systemd timer

> **Note:** SSL certificate option is only shown if Tailscale is not enabled. Tailscale provides its own HTTPS via `tailscale serve`.

For more details, see [SSL Certificates](SSL-Certificates).

## Verifying Optimizations

After installation, you can verify the applied settings:

```bash
# Check SSH config
grep -E "^(PasswordAuthentication|Ciphers|MACs)" /etc/ssh/sshd_config

# Check ZFS ARC
cat /sys/module/zfs/parameters/zfs_arc_max

# Check CPU governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Check conntrack
sysctl net.netfilter.nf_conntrack_max

# Check NTP sync
chronyc tracking

# Check SSL certificate
openssl x509 -in /etc/pve/local/pveproxy-ssl.pem -noout -issuer -dates

# Check repository
cat /etc/apt/sources.list.d/proxmox.sources
```

---

**Next:** [SSL Certificates](SSL-Certificates) | [Tailscale Setup](Tailscale-Setup) | [Home](Home)
