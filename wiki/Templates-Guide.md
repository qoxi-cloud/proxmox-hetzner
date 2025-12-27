# Templates Guide

Complete guide for working with configuration templates in the Proxmox Installer.

## Overview

Templates are configuration files with variable placeholders that get substituted during deployment. They live in the `templates/` directory with `.tmpl` extension.

```
templates/
├── sshd_config.tmpl        # SSH daemon config
├── nftables.conf.tmpl      # Firewall rules
├── promtail.yml.tmpl       # Log collector
├── *.service.tmpl          # Systemd services
├── *.timer.tmpl            # Systemd timers
└── ...
```

## Variable Syntax

Use double curly braces: `{{VARIABLE_NAME}}`

```bash
# Template: hosts.tmpl
{{MAIN_IPV4}}  {{HOSTNAME}}.{{DOMAIN_SUFFIX}}  {{HOSTNAME}}
127.0.0.1      localhost

# Result after substitution:
192.168.1.10  myserver.example.com  myserver
127.0.0.1     localhost
```

### Variable Naming Convention

- **UPPERCASE** with underscores: `{{MAIN_IPV4}}`, `{{SSH_PORT}}`
- Match global variable names from `003-init.sh` and `001-constants.sh`
- Use descriptive names: `{{PRIVATE_SUBNET}}` not `{{PRIV_SUB}}`

## Using Templates

### Basic Substitution

```bash
# Copy template to temp, substitute, deploy
local staged=$(mktemp)
cp "templates/config.tmpl" "$staged"
apply_template_vars "$staged" \
  "HOSTNAME=${PVE_HOSTNAME}" \
  "PORT=8080"
remote_copy "$staged" "/etc/app/config"
rm -f "$staged"
```

### Using deploy_template Helper

Combines the above pattern in one call:

```bash
deploy_template "templates/nginx.conf.tmpl" "/etc/nginx/nginx.conf" \
  "SERVER_NAME=${FQDN}" \
  "PORT=${PORT_PROXMOX_UI}"
```

### Using apply_common_template_vars

For templates using common network/system variables:

```bash
local staged=$(mktemp)
cp "templates/interfaces.tmpl" "$staged"
apply_common_template_vars "$staged"
remote_copy "$staged" "/etc/network/interfaces"
```

**Common variables applied automatically:**
- `MAIN_IPV4`, `MAIN_IPV4_GW`, `MAIN_IPV6`, `IPV6_GATEWAY`
- `FQDN`, `HOSTNAME`, `INTERFACE_NAME`
- `PRIVATE_IP_CIDR`, `PRIVATE_SUBNET`, `BRIDGE_MTU`
- `DNS_PRIMARY`, `DNS_SECONDARY`
- `LOCALE`, `KEYBOARD`, `COUNTRY`
- `PORT_SSH`, `PORT_PROXMOX_UI`

## Creating New Templates

### 1. Create Template File

```bash
# templates/myapp.conf.tmpl
[server]
hostname = {{HOSTNAME}}
bind_address = {{MAIN_IPV4}}
port = {{MYAPP_PORT}}

[security]
admin_email = {{EMAIL}}
```

### 2. Deploy in Configure Script

```bash
# scripts/3XX-configure-myapp.sh
_config_myapp() {
  deploy_template "templates/myapp.conf.tmpl" "/etc/myapp/config.conf" \
    "HOSTNAME=${PVE_HOSTNAME}" \
    "MAIN_IPV4=${MAIN_IPV4}" \
    "MYAPP_PORT=${MYAPP_PORT:-8080}" \
    "EMAIL=${EMAIL}"
}
```

### 3. Add Global Variable (if needed)

```bash
# scripts/003-init.sh (or 001-constants.sh for constants)
MYAPP_PORT="${MYAPP_PORT:-8080}"
```

## Special Characters

The template system auto-escapes:

| Character | Escaped As |
|-----------|------------|
| `\`       | `\\`       |
| `&`       | `\&`       |
| `\|`      | `\|`       |
| newline   | `\n`       |

You don't need to manually escape values.

## Systemd Templates

### Service Template

```ini
# templates/myapp.service.tmpl
[Unit]
Description=My Application
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/myapp --config /etc/myapp/config.conf
Restart=always
User={{ADMIN_USERNAME}}

[Install]
WantedBy=multi-user.target
```

### Timer Template

```ini
# templates/myapp-check.timer.tmpl
[Unit]
Description=Run myapp check daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

### Deploy Timer

```bash
deploy_systemd_timer "myapp-check"
# Deploys: myapp-check.service + myapp-check.timer
# Enables: myapp-check.timer
```

### Deploy Service Only

```bash
deploy_systemd_service "myapp" "ADMIN_USERNAME=${ADMIN_USERNAME}"
```

## Template Validation

### Unsubstituted Placeholders

`apply_template_vars` warns about remaining placeholders:

```bash
# If {{MISSING_VAR}} not substituted:
# Log: WARNING: Unsubstituted placeholders remain in /tmp/xxx: {{MISSING_VAR}}
# Returns: 1
```

### Empty Variables

Debug log for empty values:

```bash
# If HOSTNAME is empty:
# Log: DEBUG: Template variable HOSTNAME is empty, {{HOSTNAME}} will be replaced with empty string
```

### Critical Variables

`apply_common_template_vars` warns about empty critical vars:

```bash
# Log: WARNING: Critical variable MAIN_IPV4 is empty for /tmp/xxx
```

## Common Variables Reference

### Network

| Variable | Description | Example |
|----------|-------------|---------|
| `{{MAIN_IPV4}}` | Primary IPv4 | `192.168.1.10` |
| `{{MAIN_IPV4_GW}}` | IPv4 gateway | `192.168.1.1` |
| `{{MAIN_IPV6}}` | Primary IPv6 | `2001:db8::1` |
| `{{IPV6_GATEWAY}}` | IPv6 gateway | `fe80::1` |
| `{{INTERFACE_NAME}}` | Network interface | `eno1` |
| `{{BRIDGE_MTU}}` | Bridge MTU | `9000` |

### Private Network

| Variable | Description | Example |
|----------|-------------|---------|
| `{{PRIVATE_SUBNET}}` | NAT subnet | `10.0.0.0/24` |
| `{{PRIVATE_IP_CIDR}}` | Host IP in subnet | `10.0.0.1/24` |
| `{{PRIVATE_GATEWAY}}` | NAT gateway | `10.0.0.1` |

### DNS

| Variable | Description | Example |
|----------|-------------|---------|
| `{{DNS_PRIMARY}}` | Primary DNS | `1.1.1.1` |
| `{{DNS_SECONDARY}}` | Secondary DNS | `1.0.0.1` |
| `{{DNS6_PRIMARY}}` | Primary IPv6 DNS | `2606:4700:4700::1111` |
| `{{DNS6_SECONDARY}}` | Secondary IPv6 DNS | `2606:4700:4700::1001` |

### System

| Variable | Description | Example |
|----------|-------------|---------|
| `{{HOSTNAME}}` | Short hostname | `myserver` |
| `{{FQDN}}` | Full domain name | `myserver.example.com` |
| `{{TIMEZONE}}` | Timezone | `Europe/Kyiv` |
| `{{LOCALE}}` | System locale | `en_US.UTF-8` |
| `{{KEYBOARD}}` | Keyboard layout | `us` |
| `{{COUNTRY}}` | Country code | `US` |

### User

| Variable | Description | Example |
|----------|-------------|---------|
| `{{ADMIN_USERNAME}}` | Admin user | `deploy` |
| `{{EMAIL}}` | Admin email | `admin@example.com` |

### Ports

| Variable | Description | Default |
|----------|-------------|---------|
| `{{PORT_SSH}}` | SSH port | `22` |
| `{{PORT_PROXMOX_UI}}` | Web UI port | `8006` |

### Feature Flags

| Variable | Description | Values |
|----------|-------------|--------|
| `{{INSTALL_TAILSCALE}}` | Tailscale VPN | `yes`/`no` |
| `{{INSTALL_FIREWALL}}` | nftables | `yes`/`no` |
| `{{FIREWALL_MODE}}` | Firewall mode | `stealth`/`strict`/`standard` |

## Best Practices

1. **Always stage templates** - Don't modify originals in `templates/`
2. **Use deploy_template** - Handles staging, substitution, copy, cleanup
3. **Validate critical vars** - Check required vars before deployment
4. **Log substitution issues** - Watch for warnings in log file
5. **Test templates locally** - Use `sed` to verify substitution works
6. **Keep templates readable** - Add comments for complex configs

