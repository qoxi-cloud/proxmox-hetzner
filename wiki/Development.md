# Development Guide

This guide covers contributing to the project, including build system, versioning, and code conventions.

## Build System

The project uses a modular shell script architecture. Individual scripts in `scripts/` are concatenated into a single `pve-install.sh` by GitHub Actions.

### Build Locally

```bash
cat scripts/*.sh > pve-install.sh
chmod +x pve-install.sh
```

### Lint Scripts

```bash
shellcheck scripts/*.sh
```

Ignored warnings: SC1091 (sourced files), SC2034 (unused vars), SC2086 (word splitting)

## Versioning

The project uses **Semantic Versioning** (`MAJOR.MINOR.PATCH`) with automatic version calculation:

| Component | Source | Description |
|-----------|--------|-------------|
| **MAJOR** | `scripts/00-init.sh` | Stored manually as `VERSION="1"` |
| **MINOR** | Git tags | Count of tags matching `v{MAJOR}.*` |
| **PATCH** | Git commits | Number of commits since the last tag |

### How It Works

1. Source file contains only MAJOR version: `VERSION="1"`
2. GitHub Actions calculates the full version during build
3. The final `pve-install.sh` contains the complete version (e.g., `VERSION="1.2.5"`)
4. Version changes are **NOT** pushed back to the repository

### Version Examples

| Situation | Resulting Version |
|-----------|-------------------|
| MAJOR=1, 0 tags, 50 commits | `1.0.50` |
| MAJOR=1, tag `v1.0.0`, 0 commits after | `1.1.0` |
| MAJOR=1, tag `v1.0.0`, 10 commits after | `1.1.10` |
| MAJOR=1, tags `v1.0.0` + `v1.1.0`, 5 commits after | `1.2.5` |

### Creating a Release

To create a new release and increment MINOR version:

```bash
git tag v1.0.0
git push --tags
```

After pushing the tag, the next build will have MINOR incremented and PATCH reset to 0.

### Bumping MAJOR Version

Edit `VERSION="2"` in `scripts/00-init.sh`. The MINOR and PATCH will reset based on `v2.*` tags (starting from `2.0.0`).

## Script Structure

Scripts are numbered and concatenated in order. Number ranges provide logical grouping:

| Range | Purpose | Files |
|-------|---------|-------|
| 00-09 | Initialization | init, cli, logging, banner |
| 10-19 | Utilities & Display | display, downloads, utils, templates, ssh, async-helpers, feature-installer, template-helpers, remote-helpers, password-utils, validation-helpers |
| 20-29 | Validation & System Checks | validation, system-check, live-logs |
| 30-39 | User Interaction (Wizard) | wizard-core, wizard-ui, wizard-basic, wizard-proxmox, wizard-network, wizard-storage, wizard-services, wizard-ssh |
| 40-49 | Installation | packages, qemu, templates |
| 50-59 | Post-Install Configuration | configure-base, configure-tailscale, configure-fail2ban, configure-auditd, configure-yazi, configure-nvim, configure-ssl, configure-finalize |
| 90-99 | Main Flow | main |

## Code Conventions

- All scripts share global variables
- Progress indicators: `SPINNER_CHARS=('○' '◔' '◑' '◕' '●' '◕' '◑' '◔')`
- Menu width: `MENU_BOX_WIDTH=60`
- Helper functions prefixed with `_` for internal use
- Use `printf -v` instead of `eval` for safe variable assignment

## Templates

All template files use `.tmpl` extension and are downloaded at runtime from GitHub raw URLs.

See [Configuration Reference](Configuration-Reference) for template placeholders.
