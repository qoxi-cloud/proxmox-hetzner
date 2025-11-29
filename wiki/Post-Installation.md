# Post-Installation

Details about packages, security hardening, and system optimizations applied automatically during installation.

## Installed Packages

The installer automatically installs these useful packages:

| Package | Purpose |
|---------|---------|
| `zsh` | Modern shell with plugins (autosuggestions, syntax highlighting) |
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
| `nf_conntrack_tcp_timeout_established` | 86400 | 24h timeout for established connections |

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
| Default shell | ZSH |
| Plugins | autosuggestions, syntax-highlighting |
| Dynamic MOTD | System status shown on SSH login |

## Proxmox-Specific Changes

| Change | Purpose |
|--------|---------|
| Enterprise repo | Disabled (no subscription required) |
| No-subscription repo | Enabled |
| Subscription notice | Removed from web UI |

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
```

---

**Next:** [Tailscale Setup](Tailscale-Setup) | [Home](Home)
