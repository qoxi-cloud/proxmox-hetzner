# Contributing to Proxmox Installer

Thank you for your interest in contributing! This guide will help you get started.

## Documentation

Before contributing, familiarize yourself with the project:

- [Architecture](wiki/Architecture.md) - Project structure and execution flow
- [Function Reference](wiki/Function-Reference.md) - All public functions
- [Templates Guide](wiki/Templates-Guide.md) - Template syntax and variables
- [Wizard Development](wiki/Wizard-Development.md) - Extending the wizard
- [Security Model](wiki/Security-Model.md) - Credential handling

## Development Setup

### Prerequisites

- Bash 4.0+
- [ShellCheck](https://www.shellcheck.net/) for linting
- [shfmt](https://github.com/mvdan/sh) for formatting
- [gum](https://github.com/charmbracelet/gum) for wizard testing
- Git

### Clone and Setup

```bash
git clone https://github.com/qoxi-cloud/proxmox-installer.git
cd proxmox-installer

# Enable commit message validation (recommended)
git config core.hooksPath .githooks
```

### Project Structure

```
proxmox-installer/
├── scripts/           # Source scripts (numbered for execution order)
│   ├── 000-colors.sh  # Terminal colors, version
│   ├── 001-constants.sh # DNS, timeouts, ports, resource limits
│   ├── 002-wizard-options.sh # WIZ_* menu option lists
│   ├── 003-init.sh    # Globals, cleanup trap, runtime variables
│   ├── 004-cli.sh     # CLI argument parsing
│   ├── 005-logging.sh # Logging and metrics
│   ├── ...
│   └── 900-main.sh    # Main orchestrator
├── templates/         # Configuration templates (.tmpl extension)
├── docs/              # Developer documentation
├── wiki/              # User documentation (GitHub Wiki)
├── spec/              # ShellSpec unit tests
└── .cursor/rules/     # AI assistant context
```

### Script Number Ranges

| Range   | Purpose                                           |
|---------|---------------------------------------------------|
| 000-006 | Core init (colors, constants, wizard opts, init, cli, logging, banner) |
| 010-012 | Display & utilities                               |
| 020-021 | Templates & SSH                                   |
| 030-035 | Helpers (password, zfs, validation, parallel, deploy, network) |
| 040-043 | Validation (basic, network, dns, security)        |
| 050-056 | System detection (packages, preflight, network, drives, status, live-logs) |
| 100-103 | Wizard core (main loop, UI, navigation, menu)     |
| 110-116 | Wizard editors (screens)                          |
| 200-204 | Installation (packages, QEMU, templates, ISO, autoinstall) |
| 300-380 | Configuration (base, security, monitoring, etc.)  |
| 900     | Main orchestrator                                 |

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/my-feature
# or
git checkout -b fix/bug-description
```

### 2. Edit Scripts

Follow existing patterns in the codebase. Key references:

- **Remote execution:** Use `remote_run` for config steps, `remote_exec` for status checks
- **Templates:** Use `deploy_template` helper, see [Templates Guide](docs/templates-guide.md)
- **Validation:** Add to `040-043-validation-*.sh`, follow existing function patterns
- **Wizard fields:** See [Wizard Development](docs/wizard-development.md)

### 3. Lint and Format

```bash
# Lint all scripts
shellcheck scripts/*.sh

# Format all scripts
shfmt -w scripts/*.sh
```

Configuration files: `.shellcheckrc`, `.editorconfig`

### 4. Run Tests

Tests must run in Docker (macOS bash 3.2 has compatibility issues):

```bash
docker run --rm -v "$(pwd):/app" -w /app ubuntu:22.04 bash -c '
  apt-get update -qq && apt-get install -y -qq curl git >/dev/null 2>&1
  curl -fsSL https://git.io/shellspec 2>/dev/null | sh -s -- --yes >/dev/null 2>&1
  ~/.local/lib/shellspec/shellspec --format documentation
'
```

### 5. Build Locally

```bash
# Concatenate scripts (simulates CI build)
cat scripts/*.sh > pve-install.sh
chmod +x pve-install.sh
```

## Pull Request Process

### 1. Push Your Branch

```bash
git push origin feature/my-feature
```

### 2. Create Pull Request

Create a PR against the `main` branch.

### 3. Automated Checks

GitHub Actions will automatically:

1. **Lint** - Run ShellCheck
2. **Format** - Verify shfmt formatting
3. **Test** - Run ShellSpec tests
4. **Build** - Concatenate scripts and inject version
5. **Deploy** - Deploy test build to GitHub Pages

### 4. Test Your Changes

After the build completes, a bot will comment on your PR with a test command:

```bash
bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-installer/pve-install-pr.42.sh)
```

## Commit Message Format

Use emoji conventional commit format:

```text
<emoji> <type>: <short description>

<detailed explanation>

Changes:
- Specific change 1
- Specific change 2
```

**Example:**

```text
✨ feat: add IPv6 dual-stack support for network bridges

Added full IPv6 support with automatic detection, manual configuration,
and disable options.

Changes:
- Added validate_ipv6() and validate_ipv6_cidr() functions
- Added IPV6_MODE config option (auto/manual/disabled)
- Updated network templates with IPv6 placeholders
```

**Emoji Reference:**

| Emoji | Type | Description |
|-------|------|-------------|
| ✨ | `feat` | New features |
| 🐛 | `fix` | Bug fixes |
| 🔒️ | `security` | Security fixes |
| ♻️ | `refactor` | Code restructuring |
| 📝 | `docs` | Documentation |
| 🔧 | `chore` | Configuration, tooling |
| ⚡️ | `perf` | Performance improvements |
| ✅ | `test` | Adding or updating tests |

## Code Style

### Shell Script Guidelines

- **No `set -e`** - All error handling is explicit (interferes with traps)
- Quote variables: `"$variable"` not `$variable`
- Use `[[ ]]` for conditionals, not `[ ]`
- Use `$(command)` not backticks
- Prefix internal functions with `_`

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Global variables | `UPPER_SNAKE_CASE` | `MAIN_IPV4` |
| Local variables | `lower_snake_case` | `local result` |
| Public functions | `lower_snake_case` | `remote_run` |
| Private functions | `_prefix_name` | `_wiz_render_menu` |
| Files | `NNN-name.sh` | `300-configure-base.sh` |

### Function Prefixes

| Prefix | Location | Purpose |
|--------|----------|---------|
| `_wiz_` | 101-wizard-ui.sh | Wizard UI helpers |
| `_edit_` | 110-116 wizard | Field editors |
| `print_` | 010-display.sh | User messages |
| `validate_` | 040-043-validation-*.sh | Input validation |
| `remote_` | 021-ssh.sh | Remote execution |
| `deploy_` | 034-deploy-helpers.sh | Deployment helpers |
| `configure_` | 300-380 | Post-install config |
| `_config_` | configure scripts | Private config functions |
| `add_` / `start_` / `complete_` | 056-live-logs.sh | Live log operations |
| `log_` | 005-logging.sh, 056-live-logs.sh | Logging functions |

### Comments

- Add comments for complex logic
- Document function parameters in header comment
- Use `# shellcheck disable=SCXXXX` with explanation

## Templates

Templates use `{{VARIABLE}}` syntax. See [Templates Guide](docs/templates-guide.md) for:

- Variable naming and escaping
- Common variables reference
- Deployment patterns

## Getting Help

- Check [Troubleshooting](wiki/Troubleshooting.md) for common issues
- Open an [issue](https://github.com/qoxi-cloud/proxmox-installer/issues)
- Review existing code for patterns

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
