# Contributing to Proxmox Hetzner Installer

Thank you for your interest in contributing! This guide will help you get started.

## Development Setup

### Prerequisites

- Bash 4.0+
- [ShellCheck](https://www.shellcheck.net/) for linting
- Git

### Clone and Setup

```bash
git clone https://github.com/qoxi-cloud/proxmox-hetzner.git
cd proxmox-hetzner

# Enable commit message validation (recommended)
git config core.hooksPath .githooks
```

The git hooks will automatically validate your commit messages before each commit.

### Project Structure

```
proxmox-hetzner/
├── scripts/           # Source scripts (numbered for concatenation order)
│   ├── 00-init.sh     # Initialization, colors, version, constants
│   ├── 01-cli.sh      # CLI argument parsing
│   ├── 02-logging.sh  # Logging system
│   ├── 03-banner.sh   # ASCII banner display
│   ├── ...
│   └── 99-main.sh     # Main execution flow
├── templates/         # Configuration templates (.tmpl extension)
├── tests/             # Unit tests
│   ├── test-*.sh      # Individual test files
│   └── run-all-tests.sh
└── .github/workflows/ # CI/CD pipelines
```

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/my-feature
# or
git checkout -b fix/bug-description
```

### 2. Edit Scripts

Scripts are in `scripts/` directory, organized by number ranges:
- `00-09` - Initialization (init, cli, logging, banner)
- `10-19` - Utilities & Display (UI, downloads, templates, ssh, helpers)
- `20-29` - Validation & System Checks (validation, system info, live logs)
- `30-39` - User Interaction (wizard: core, ui, editors)
- `40-49` - Installation (packages, qemu, templates)
- `50-59` - Post-Install Configuration (base, tailscale, fail2ban, auditd, yazi, nvim, ssl, finalize)
- `90-99` - Main flow

### 3. Edit Templates

Templates are in `templates/` with `.tmpl` extension. Use placeholders like:
- `{{HOSTNAME}}`, `{{FQDN}}`
- `{{MAIN_IPV4}}`, `{{MAIN_IPV6}}`
- `{{DNS_PRIMARY}}`, `{{DNS_SECONDARY}}`

See [CLAUDE.md](CLAUDE.md) for full list of placeholders.

### 4. Run Tests Locally

```bash
# Run all tests
./tests/run-all-tests.sh

# Run specific test
./tests/test-validation.sh

# Lint scripts
shellcheck -e SC1091,SC2034,SC2086 scripts/*.sh
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

When you create a PR, GitHub Actions will automatically:

1. **Build** - Concatenate scripts and inject version
2. **Lint** - Run ShellCheck
3. **Test** - Run unit tests (176 tests)
4. **Deploy** - Deploy test build to GitHub Pages

### 4. Test Your Changes

After the build completes, a bot will comment on your PR with:

```
## Test Build Available

| Property | Value |
|----------|-------|
| **Version** | `1.2.5-pr.42` |
| **Branch** | `feature/my-feature` |

### Quick Install (for testing)

bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-hetzner/pve-install-pr.42.sh)
```

You can test your changes on a Hetzner server using this command.

### 5. Fork PRs

PRs from forks are fully supported:
- Templates will be loaded from your fork
- The test build will use your fork's branch

## Commit Message Format

Use emoji conventional commit format:

```text
<emoji> <type>: <short description>

<detailed explanation of changes>

Changes:
- Bullet point list of specific changes
- Each change on its own line
- Focus on "what" and "why"

<additional context if needed>
```

**Example:**

```text
✨ feat: add IPv6 dual-stack support for network bridges

Added full IPv6 support with automatic detection, manual configuration, and disable options. The installer now properly configures both IPv4 and IPv6 addresses on network bridges.

Changes:
- Added validate_ipv6() and validate_ipv6_cidr() functions
- Added IPV6_MODE config option (auto/manual/disabled)
- Updated network templates with IPv6 placeholders
- Added IPv6 gateway detection from Hetzner metadata

Tested on AX41-NVMe with /64 subnet allocation.
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
| 🩹 | `fix` | Simple non-critical fixes |
| 🚑️ | `hotfix` | Critical hotfixes |
| ✅ | `test` | Adding or updating tests |
| 🏗️ | `build` | Build system changes |
| 👷 | `ci` | CI/CD changes |

## Code Style

### Shell Script Guidelines

- Use `set -euo pipefail` at script start
- Quote variables: `"$variable"` not `$variable`
- Use `[[ ]]` for conditionals, not `[ ]`
- Use `$(command)` not backticks
- Prefix internal helper functions with `_`

### Naming Conventions

- Variables: `UPPER_SNAKE_CASE` for globals, `lower_snake_case` for locals
- Functions: `lower_snake_case`
- Files: `NN-name.sh` where NN is execution order

### Comments

- Add comments for complex logic
- Document function parameters
- Keep comments in English

## Testing

### Writing Tests

Tests use a simple assertion framework:

```bash
# Test that passes when command succeeds
assert_true "description" validate_hostname "pve01"

# Test that passes when command fails
assert_false "description" validate_hostname "-invalid"

# Test exact value match
assert_equals "description" "expected" "$actual"
```

### Test File Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

# Extract function to test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(sed -n '/^function_name()/,/^}/p' "$SCRIPT_DIR/scripts/module.sh")"

# Tests
assert_true "test case 1" function_name "arg1"
assert_false "test case 2" function_name "invalid"

# Summary
echo "Tests run: $TESTS_RUN"
```

## Versioning

The project uses semantic versioning:
- **MAJOR** - Set in `scripts/00-init.sh` (MAJOR_VERSION variable)
- **MINOR** - Count of git tags
- **PATCH** - Commits since last tag

Version is injected during build by CI pipeline.
PR builds get a `-pr.{number}` suffix.

## Getting Help

- Open an [issue](https://github.com/qoxi-cloud/proxmox-hetzner/issues)
- Check [CLAUDE.md](CLAUDE.md) for detailed architecture docs

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
