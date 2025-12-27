# Development Guide

This guide covers contributing to the project, including architecture, testing, and code conventions.

## Architecture

The project is a modular bash framework. Individual scripts in `scripts/` are concatenated into a single `pve-install.sh` by GitHub Actions.

### Script Numbering

| Range | Purpose |
|-------|---------|
| **000-007** | Core: colors, constants, wizard opts, init, trap, cli, logging, banner |
| **010-012** | Display & utilities |
| **020-022** | Templates & SSH (session, remote) |
| **030-037** | Helpers: password, zfs, validation, parallel, deploy, network |
| **040-043** | Validation: basic, network, dns, security |
| **050-056** | System: packages, preflight, network, drives, wizard-data, status, live-logs |
| **100-104** | Wizard: core, ui, navigation, menu, display |
| **110-121** | Wizard: editors (locale, basic, proxmox, network, storage, ssl, tailscale, access, ssh, disks, features) |
| **200-207** | Installation: packages, QEMU config/release, templates, ISO download, autoinstall, qemu-install |
| **300-303** | Configuration: base, tailscale, admin user, services |
| **310-313** | Security: firewall-rules, firewall, fail2ban, apparmor |
| **320-324** | Security: auditd, aide, chkrootkit, lynis, needrestart |
| **330** | Network: ringbuffer tuning |
| **340-342** | Monitoring: vnstat, promtail, netdata |
| **350-351** | Tools: yazi, nvim |
| **360-361** | SSL & API token |
| **370-371** | Storage: ZFS ARC, pool creation/import |
| **380-381** | Finalization: validation, completion, phases |
| **900** | Main orchestrator |

### Data Flow

```
User Input (Wizard) → Global Variables → Template Substitution → Remote Files
```

All configuration is stored in global variables (defined in `003-init.sh`, constants in `001-constants.sh`), which are then used for template substitution and remote configuration.

### Template System

Templates use `{{VARIABLE}}` syntax:

```bash
# Apply variables to template
apply_template_vars "./templates/config.tmpl" "VAR1=${VALUE1}" "VAR2=${VALUE2}"

# Deploy template to remote
deploy_template "source.tmpl" "/target/path" "VAR1=val" "VAR2=val"
```

## Local Development

### Build Script

```bash
cat scripts/*.sh > pve-install.sh
chmod +x pve-install.sh
```

### Linting

```bash
# ShellCheck
shellcheck scripts/*.sh

# Format with shfmt
shfmt -w -i 2 -ci -bn scripts/*.sh
```

Configuration files:
- `.shellcheckrc` - ShellCheck settings
- `.editorconfig` - shfmt settings (2-space indent, case indent, binary next line)

### Testing

**Run tests in Docker** (required - macOS bash 3.2 has compatibility issues):

```bash
docker run --rm -v "$(pwd):/app" -w /app ubuntu:22.04 bash -c '
  apt-get update -qq && apt-get install -y -qq curl git >/dev/null 2>&1
  curl -fsSL https://git.io/shellspec 2>/dev/null | sh -s -- --yes >/dev/null 2>&1
  ~/.local/lib/shellspec/shellspec --format documentation
'
```

Test files are in `spec/` directory.

## Code Conventions

### Function Naming

| Prefix | Purpose |
|--------|---------|
| `_wiz_` | Wizard UI helpers |
| `_edit_` | Configuration editors |
| `_add_` | Menu builders |
| `_nav_` | Navigation helpers |
| `log` / `log_*` | Logging functions |
| `print_` | User-facing messages |
| `validate_` | Validation functions |
| `remote_` | Remote execution |
| `_ssh_` | SSH session helpers |
| `configure_` | Post-install config |
| `_config_` | Private config functions |
| `deploy_` | Deployment helpers |
| `run_` | Execution helpers |
| `add_` / `start_` / `complete_` | Live log operations |

Private/helper functions start with underscore.

### Error Handling

No `set -e` - all error handling is explicit:

```bash
# Fail fast
command || { log "ERROR: Failed"; return 1; }

# Warn and continue
command || log "WARNING: Non-critical failure"
```

### Variables

- `UPPERCASE` for global/environment variables
- `lowercase` for local variables
- Always quote: `"$VAR"` or `"${VAR}"`

## Versioning

Uses Semantic Versioning with automatic calculation:

| Component | Source |
|-----------|--------|
| MAJOR | Manual in `000-colors.sh` as `VERSION="X"` |
| MINOR | Count of git tags matching `vX.*` |
| PATCH | Commits since last tag |

The build process calculates and injects the full version.

### Creating a Release

```bash
git tag v2.1.0
git push --tags
```

## Common Patterns

### Progress Indicator

```bash
run_with_progress "Doing thing" "Done" some_function
```

### Parallel Execution

```bash
run_parallel_group "Group label" "Success message" \
  func1 \
  func2 \
  func3
```

### Feature Flag Pattern

```bash
configure_feature() {
  [[ $INSTALL_FEATURE != "yes" ]] && return 0
  _config_feature
}
```

### Remote Operations

```bash
# Execute command
remote_exec 'command'

# With progress indicator
remote_run "Description" 'command' "Success message"

# Copy file
remote_copy "/local/path" "/remote/path"
```

### Template Deployment

```bash
deploy_template "source.tmpl" "/target/path" "VAR1=val"
deploy_systemd_timer "feature"  # Deploys .service and .timer
```

## Templates

All templates use `.tmpl` extension in `templates/` directory.

Common templates:
- System config: `sshd_config.tmpl`, `hosts.tmpl`, `resolv.conf.tmpl`
- Security: `fail2ban-*.tmpl`, `auditd-rules.tmpl`
- Services: `*.service.tmpl`, `*.timer.tmpl`
- Proxmox: `proxmox.sources.tmpl`, `validation.sh.tmpl`

## Pull Requests

1. Fork the repository
2. Create feature branch
3. Make changes following code conventions
4. Run ShellCheck and tests
5. Submit PR with clear description

PRs are automatically tested via GitHub Actions.

---

**Back to:** [Home](Home)
