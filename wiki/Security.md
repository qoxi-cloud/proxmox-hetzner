# Security

This page describes security features configured by the installer.

## Security Model Overview

| Configuration | Primary Security | Additional Protection |
|---------------|------------------|----------------------|
| **With Tailscale** | VPN mesh, stealth firewall | Tailscale SSH, encrypted access |
| **Without Tailscale** | nftables firewall, Fail2Ban | SSH hardening |

## nftables Firewall

The installer uses nftables (modern replacement for iptables) with unified IPv4/IPv6 rules.

### Firewall Modes

| Mode | Allowed Incoming Traffic |
|------|-------------------------|
| **Stealth** | Tailscale and VM bridges only (public ports blocked) |
| **Strict** | SSH only (port 22) |
| **Standard** | SSH + Proxmox Web UI (ports 22, 8006) |
| **Disabled** | No firewall rules |

### What's Always Allowed

Regardless of mode, the firewall always allows:
- Loopback interface (localhost)
- Established/related connections (stateful)
- ICMP/ICMPv6 essentials (ping, neighbor discovery)
- VM bridge traffic (vmbr0, vmbr1)
- Tailscale interface (if installed)
- NAT masquerading for VM internet access

### Viewing Firewall Rules

```bash
# View current ruleset
nft list ruleset

# View specific table
nft list table inet filter
```

### Modifying Firewall

```bash
# Edit configuration
nano /etc/nftables.conf

# Apply changes
nft -f /etc/nftables.conf

# Verify syntax before applying
nft -c -f /etc/nftables.conf
```

### Temporarily Disable

```bash
# Flush all rules (until reboot)
nft flush ruleset

# Permanently disable
systemctl disable nftables
```

## SSH Hardening

Both configurations include comprehensive SSH hardening:

| Feature | Configuration |
|---------|---------------|
| Password authentication | **Disabled** |
| Key-only login | Required |
| Root login | **Disabled** (use admin user) |
| Max auth attempts | 3 |
| Login grace time | 30 seconds |

### Modern Ciphers Only

```
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
```

### Admin User Model

Root SSH is completely disabled. All SSH access uses the admin user:

```bash
# Connect via admin user
ssh ADMIN_USER@YOUR-IP

# Use sudo for root commands
sudo command

# Or switch to root
sudo -i
```

## Fail2Ban (Without Tailscale)

When Tailscale is **not** installed, Fail2Ban provides brute-force protection.

### Protected Services

| Service | Port | Max Retries | Initial Ban |
|---------|------|-------------|-------------|
| SSH | 22 | 3 | 1 hour |
| Proxmox API/Web UI | 8006 | 3 | 2 hours |

### Incremental Bans

Repeat offenders get progressively longer bans:
- 1st ban: 1 hour
- 2nd ban: 1 day
- 3rd ban: 2 days
- Maximum: 30 days

### Ignored IP Ranges

- `127.0.0.1/8` - Localhost
- `10.0.0.0/8` - Private network (Class A)
- `172.16.0.0/12` - Private network (Class B)
- `192.168.0.0/16` - Private network (Class C)

### Managing Fail2Ban

```bash
# Check status
fail2ban-client status

# Check specific jail
fail2ban-client status sshd
fail2ban-client status proxmox

# View banned IPs
fail2ban-client banned

# Unban an IP
fail2ban-client set sshd unbanip 1.2.3.4

# View logs
tail -f /var/log/fail2ban.log
```

## Optional Security Features

Enable these in the Services screen during installation.

### AppArmor

Mandatory Access Control (MAC) that confines programs to limited resources.

```bash
# Check status
aa-status

# View profiles
ls /etc/apparmor.d/
```

### auditd

Comprehensive audit logging for security compliance.

**Monitored Events:**
- User/group changes
- Privileged commands (sudo, su)
- SSH configuration changes
- Network configuration
- Proxmox CLI commands (qm, pct, pvesh)
- Proxmox config changes (/etc/pve/)
- Kernel modules
- Package management
- Firewall changes
- ZFS administration

```bash
# View recent events
ausearch -ts recent

# Search by key
ausearch -k proxmox_vm       # VM operations
ausearch -k identity          # User changes
ausearch -k privileged        # Sudo usage

# Generate reports
aureport --summary
aureport --auth
```

### AIDE

File Integrity Monitoring - detects unauthorized file changes.

```bash
# Check status
systemctl status aide-check.timer

# Run manual check
aide --check

# View reports
cat /var/log/aide/aide.log
```

### chkrootkit

Rootkit scanner running weekly.

```bash
# Check timer status
systemctl status chkrootkit-scan.timer

# Run manual scan
chkrootkit

# View logs
journalctl -u chkrootkit-scan.service
```

### lynis

Security auditing tool running weekly.

```bash
# Check timer status
systemctl status lynis-audit.timer

# Run manual audit
lynis audit system

# View reports
cat /var/log/lynis-report.dat
```

### needrestart

Automatically prompts to restart services after updates.

```bash
# Check configuration
cat /etc/needrestart/needrestart.conf

# Manual check
needrestart
```

## Tailscale Security

When Tailscale is enabled with an auth key, additional security is configured:

| Feature | Description |
|---------|-------------|
| **Stealth Firewall** | Blocks ALL incoming traffic on public IP |
| **VPN Mesh** | All traffic encrypted end-to-end |
| **Zero Trust** | Every connection authenticated |

See [Tailscale Setup](Tailscale-Setup) for full details.

## Security Comparison

| Feature | With Tailscale | Without Tailscale |
|---------|----------------|-------------------|
| Public SSH access | Blocked (stealth mode) | Protected by Fail2Ban |
| Public Web UI access | Blocked (stealth mode) | Protected by Fail2Ban |
| Attack surface | Minimal (VPN only) | SSH + Web UI exposed |
| Encryption | VPN + HTTPS | HTTPS only |

## Best Practices

### With Tailscale

1. Always provide auth key for automatic security
2. Use Tailscale SSH for best security
3. Keep stealth firewall enabled

### Without Tailscale

1. Use Ed25519 SSH keys
2. Monitor Fail2Ban logs for attack patterns
3. Keep systems updated (automatic security updates enabled)
4. Consider enabling auditd for compliance

---

**See also:** [Tailscale Setup](Tailscale-Setup) | [Post-Installation](Post-Installation)
