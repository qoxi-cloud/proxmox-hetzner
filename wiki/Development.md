# Development Guide

This guide covers contributing to the project, including architecture, testing, and code conventions.

## Architecture

The project is a modular bash framework. Individual scripts in `scripts/` are concatenated into a single `pve-install.sh` by GitHub Actions.

### Script Numbering

| Range | Purpose |
|-------|---------|
| **000-009** | Core: init, cli, logging, banner |
| **010-019** | Display & downloads |
| **020-029** | Templates & SSH |
| **030-039** | Helpers: password, zfs, validation, parallel, deploy, network |
| **040-049** | Validation & system checks |
| **100-109** | Wizard: core, ui, navigation, menu |
| **110-119** | Wizard: editors (basic, proxmox, network, storage, services, access, disks) |
| **200-209** | Installation: packages, QEMU, templates, ISO download, autoinstall |
| **300-309** | Configuration: base, tailscale, admin user |
| **310-319** | Security: firewall, fail2ban, apparmor |
| **320-329** | Security: auditd, aide, chkrootkit, lynis, needrestart |
| **330-339** | Network: ringbuffer tuning |
| **340-349** | Monitoring: vnstat, promtail, netdata |
| **350-359** | Tools: yazi, nvim |
| **360-369** | SSL & API token |
| **370-379** | Storage: ZFS ARC, pool creation |
| **380-389** | Finalization: validation, completion |
| **900-999** | Main orchestrator |

### Data Flow

```
User Input (Wizard) → Global Variables → Template Substitution → Remote Files
```

All configuration is stored in global variables (defined in `000-init.sh`), which are then used for template substitution and remote configuration.

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
| MAJOR | Manual in `000-init.sh` as `VERSION="X"` |
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
