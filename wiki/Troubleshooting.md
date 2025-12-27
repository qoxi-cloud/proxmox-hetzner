# Troubleshooting Guide

Common issues and solutions for the Proxmox Installer.

## QEMU Issues

### QEMU Won't Start

**Symptom:** "QEMU failed to start" or process exits immediately.

**Check:**
```bash
# Verify KVM is available
ls -la /dev/kvm

# Check if KVM module loaded
lsmod | grep kvm

# Test QEMU manually
qemu-system-x86_64 --version
```

**Solutions:**

1. **No KVM access:**
   ```bash
   # Load KVM module
   modprobe kvm_intel  # or kvm_amd
   
   # Check permissions
   chmod 666 /dev/kvm
   ```

2. **Running in VM without nested virtualization:**
   - Enable nested virtualization in hypervisor
   - Or run with software emulation (very slow)

3. **Insufficient memory:**
   - Reduce QEMU RAM: `--qemu-ram 4096`
   - Minimum: 4GB

### QEMU Exits During Installation

**Symptom:** VM shuts down unexpectedly mid-install.

**Check log:**
```bash
tail -100 /root/pve-install-*.log | grep -i error
```

**Common causes:**

1. **Disk space:**
   ```bash
   df -h /root
   # Need ~10GB free
   ```

2. **ISO corruption:**
   ```bash
   rm -f /root/proxmox-ve-*.iso
   # Rerun to re-download
   ```

3. **Memory exhaustion:**
   ```bash
   free -h
   # Reduce QEMU RAM if needed
   ```

### Port 5555 Already in Use

**Symptom:** "Port 5555 is not available"

**Solution:**
```bash
# Find process using port
ss -tlnp | grep 5555
lsof -i :5555

# Kill if stale QEMU
kill <pid>
```

---

## SSH Connection Issues

### SSH Timeout

**Symptom:** "Waiting for SSH" never completes.

**Debug:**
```bash
# Test SSH manually
ssh -p 5555 -o StrictHostKeyChecking=no root@localhost

# Check if port is open
nc -zv localhost 5555
```

**Solutions:**

1. **QEMU not running:**
   ```bash
   ps aux | grep qemu
   ```

2. **VM still booting:**
   - Wait longer (boot can take 2-3 minutes)
   - Check QEMU console output

3. **Wrong password:**
   - Check log for password generation errors
   - Verify passfile exists: `ls -la /dev/shm/pve-ssh-session.*`

### SSH Authentication Failed

**Symptom:** "Permission denied" after SSH ready.

**Check:**
```bash
# Verify passfile content
cat /dev/shm/pve-ssh-session.$$

# Test with password manually
sshpass -p 'password' ssh -p 5555 root@localhost
```

**Solution:**
- Restart installation (password mismatch)
- Check `NEW_ROOT_PASSWORD` variable is set

---

## Network Detection Issues

### Interface Not Detected

**Symptom:** "Network Interface: Not configured"

**Debug:**
```bash
# List interfaces
ip link show
ip -j link 2>/dev/null | jq

# Check route
ip route show default
```

**Manual override:**
```bash
# In wizard, edit Interface field
# Or set before running:
export INTERFACE_NAME="eno1"
```

### Wrong Interface Selected

**Symptom:** Installer picks wrong NIC (e.g., veth, docker)

**Solution:**
1. Edit Interface field in wizard
2. Use filter to find correct interface

**Detection order:**
1. `ip -j link` (JSON with jq)
2. `ip route` (default route)
3. `route` command
4. `ip link show`
5. `ifconfig`
6. Default "eth0"

### IPv6 Issues

**Symptom:** IPv6 not working after installation.

**Check:**
```bash
# On installed system
ip -6 addr show
ip -6 route show

# Test connectivity
ping6 -c3 2606:4700:4700::1111
```

**Common causes:**

1. **Wrong gateway:**
   - Most providers use `fe80::1`
   - Some use routed gateway

2. **Prefix length:**
   - /64 is most common
   - /128 for single IP
   - /48 for large allocations

3. **SLAAC vs static:**
   - Check provider's network config

---

## Template Issues

### Unsubstituted Placeholders

**Symptom:** Config file contains `{{VARIABLE}}` literally.

**Check log:**
```bash
grep "Unsubstituted placeholders" /root/pve-install-*.log
```

**Causes:**

1. **Variable not passed:**
   ```bash
   # Wrong
   apply_template_vars "$file"  # No vars!
   
   # Right
   apply_template_vars "$file" "VAR=${VALUE}"
   ```

2. **Typo in template:**
   ```bash
   # Template has {{HOSTNME}} not {{HOSTNAME}}
   ```

3. **Empty variable:**
   ```bash
   # Check if variable is set
   echo "HOSTNAME=$PVE_HOSTNAME"
   ```

### Template Not Found

**Symptom:** "Template file not found"

**Check:**
```bash
ls -la templates/*.tmpl
```

**Solution:**
- Run from project root directory
- Check SCRIPT_DIR is correct

---

## Wizard Issues

### Gum Not Found

**Symptom:** "gum: command not found"

**Solution:**
```bash
# Install gum
brew install gum          # macOS
apt install gum           # Debian (if in repos)

# Or download binary
curl -sL https://github.com/charmbracelet/gum/releases/download/v0.14.1/gum_0.14.1_linux_amd64.tar.gz | tar xz
sudo mv gum /usr/local/bin/
```

### Arrow Keys Don't Work

**Symptom:** Navigation not responding to arrow keys.

**Causes:**

1. **Terminal emulator issue:**
   - Try different terminal (iTerm2, Terminal.app)
   - Check TERM variable: `echo $TERM`

2. **SSH session:**
   - Run locally, not over SSH

3. **Screen/tmux:**
   - Exit multiplexer, run directly

### Display Corruption

**Symptom:** Screen garbled, overlapping text.

**Solutions:**
```bash
# Reset terminal
reset
clear

# Check terminal size
echo "Cols: $COLUMNS, Lines: $LINES"
# Need at least 80x24
```

---

## Validation Issues

### DNS Resolution Fails

**Symptom:** "DNS lookup failed" for FQDN.

**Check:**
```bash
# Test DNS manually
dig +short A example.com @1.1.1.1
host example.com 8.8.8.8
```

**Solutions:**

1. **DNS not propagated:**
   - Wait and retry
   - Check with `dig` directly

2. **Firewall blocking:**
   - Ensure UDP 53 is allowed outbound

3. **Wrong FQDN:**
   - Verify domain is correct
   - Check A record exists

### SSH Key Validation Fails

**Symptom:** "Invalid SSH public key format"

**Check:**
```bash
# Validate key
echo "$SSH_PUBLIC_KEY" | ssh-keygen -l -f -
```

**Common issues:**

1. **Private key instead of public:**
   - Use `.pub` file content

2. **Extra whitespace:**
   - Key should be single line

3. **Truncated key:**
   - Paste complete key

4. **Weak key:**
   - RSA < 2048 bits rejected
   - DSA keys rejected

---

## Installation Failures

### Package Installation Fails

**Symptom:** "apt-get install failed"

**Check log:**
```bash
grep -A5 "apt-get install" /root/pve-install-*.log
```

**Solutions:**

1. **Network issue:**
   ```bash
   # On remote
   ping -c3 1.1.1.1
   curl -I https://deb.debian.org
   ```

2. **Repository issue:**
   ```bash
   apt-get update
   # Check for errors
   ```

3. **Disk space:**
   ```bash
   df -h
   ```

### Systemd Service Fails

**Symptom:** Service won't start after installation.

**Debug:**
```bash
# On installed system
systemctl status <service>
journalctl -u <service> -n 50
```

**Common causes:**

1. **Config syntax error:**
   ```bash
   <service> --test  # If supported
   nginx -t
   nft -c -f /etc/nftables.conf
   ```

2. **Missing dependency:**
   ```bash
   systemctl list-dependencies <service>
   ```

3. **Permission issue:**
   ```bash
   ls -la /etc/<service>/
   ```

---

## Log Analysis

### Finding the Log

```bash
ls -la /root/pve-install-*.log
```

### Key Sections

```bash
# Errors
grep -i error /root/pve-install-*.log

# Warnings
grep -i warning /root/pve-install-*.log

# SSH commands
grep "remote_exec\|remote_run" /root/pve-install-*.log

# Template issues
grep "Template\|placeholder" /root/pve-install-*.log
```

### Metrics

```bash
# Performance timing
grep "metrics_" /root/pve-install-*.log
```

---

## Getting Help

1. **Check log file** - Most errors are logged
2. **Run with debug** - Set `LOG_LEVEL=DEBUG`
3. **Test manually** - Run failed commands directly
4. **Check wiki** - Browse other wiki pages
5. **Open issue** - Include log excerpts and system info

