# Post-Installation

Details about packages, system optimizations, and configurations applied during installation.

## Installed Packages

### System Utilities (Always Installed)

| Package | Purpose |
|---------|---------|
| `btop` | Modern system monitor (CPU, RAM, disk, network) |
| `iotop` | Disk I/O monitoring |
| `ncdu` | Interactive disk usage analyzer |
| `tmux` | Terminal multiplexer (persistent sessions) |
| `pigz` | Parallel gzip (faster backup compression) |
| `smartmontools` | Disk health monitoring (SMART) |
| `jq` | JSON parser for scripts/API |
| `bat` | Modern `cat` with syntax highlighting |
| `fastfetch` | System information display |
| `sysstat` | System performance tools (sar, iostat) |
| `nethogs` | Per-process network bandwidth |
| `ethtool` | Network interface configuration |
| `curl` | HTTP client |
| `gnupg` | Encryption and signing |
| `libguestfs-tools` | VM image manipulation |
| `chrony` | NTP time synchronization |

### Optional Packages

Installed based on wizard selections:

| Package | When Installed |
|---------|---------------|
| `zsh` + Oh-My-Zsh + Powerlevel10k | Shell = ZSH |
| `nftables` | Firewall enabled |
| `fail2ban` | Tailscale disabled |
| `certbot` | SSL = Let's Encrypt |
| `tailscale` | Tailscale enabled |
| `apparmor` | Security feature selected |
| `auditd` | Security feature selected |
| `aide` | Security feature selected |
| `chkrootkit` | Security feature selected |
| `lynis` | Security feature selected |
| `needrestart` | Security feature selected |
| `vnstat` | Monitoring feature selected |
| `promtail` | Monitoring feature selected |
| `yazi` | Tool selected |
| `neovim` | Tool selected |

## Shell Configuration

### ZSH (When Selected)

| Feature | Details |
|---------|---------|
| Framework | Oh-My-Zsh |
| Theme | Powerlevel10k (pre-configured) |
| Plugins | autosuggestions, syntax-highlighting, git, sudo, history |

**Features:**
- Git status in prompt
- Command execution time
- Auto-suggestions from history (gray text)
- Syntax highlighting for commands
- Proxmox-specific aliases

### Bash (When Selected)

Minimal changes - standard Debian bash configuration.

## System Optimizations

### ZFS Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| ARC size | Based on strategy | Optimal memory usage |
| Compression | `lz4` | Fast compression |
| Scrub schedule | Weekly | Data integrity checks |

**ARC Memory Strategies:**

| Strategy | Allocation |
|----------|------------|
| VM-focused | Fixed 4GB |
| Balanced | 25-40% of RAM |
| Storage-focused | 50% of RAM |

### Network Optimizations

| Setting | Value | Purpose |
|---------|-------|---------|
| `nf_conntrack_max` | 1048576 | Support 1M+ connections |
| `nf_conntrack_tcp_timeout_established` | 28800 | 8h timeout |

### Ring Buffer Tuning (When Enabled)

Maximizes NIC ring buffers for high-throughput networks:
- Automatically detects maximum supported values
- Sets RX/TX ring buffers to maximum
- Runs on boot via systemd service

### CPU Governor

Available profiles configured during installation:

| Profile | Governor | Use Case |
|---------|----------|----------|
| Performance | performance | Maximum speed (default) |
| Balanced | ondemand/powersave | Power/performance balance |
| Adaptive | schedutil | Kernel-managed |
| Conservative | conservative | Gradual scaling |

### NTP Configuration

Chrony configured with reliable NTP servers:
- `0.pool.ntp.org`
- `1.pool.ntp.org`
- `2.pool.ntp.org`

Provider-specific NTP servers used when detected.

## Automatic Security Updates

Unattended-upgrades configured for automatic security updates:

| Feature | Configuration |
|---------|---------------|
| Security updates | Automatic daily |
| Kernel updates | Excluded (requires reboot) |
| Cleanup | Automatic removal of unused packages |

**Why kernel updates are excluded:**
Kernel updates require a reboot. Automatic reboots could disrupt running VMs. Update kernels manually during maintenance windows.

## Repository Configuration

| Repository | Subscription Nag | Updates Source |
|------------|------------------|----------------|
| No-subscription | Removed | Community repo |
| Enterprise | Kept (unless key provided) | Enterprise repo |
| Test | Removed | Test repo |

When using Enterprise with a subscription key, it's automatically registered via `pvesubscription set`.

## Admin User Configuration

| Feature | Configuration |
|---------|---------------|
| Username | Custom (set in wizard) |
| Groups | sudo, users |
| SSH key | Installed in `~/.ssh/authorized_keys` |
| Proxmox access | Full Administrator role |
| Root SSH | Disabled |

The admin user has full sudo access and can log into Proxmox Web UI.

## Verifying Configuration

```bash
# Check SSH config
grep -E "^(PasswordAuthentication|PermitRootLogin)" /etc/ssh/sshd_config

# Check ZFS ARC
cat /sys/module/zfs/parameters/zfs_arc_max

# Check CPU governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Check conntrack
sysctl net.netfilter.nf_conntrack_max

# Check NTP sync
chronyc tracking

# Check repository
cat /etc/apt/sources.list.d/proxmox.sources

# Check firewall
nft list ruleset

# Check Fail2Ban (if installed)
fail2ban-client status

# Check installed packages
dpkg -l | grep -E "(btop|tmux|zsh|fail2ban)"
```

## Monitoring Tools

### vnstat (When Enabled)

Network traffic monitoring:

```bash
# Current stats
vnstat

# Live monitoring
vnstat -l

# Daily/monthly reports
vnstat -d
vnstat -m
```

### Netdata (When Enabled)

Real-time monitoring dashboard at `http://YOUR-IP:19999`:
- CPU, RAM, disk, network metrics
- Per-process monitoring
- Alerts and notifications

```bash
# Check status
systemctl status netdata

# Restart
systemctl restart netdata
```

### Promtail (When Enabled)

Log collector for Grafana Loki:
- Collects system logs
- Ships to configured Loki endpoint

```bash
# Check status
systemctl status promtail

# View logs
journalctl -u promtail -f
```

---

**Next:** [Security](Security) | [SSL Certificates](SSL-Certificates)
