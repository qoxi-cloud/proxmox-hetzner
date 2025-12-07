# Security

This page describes security features automatically configured by the installer.

## Security Model

The installer uses different security strategies based on your configuration:

| Configuration | Primary Security | Additional Protection |
|--------------|------------------|----------------------|
| **With Tailscale** | VPN mesh network, stealth firewall | Tailscale SSH, encrypted access |
| **Without Tailscale** | Fail2Ban, SSH hardening | Brute-force protection |

## Fail2Ban (Without Tailscale)

When Tailscale is **not** installed, the installer automatically configures [Fail2Ban](https://www.fail2ban.org/) to protect against brute-force attacks.

### What Fail2Ban Does

Fail2Ban monitors log files for repeated failed authentication attempts and temporarily bans the offending IP addresses using iptables.

### Protected Services

| Service | Port | Max Retries | Ban Duration |
|---------|------|-------------|--------------|
| SSH | 22 | 3 | 1 hour (incremental) |
| Proxmox API/Web UI | 8006 | 3 | 2 hours (incremental) |

### Configuration Details

Based on [Proxmox Wiki Fail2ban](https://pve.proxmox.com/wiki/Fail2ban) recommendations.

**Default settings:**

| Setting | Value | Description |
|---------|-------|-------------|
| `findtime` | 1 day | Time window for counting failures |
| `bantime` | 1 hour | Initial ban duration for SSH |
| `bantime` (Proxmox) | 2 hours | Initial ban duration for Proxmox API |
| `maxretry` | 3 | Failed attempts before ban |
| `ignoreip` | localhost, private networks | Never ban these IPs |
| `backend` | systemd | Log source (Debian 12+) |

**Incremental ban times:**

Repeat offenders get progressively longer bans:

- 1st ban: 1 hour
- 2nd ban: 1 day
- 3rd ban: 2 days
- Maximum: 30 days

**Ignored IP ranges:**

- `127.0.0.1/8` - Localhost
- `10.0.0.0/8` - Private network (Class A)
- `172.16.0.0/12` - Private network (Class B)
- `192.168.0.0/16` - Private network (Class C)

### Verifying Fail2Ban Status

```bash
# Check service status
systemctl status fail2ban

# View active jails
fail2ban-client status

# Check SSH jail
fail2ban-client status sshd

# Check Proxmox jail
fail2ban-client status proxmox

# View banned IPs
fail2ban-client banned
```

### Managing Bans

```bash
# Unban an IP from SSH jail
fail2ban-client set sshd unbanip 1.2.3.4

# Unban an IP from Proxmox jail
fail2ban-client set proxmox unbanip 1.2.3.4

# Ban an IP manually
fail2ban-client set sshd banip 1.2.3.4
```

### Viewing Logs

```bash
# Fail2Ban log
tail -f /var/log/fail2ban.log

# Check for recent bans
grep "Ban" /var/log/fail2ban.log

# Check Proxmox authentication log
grep "authentication failure" /var/log/daemon.log
```

### Configuration Files

| File | Purpose |
|------|---------|
| `/etc/fail2ban/jail.local` | Main configuration |
| `/etc/fail2ban/filter.d/proxmox.conf` | Proxmox filter rules |

### Customizing Fail2Ban

**Increase ban duration:**

```bash
# Edit jail configuration
nano /etc/fail2ban/jail.local

# Change bantime (in seconds)
# bantime = 86400  # 24 hours

# Restart Fail2Ban
systemctl restart fail2ban
```

**Add email notifications:**

```bash
# Edit jail configuration
nano /etc/fail2ban/jail.local

# Uncomment and configure:
# destemail = your@email.com
# sender = fail2ban@hostname
# mta = sendmail
# action = %(action_mwl)s

# Restart Fail2Ban
systemctl restart fail2ban
```

## Audit Logging (auditd)

The installer can optionally configure [auditd](https://linux.die.net/man/8/auditd) for comprehensive administrative action tracking.

> **Note:** Audit logging is **disabled by default**. Enable it during installation if you need security compliance or forensic capabilities.

### What auditd Does

Auditd provides a detailed audit trail of system activities, essential for:

- **Security compliance** (PCI-DSS, HIPAA, SOC2)
- **Forensic analysis** after security incidents
- **Change tracking** for administrative actions
- **Anomaly detection** through log analysis

### Monitored Events

| Category | Examples |
|----------|----------|
| **User/Group changes** | `/etc/passwd`, `/etc/shadow`, user creation/deletion |
| **Privileged commands** | `sudo`, `su`, `passwd`, user management tools |
| **SSH configuration** | `sshd_config`, authorized_keys changes |
| **Network configuration** | `/etc/network/interfaces`, `/etc/hosts`, `/etc/resolv.conf` |
| **Proxmox CLI** | `qm`, `pct`, `pvesh`, `pveum`, `vzdump`, `pvesm`, etc. |
| **Proxmox config** | `/etc/pve/`, cluster config, firewall rules |
| **System services** | systemd units, cron jobs, init scripts |
| **Kernel modules** | `insmod`, `rmmod`, `modprobe` |
| **Package management** | `apt`, `apt-get`, `dpkg` |
| **Firewall changes** | `iptables`, `ip6tables`, `nft`, `pve-firewall` |
| **ZFS administration** | `zpool`, `zfs` commands |
| **Fail2Ban** | Configuration and client commands |
| **Time changes** | System clock modifications |
| **Login events** | Login/logout, failed attempts |

### Enabling auditd

**Interactive mode:**

During installation, select "Install auditd" in the Audit Logging menu.

**Environment variable:**

```bash
INSTALL_AUDITD=yes bash pve-install.sh
```

**Configuration file:**

```bash
INSTALL_AUDITD=yes
```

### Viewing Audit Logs

```bash
# View recent audit events
ausearch -ts recent

# Search by key (tag)
ausearch -k proxmox_vm          # VM operations
ausearch -k proxmox_config      # Config changes
ausearch -k identity            # User/group changes
ausearch -k privileged          # Privileged commands
ausearch -k sshd_config         # SSH config changes
ausearch -k firewall            # Firewall changes
ausearch -k zfs_admin           # ZFS operations

# Generate summary report
aureport --summary

# Generate authentication report
aureport --auth

# View events for specific user
ausearch -ua root

# View events for specific time range
ausearch -ts today -te now
```

### Audit Reports

```bash
# Summary of all events
aureport

# Failed authentication attempts
aureport --failed

# System configuration changes
aureport --config

# Executable file runs
aureport --executable

# Anomaly events
aureport --anomaly
```

### Auditd Configuration Files

| File | Purpose |
|------|---------|
| `/etc/audit/auditd.conf` | Main auditd configuration |
| `/etc/audit/rules.d/proxmox.rules` | Audit rules for Proxmox |

### Log Retention

Default settings configured by the installer:

| Setting | Value | Description |
|---------|-------|-------------|
| `max_log_file` | 50 MB | Maximum size per log file |
| `num_logs` | 10 | Number of log files to retain |
| `max_log_file_action` | ROTATE | Rotate logs when full |

Logs are stored in `/var/log/audit/`.

### Customizing Rules

To add custom audit rules:

```bash
# Edit rules file
nano /etc/audit/rules.d/custom.rules

# Example: Monitor specific file
-w /path/to/file -p wa -k custom_watch

# Reload rules
augenrules --load

# Verify rules loaded
auditctl -l
```

### Performance Considerations

Audit logging adds minimal overhead but consider:

- **High-traffic systems:** May generate large log volumes
- **Storage:** Monitor `/var/log/audit/` disk usage
- **Rules optimization:** Remove unnecessary rules if needed

To temporarily disable auditd:

```bash
systemctl stop auditd
```

## SSH Hardening

Both configurations (with or without Tailscale) include SSH hardening:

| Feature | Configuration |
|---------|---------------|
| Password authentication | Disabled |
| Key-only login | Required |
| Modern ciphers | ChaCha20, AES-GCM only |
| Max auth attempts | 3 |
| Login grace time | 30 seconds |

See [Post-Installation](Post-Installation) for details on SSH configuration.

## Tailscale Security (With Tailscale)

When Tailscale is installed with an auth key, additional security features are enabled:

| Feature | Description |
|---------|-------------|
| **Stealth Firewall** | Blocks all incoming traffic on public IP |
| **OpenSSH Disabled** | Only Tailscale SSH accessible |
| **Encrypted Mesh** | All traffic encrypted end-to-end |
| **Zero Trust** | Every connection authenticated |

See [Tailscale Setup](Tailscale-Setup) for full details.

## Why Fail2Ban Only Without Tailscale?

When Tailscale is installed with proper configuration:

1. **Public IP is blocked** - Stealth firewall drops all incoming traffic on public IP
2. **OpenSSH is disabled** - No SSH service to attack
3. **Tailscale handles auth** - Built-in authentication via Tailscale network
4. **Access is encrypted** - All traffic goes through VPN tunnel

Fail2Ban becomes redundant because there's nothing exposed to attack. The server is effectively invisible to the public internet.

When Tailscale is **not** installed:

- SSH port 22 is exposed to the internet
- Proxmox Web UI port 8006 is exposed
- Fail2Ban provides essential protection against brute-force attacks

## Security Comparison

| Feature | With Tailscale | Without Tailscale |
|---------|----------------|-------------------|
| Public SSH access | Blocked | Protected by Fail2Ban |
| Public Web UI access | Blocked | Protected by Fail2Ban |
| SSH brute-force protection | N/A (blocked) | Fail2Ban (3 attempts = 1h ban) |
| API brute-force protection | N/A (blocked) | Fail2Ban (3 attempts = 2h ban) |
| Attack surface | Minimal (VPN only) | SSH + Web UI exposed |
| Encryption | VPN + HTTPS | HTTPS only |

## Best Practices

### If Using Tailscale

1. **Always provide auth key** - Enables automatic security hardening
2. **Use Tailscale SSH** - More secure than OpenSSH
3. **Enable stealth mode** - Makes server invisible

### If Not Using Tailscale

1. **Use strong SSH keys** - Ed25519 recommended
2. **Monitor Fail2Ban logs** - Check for attack patterns
3. **Consider rate limiting** - Additional iptables rules if needed
4. **Keep systems updated** - Automatic security updates enabled by default

---

**See also:** [Tailscale Setup](Tailscale-Setup) | [Post-Installation](Post-Installation) | [Home](Home)
