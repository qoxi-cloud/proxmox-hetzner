# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language Requirements

**All content in this repository MUST be in English only.** This includes:

- Commit messages
- Pull request titles and descriptions
- Code comments
- Documentation files
- Variable and function names
- Log messages and user-facing strings
- Branch names

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

## Pull Request Format

When creating pull requests, use the template at `.github/pull_request_template.md`. PR titles must follow the same emoji conventional format as commit messages.

**PR Title Format:**

```text
<emoji> <type>: <short description>
```

**Example:**

```text
✨ feat: add IPv6 dual-stack support for network bridges
```

**PR Body Structure:**

```markdown
## Summary

Brief description of what this PR does

## Changes

- List specific changes
- Each change on its own line

## Type of Change

- [x] New feature (`feat`)

## Testing

- [x] Unit tests pass (`./tests/run-all-tests.sh`)
- [x] ShellCheck passes (`shellcheck scripts/*.sh`)
- [x] Manual testing performed

## Checklist

- [x] Code follows project conventions (see CLAUDE.md)
- [x] All content is in English
- [x] Commit messages follow emoji conventional format
- [x] No secrets or credentials included
```

## Project Overview

Automated Proxmox VE installer for Hetzner dedicated servers without console access. The installer runs in Hetzner Rescue System and uses QEMU to install Proxmox on NVMe drives.

## Build System

The project uses a modular shell script architecture. Individual scripts in `scripts/` are concatenated into a single `pve-install.sh` by GitHub Actions.

**Build locally (simulates CI):**

```bash
cat scripts/*.sh > pve-install.sh
chmod +x pve-install.sh
```

**Lint scripts:**

```bash
shellcheck scripts/*.sh
# Ignored warnings: SC1003 (ASCII art escapes), SC1091 (sourced files), SC2001 (sed for complex regex), SC2034 (unused vars), SC2086 (word splitting)
```

**Format scripts:**

```bash
shfmt -i 2 -ci -s -w scripts/*.sh
# -i 2: 2-space indent
# -ci: indent switch cases
# -s: simplify code
# -w: write in-place
```

**Run unit tests:**

```bash
./tests/run-all-tests.sh
```

## Unit Tests

The project includes comprehensive unit tests in the `tests/` directory:

| Test File | Module | Tests | Description |
|-----------|--------|-------|-------------|
| `test-validation.sh` | 05-validation.sh | 103 | Hostname, FQDN, email, password, subnet, IPv6 validation |
| `test-ssh.sh` | 03-ssh.sh | 16 | SSH key validation and parsing |
| `test-main.sh` | 99-main.sh | 8 | String truncation utilities |
| `test-utils.sh` | 02-utils.sh | 7 | Duration formatting |
| `run-all-tests.sh` | - | - | Test runner aggregating all tests |

**Test structure:**

Each test file uses a simple assertion framework:

```bash
assert_true "description" command args...   # Expects command to succeed
assert_false "description" command args...  # Expects command to fail
assert_equals "description" "expected" "actual"
assert_not_empty "description" "$value"
```

**Function extraction pattern:**

Tests extract individual functions using `sed` to avoid loading entire scripts with dependencies:

```bash
eval "$(sed -n '/^function_name()/,/^}/p' "$SCRIPT_DIR/scripts/module.sh")"
```

**Cross-platform notes:**

- Tests are designed to work on both macOS and Linux
- Some functions (e.g., `apply_template_vars` using `sed -i`) are not tested due to platform differences
- Tests run in CI on Ubuntu runners

**IMPORTANT: Running tests on non-Ubuntu systems (e.g., macOS):**

CI runs on Ubuntu, and there are subtle differences in shell behavior between platforms (e.g., locale handling, `${#var}` for UTF-8 strings). To ensure tests pass in CI, **always run tests in Docker** when developing on macOS or other non-Ubuntu systems:

```bash
# Run all tests in Ubuntu container (matches CI environment)
docker run --rm -v "$(pwd)":/workspace -w /workspace ubuntu:latest bash -c "
    apt-get update && apt-get install -y bash coreutils
    ./tests/run-all-tests.sh
"

# Run a specific test file
docker run --rm -v "$(pwd)":/workspace -w /workspace ubuntu:latest bash -c "
    apt-get update && apt-get install -y bash coreutils
    ./tests/test-validation.sh
"
```

This prevents false positives where tests pass locally but fail in CI due to platform differences.

## CI/CD Workflow

The project uses multiple GitHub Actions workflows:

### CI Workflow (`ci.yml`)

**Build Job** - Runs on every push and pull request:

1. Checkout code (including fork PRs)
2. Concatenate scripts into `pve-install.sh`
3. Check formatting with `shfmt -i 2 -ci -s -d`
4. Minify with `shfmt -mn` to create `pve-install.min.sh`
5. Run ShellCheck linting
6. Run unit tests (`./tests/run-all-tests.sh`)
7. Calculate and inject version number
8. Upload artifacts and PR metadata

**Deploy Job** - Runs only on push to main:

1. Download build artifacts
2. Deploy to GitHub Pages as `pve-install.min.sh` (minified) and `pve-install.sh` (full)

### Deploy PR Workflow (`deploy-pr.yml`)

Runs after build completes for PRs (including forks):

1. Download build artifact and PR metadata
2. Deploy to GitHub Pages as `pve-install-pr.{number}.min.sh`
3. Post/update comment on PR with test link

Uses `workflow_run` trigger for secure fork PR deployments.

**PR builds include:**

- Version suffix: `1.2.5-pr.42`
- Updated `GITHUB_BRANCH` to load templates from PR branch
- For forks: Updated `GITHUB_REPO` to load templates from fork
- Auto-generated comment with download link

### Cleanup PR Workflow (`cleanup-pr.yml`)

Runs when PR is closed (merged or rejected):

1. Remove `pve-install-pr.{number}.min.sh` from GitHub Pages

Uses `pull_request_target` for secure access to close events from forks.

### Commit Lint Workflow (`commit-lint.yml`)

Runs on every PR to validate:

1. All commit messages follow emoji conventional format
2. PR title follows the same format

Skips merge commits and bot commits automatically.

## Versioning

The project uses **Semantic Versioning** with automatic MINOR and PATCH calculation:

| Component | Source | Description |
|-----------|--------|-------------|
| **MAJOR** | `scripts/00-init.sh` | Stored as `VERSION="1"` (only the major number) |
| **MINOR** | Git tags | Count of tags matching `v{MAJOR}.*` |
| **PATCH** | Git commits | Commits since the last tag |

**How it works:**

1. `00-init.sh` contains only the MAJOR version: `VERSION="1"`
2. GitHub Actions calculates the full version during build
3. The final `pve-install.min.sh` contains the complete version (e.g., `VERSION="1.2.5"`)
4. Version changes are NOT pushed back to the repository

**Version examples:**

| Situation | Resulting Version |
|-----------|-------------------|
| MAJOR=1, 0 tags, 50 commits | `1.0.50` |
| MAJOR=1, tag `v1.0.0`, 0 commits after | `1.1.0` |
| MAJOR=1, tag `v1.0.0`, 10 commits after | `1.1.10` |
| MAJOR=1, tags `v1.0.0` + `v1.1.0`, 5 commits after | `1.2.5` |
| PR #42 build | `1.2.5-pr.42` |

**PR version suffix:**

Pull request builds include a `-pr.{number}` suffix to distinguish them from main branch builds:

- Main branch: `1.2.5`
- PR #42: `1.2.5-pr.42`
- PR #123: `1.2.5-pr.123`

This allows testing PR artifacts without confusion with release versions.

**Creating a release:**

```bash
git tag v1.0.0
git push --tags
```

This increments MINOR and resets PATCH to 0 on next build.

**Bumping MAJOR version:**

Edit `VERSION="2"` in `scripts/00-init.sh` — MINOR/PATCH will reset based on `v2.*` tags.

## Architecture

### Script Execution Order

Scripts are numbered and concatenated in order:

#### Initialization (00-00d)

- `00-init.sh` - Shebang, colors, version, configuration constants (see Constants section)
- `00a-cli.sh` - Command line argument parsing
- `00c-logging.sh` - Logging functions
- `00d-banner.sh` - ASCII banner and startup display

#### UI and Utilities (01-05)

- `01-display.sh` - Box/table display utilities using `boxes` command
- `02-utils.sh` - Download, password input, progress spinners, template utilities
- `03-ssh.sh` - SSH helpers for remote execution into QEMU VM
- `04-menu.sh` - Interactive menu system (radio_menu for single-select, checkbox_menu for multi-select)
- `05-validation.sh` - Input validators (hostname, email, subnet, password, etc.)

#### System Detection (06-07)

- `06-system-check.sh` - Pre-flight checks (root, RAM, KVM, NVMe detection), auto-installs required utilities
- `07-network.sh` - Network interface detection with fallback chain (ip -j | jq → ip | awk → ifconfig/route)

#### Input Collection (09-10)

- `09-input-interactive.sh` - Interactive input collection with menus
- `10-input-main.sh` - Main input orchestration function

#### Installation (11-12)

- `11-packages.sh` - Package installation, ISO download (with fallback chain), answer.toml generation
- `12-qemu.sh` - QEMU VM management for installation and boot, drive release with findmnt

#### Post-Install Configuration (13-18)

- `13-templates.sh` - Template download and preparation
- `14-configure-base.sh` - Base system configuration (ZFS, packages, shell)
- `15-configure-tailscale.sh` - Tailscale VPN configuration (uses jq for JSON parsing)
- `15a-configure-fail2ban.sh` - Fail2Ban brute-force protection (when Tailscale not used)
- `15b-configure-auditd.sh` - Auditd audit logging for administrative actions
- `16-configure-ssl.sh` - SSL certificate configuration (self-signed or Let's Encrypt)
- `17-configure-finalize.sh` - SSH hardening and VM finalization
- `18-validate.sh` - Post-installation validation (SSH, ZFS, network, services)

#### Main Flow (99)

- `99-main.sh` - Main execution flow and installation summary

### Key Flow

```text
collect_system_info → show_system_status → get_system_inputs →
prepare_packages → download_proxmox_iso → make_answer_toml →
make_autoinstall_iso → install_proxmox → boot_proxmox_with_port_forwarding →
configure_proxmox_via_ssh → reboot_to_main_os
```

### Configuration Constants

Centralized constants in `00-init.sh` (can be overridden via environment variables):

| Constant Group | Examples |
|----------------|----------|
| GitHub URLs | `GITHUB_REPO`, `GITHUB_BRANCH`, `GITHUB_BASE_URL` |
| Proxmox URLs | `PROXMOX_ISO_BASE_URL`, `PROXMOX_CHECKSUM_URL` |
| DNS servers (IPv4) | `DNS_SERVERS[]`, `DNS_PRIMARY`, `DNS_SECONDARY`, etc. |
| DNS servers (IPv6) | `DNS6_PRIMARY`, `DNS6_SECONDARY`, `DNS6_TERTIARY`, `DNS6_QUATERNARY` |
| Resource limits | `MIN_DISK_SPACE_MB`, `MIN_RAM_MB`, `MIN_CPU_CORES` |
| QEMU defaults | `DEFAULT_QEMU_RAM`, `MIN_QEMU_RAM`, `MAX_QEMU_CORES`, `QEMU_MIN_RAM_RESERVE` |
| Default values | `DEFAULT_HOSTNAME`, `DEFAULT_TIMEZONE`, `DEFAULT_SUBNET`, `DEFAULT_BRIDGE_MTU`, etc. |
| CPU governor | `DEFAULT_CPU_GOVERNOR` (performance, ondemand, powersave, schedutil, conservative) |
| IPv6 defaults | `DEFAULT_IPV6_MODE`, `DEFAULT_IPV6_GATEWAY`, `DEFAULT_IPV6_VM_PREFIX` |
| Packages | `SYSTEM_UTILITIES`, `OPTIONAL_PACKAGES` |
| Timeouts | `DNS_LOOKUP_TIMEOUT`, `SSH_CONNECT_TIMEOUT`, `SSH_READY_TIMEOUT`, `QEMU_BOOT_TIMEOUT` |
| Retry settings | `DNS_RETRY_DELAY`, `DOWNLOAD_RETRY_COUNT`, `DOWNLOAD_RETRY_DELAY` |
| Password | `DEFAULT_PASSWORD_LENGTH` (default: 16) |

### Auto-Installed Utilities

The installer automatically installs required utilities in `06-system-check.sh`:

| Utility | Package | Purpose |
|---------|---------|---------|
| `boxes` | boxes | Box/table display formatting |
| `column` | bsdmainutils | Column alignment in tables |
| `ip` | iproute2 | Network interface detection |
| `udevadm` | udev | Predictable interface name detection |
| `timeout` | coreutils | Command timeouts |
| `curl` | curl | HTTP requests and ISO downloads |
| `jq` | jq | JSON parsing (network info, Tailscale status) |
| `aria2c` | aria2 | Optional multi-connection downloads (fallback: curl, wget) |
| `findmnt` | util-linux | Efficient mount point detection |

### Templates

Configuration files in `templates/` are downloaded at runtime from GitHub raw URLs and customized with placeholder substitution.

**All template files use `.tmpl` extension** (e.g., `hosts.tmpl`, `zshrc.tmpl`). The `download_template()` function automatically adds `.tmpl` when fetching from GitHub, so scripts reference templates without the extension.

#### Template Categories

| Category | Files |
|----------|-------|
| Network config | `interfaces.internal`, `interfaces.external`, `interfaces.both`, `resolv.conf` |
| System config | `hosts`, `sshd_config`, `chrony`, `debian.sources`, `proxmox.sources`, `99-proxmox.conf` |
| Locale | `locale.sh`, `default-locale`, `environment` |
| Shell | `zshrc`, `p10k.zsh`, `fastfetch.sh` |
| Scripts | `configure-zfs-arc.sh`, `remove-subscription-nag.sh` |
| Services | `cpufrequtils`, `50unattended-upgrades`, `20auto-upgrades` |
| SSL | `letsencrypt-deploy-hook.sh`, `letsencrypt-firstboot.sh`, `letsencrypt-firstboot.service` |
| Tailscale | `disable-openssh.service`, `stealth-firewall.service` |
| Security | `fail2ban-jail.local`, `fail2ban-proxmox.conf`, `auditd-rules` |
| Installation | `answer.toml` |

#### Template Placeholders

- `{{MAIN_IPV4}}`, `{{MAIN_IPV4_GW}}`, `{{FQDN}}`, `{{HOSTNAME}}` - IPv4 and host values
- `{{MAIN_IPV6}}`, `{{IPV6_GATEWAY}}`, `{{FIRST_IPV6_CIDR}}` - IPv6 configuration
- `{{INTERFACE_NAME}}`, `{{PRIVATE_IP_CIDR}}`, `{{PRIVATE_SUBNET}}`, `{{BRIDGE_MTU}}` - Bridge config
- `{{DNS_PRIMARY}}`, `{{DNS_SECONDARY}}`, etc. - IPv4 DNS servers
- `{{DNS6_PRIMARY}}`, `{{DNS6_SECONDARY}}` - IPv6 DNS servers
- `{{CPU_GOVERNOR}}` - CPU frequency scaling governor

#### Template Utility Functions

- `download_template "LOCAL_PATH" ["REMOTE_FILENAME"]` - Download template from GitHub
- `apply_template_vars "FILE" "VAR1=VALUE1" ...` - Apply variable substitutions
- `apply_common_template_vars "FILE"` - Apply standard variables (IP, hostname, etc.)

### Remote Execution Pattern

Post-install configuration runs via SSH into QEMU VM on port 5555:

- `remote_exec "command"` - Run single command
- `run_remote "message" 'script' "done_msg"` - Run with spinner, exit on failure with log reference
- `remote_exec_with_progress "message" 'script' "done_msg"` - Run with spinner (returns exit code)
- `remote_copy "local" "remote"` - SCP file to VM

## CLI Options

| Option | Description |
|--------|-------------|
| `--qemu-ram MB` | Override QEMU RAM (default: auto 4096-8192) |
| `--qemu-cores N` | Override QEMU CPU cores (default: auto, max 16) |
| `--iso-version FILE` | Use specific Proxmox ISO (e.g., proxmox-ve_8.3-1.iso) |

## Conventions

- All scripts share global variables (no `local` for exported values)
- Progress indicators use spinner chars: `SPINNER_CHARS=('○' '◔' '◑' '◕' '●' '◕' '◑' '◔')`
- Menu width is fixed: `MENU_BOX_WIDTH=60`
- Colors: `CLR_RED`, `CLR_GREEN`, `CLR_YELLOW`, `CLR_ORANGE`, `CLR_GRAY`, `CLR_HETZNER`, `CLR_RESET`
- Status markers: `[OK]`, `[WARN]`, `[ERROR]` - colorized by `colorize_status` function
- SSH functions use `SSHPASS` env var to avoid password exposure in process list

### Fallback Patterns

The installer uses fallback chains for compatibility across different environments:

#### Network Detection (07-network.sh)

```text
ip -j | jq (JSON) → ip | awk (text) → ifconfig/route (legacy)
```

#### DNS Resolution (05-validation.sh)

```text
dig → host → nslookup → getent hosts
```

All DNS commands use configurable timeout (`DNS_LOOKUP_TIMEOUT`, default: 5s).

#### Mount Detection (12-qemu.sh)

```text
findmnt (efficient) → mount | grep (fallback)
```

#### ISO Download (11-packages.sh)

```text
aria2c (2 connections) → curl (single, resume) → wget (single, resume)
```

Uses a fallback chain for reliability. aria2c is tried first with conservative settings (2 connections to avoid rate limiting), then falls back to curl or wget. All methods support resume and retry.

Helper functions:

- `_download_iso_aria2c()` - Multi-connection download with checksum verification
- `_download_iso_curl()` - Single connection with retry and resume support
- `_download_iso_wget()` - Single connection fallback

### Helper Function Patterns

Large functions are decomposed into smaller helper functions prefixed with `_` for internal use:

#### Network Detection Helpers (07-network.sh)

- `_get_ipv4_via_ip_json()` - IPv4 detection using `ip -j` + `jq`
- `_get_ipv4_via_ip_text()` - IPv4 detection using `ip` text parsing
- `_get_ipv4_via_ifconfig()` - IPv4 detection using legacy `ifconfig`
- `_get_mac_and_ipv6()` - MAC address and IPv6 detection
- `_validate_network_config()` - Network configuration validation
- `_calculate_ipv6_prefix()` - IPv6 prefix calculation for VM network

#### Drive Release Helpers (12-qemu.sh)

- `_signal_process()` - Send signal to process if running
- `_kill_processes_by_pattern()` - Kill processes with graceful→forced termination
- `_stop_mdadm_arrays()` - Stop RAID arrays
- `_deactivate_lvm()` - Deactivate LVM volume groups
- `_unmount_drive_filesystems()` - Unmount filesystems on drives
- `_kill_drive_holders()` - Kill processes holding drives open

#### Validation Helpers (18-validate.sh)

- `_add_validation_result()` - Add result with status (pass/fail/warn)
- `_validate_ssh()` - Check SSH service, keys, and authentication settings
- `_validate_zfs()` - Check ZFS pools, health, and ARC configuration
- `_validate_network()` - Check interfaces, bridges, IPv4/IPv6 connectivity, DNS
- `_validate_services()` - Check Proxmox services (pve-cluster, pvedaemon, etc.)
- `_validate_proxmox()` - Check web UI, API, and storage
- `_validate_optional()` - Check Tailscale, Fail2Ban, Auditd if installed
- `_validate_ssl()` - Check SSL certificate presence and validity
- `_display_validation_summary()` - Display results in formatted box

### Error Handling Patterns

#### Download Functions (02-utils.sh)

Download functions return error codes instead of calling `exit`:

```bash
# Returns 0 on success, 1 on failure
download_file "output" "url"
download_template "local_path" ["remote_filename"]
```

Callers handle errors appropriately:

```bash
# In subshell with show_progress - exits subshell on error
(
    download_template "./templates/hosts" || exit 1
    download_template "./templates/sshd_config" || exit 1
) > /dev/null 2>&1 &
if ! show_progress $! "Downloading templates"; then
    log "ERROR: Download failed"
    exit 1
fi
```

#### SSH Hardening Pattern (17-configure-finalize.sh)

Critical operations use subshell + `show_progress` pattern with error checking:

```bash
configure_ssh_hardening() {
    local escaped_ssh_key="${SSH_PUBLIC_KEY//\'/\'\\\'\'}"
    (
        remote_exec "mkdir -p /root/.ssh" || exit 1
        remote_exec "echo '${escaped_ssh_key}' >> /root/.ssh/authorized_keys" || exit 1
        remote_copy "templates/sshd_config" "/etc/ssh/sshd_config" || exit 1
    ) > /dev/null 2>&1 &
    show_progress $! "Deploying SSH hardening"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: SSH hardening failed"
        exit 1
    fi
}
```

#### Temporary File Cleanup (15-configure-tailscale.sh)

Use `trap RETURN` for automatic cleanup:

```bash
local tmp_ip=$(mktemp)
trap "rm -f '$tmp_ip'" RETURN
```

### IPv6 Validation Functions (05-validation.sh)

IPv6 validation functions for dual-stack support:

- `validate_ipv6()` - Validate IPv6 address (full, compressed, or mixed format)
- `validate_ipv6_cidr()` - Validate IPv6 with CIDR prefix (e.g., `2001:db8::1/64`)
- `validate_ipv6_gateway()` - Validate IPv6 gateway (accepts empty, `auto`, or valid IPv6)
- `validate_ipv6_prefix_length()` - Validate prefix length (48-128)
- `is_ipv6_link_local()` - Check if address is link-local (fe80::/10)
- `is_ipv6_ula()` - Check if address is ULA (fc00::/7)
- `is_ipv6_global()` - Check if address is global unicast (2000::/3)

### Interactive Menu Functions (04-menu.sh)

Two types of interactive menus are available:

#### Radio Menu (single-select)

```bash
radio_menu "Title" "header_content" "label1|desc1" "label2|desc2" ...
# Result: MENU_SELECTED (0-based index)
```

#### Checkbox Menu (multi-select)

```bash
checkbox_menu "Title" "header_content" "label1|desc1|default1" "label2|desc2|default2" ...
# default: 1 = checked, 0 = unchecked
# Result: CHECKBOX_RESULTS array (1=selected, 0=not selected)
```

Navigation:

- ↑/↓ arrows to move cursor
- Space to toggle selection (checkbox only)
- Enter to confirm

### Password Validation (05-validation.sh)

Password validation uses `get_password_error()` for consistent error messages:

```bash
password_error=$(get_password_error "$password")
if [[ -n "$password_error" ]]; then
    print_error "$password_error"
fi
```

### Safe Variable Assignment

Use `printf -v` instead of `eval` for dynamic variable assignment:

```bash
# Safe (no command injection risk)
printf -v "$var_name" '%s' "$value"

# Unsafe (avoid)
eval "$var_name=\"\$value\""
```
