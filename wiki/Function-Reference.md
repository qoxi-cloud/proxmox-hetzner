# Function Reference

Complete reference for all public functions in the Proxmox Installer.

## Display Functions (`010-display.sh`)

### print_success

Prints success message with checkmark.

```bash
print_success "Operation completed"
print_success "Files" "15 copied"  # With value
```

### print_error

Prints error message with red cross.

```bash
print_error "Failed to connect"
```

### print_warning

Prints warning message with yellow icon.

```bash
print_warning "Low disk space"
print_warning "Timeout" "30s"  # With value
print_warning "Nested warning" "true"  # With indent
```

### print_info

Prints informational message with cyan icon.

```bash
print_info "Starting installation..."
```

### show_progress

Shows spinner while process runs.

```bash
(long_command) >/dev/null 2>&1 &
show_progress $! "Processing" "Done"

# Silent mode (clears line on success)
show_progress $! "Processing" "--silent"
```

### format_wizard_header

Formats wizard-style step header with line and dot.

```bash
format_wizard_header "Installation"
```

---

## Template Functions (`020-templates.sh`)

### apply_template_vars

Substitutes `{{VAR}}` placeholders in file.

```bash
apply_template_vars "/tmp/config" \
  "HOSTNAME=myserver" \
  "IP=192.168.1.1"
```

**Returns:** 0 on success, 1 if file not found or unsubstituted placeholders remain.

**Special character handling:** Automatically escapes `\`, `&`, `|`, and newlines.

### apply_common_template_vars

Applies common network/system variables from globals.

```bash
apply_common_template_vars "/tmp/interfaces"
```

**Variables applied:**
- `MAIN_IPV4`, `MAIN_IPV4_GW`, `MAIN_IPV6`, `FIRST_IPV6_CIDR`, `IPV6_GATEWAY`
- `FQDN`, `HOSTNAME`, `INTERFACE_NAME`
- `PRIVATE_IP_CIDR`, `PRIVATE_SUBNET`, `BRIDGE_MTU`
- `DNS_PRIMARY`, `DNS_SECONDARY`, `DNS6_PRIMARY`, `DNS6_SECONDARY`
- `LOCALE`, `KEYBOARD`, `COUNTRY`
- `PORT_SSH`, `PORT_PROXMOX_UI`

### download_template

Downloads template from GitHub with validation.

```bash
download_template "/tmp/sshd_config" "sshd_config"
```

---

## SSH Functions (`021-ssh.sh`, `022-ssh-remote.sh`)

### remote_exec

Low-level SSH execution with retry. Returns exit code.

```bash
if remote_exec 'systemctl status nginx'; then
  echo "nginx is running"
fi
```

**Use when:**
- Need return code handling
- Inside subshells with own progress
- Quick status checks

### remote_run

Primary function for configuration. Exits on failure.

```bash
remote_run "Installing nginx" 'apt-get install -y nginx' "Nginx installed"
```

**Parameters:**
1. Progress message (shown while running)
2. Script content (can be multi-line)
3. Done message (optional)

**Use when:**
- Major installation/configuration steps
- Commands that should show progress
- Failure should abort installation

### remote_copy

Copies file to remote via SCP.

```bash
remote_copy "/tmp/config" "/etc/app/config" || return 1
```

### wait_for_ssh_ready

Waits for SSH service on QEMU VM.

```bash
wait_for_ssh_ready 120  # 120 second timeout
```

### check_port_available

Checks if port is available (not in use).

```bash
if check_port_available 8080; then
  echo "Port 8080 is free"
fi
```

### parse_ssh_key

Parses SSH public key into components.

```bash
parse_ssh_key "$SSH_PUBLIC_KEY"
echo "Type: $SSH_KEY_TYPE"
echo "Short: $SSH_KEY_SHORT"
```

**Sets globals:** `SSH_KEY_TYPE`, `SSH_KEY_DATA`, `SSH_KEY_COMMENT`, `SSH_KEY_SHORT`

### get_rescue_ssh_key

Gets SSH key from rescue system's authorized_keys.

```bash
SSH_PUBLIC_KEY=$(get_rescue_ssh_key)
```

---

## Deployment Helpers (`034-deploy-helpers.sh`, `035-deploy-template.sh`)

### deploy_template

Deploys template with variable substitution to remote.

```bash
deploy_template "templates/nginx.conf" "/etc/nginx/nginx.conf" \
  "PORT=8080" \
  "SERVER_NAME=example.com"
```

### deploy_systemd_timer

Deploys both .service and .timer files, enables timer.

```bash
deploy_systemd_timer "aide-check"
# Deploys: aide-check.service + aide-check.timer
```

### deploy_systemd_service

Deploys .service file with optional vars, enables it.

```bash
deploy_systemd_service "network-ringbuffer" "INTERFACE=${INTERFACE_NAME}"
```

### deploy_user_config

Deploys config to admin user's home directory with optional template vars.

```bash
deploy_user_config "templates/bat-config" ".config/bat/config"
deploy_user_config "templates/zshrc" ".zshrc" "HOSTNAME=${HOSTNAME}"
# Creates: /home/$ADMIN_USERNAME/.config/bat/config
```

### run_with_progress

Runs command with progress indicator.

```bash
run_with_progress "Downloading" "Downloaded" curl -sLO "$url"
```

### remote_enable_services

Enables multiple systemd services in one call.

```bash
remote_enable_services "nginx" "php-fpm" "redis"
```

### make_feature_wrapper

Creates configure_* wrapper that checks INSTALL_* flag.

```bash
make_feature_wrapper "apparmor" "INSTALL_APPARMOR"
# Creates: configure_apparmor() that guards _config_apparmor()
```

### make_condition_wrapper

Creates configure_* wrapper with value comparison (not just boolean).

```bash
make_condition_wrapper "ssl" "SSL_TYPE" "letsencrypt"
# Creates: configure_ssl() that calls _config_ssl() only if SSL_TYPE="letsencrypt"
```

### deploy_timer_with_logdir

Deploys systemd timer and creates log directory in one call.

```bash
deploy_timer_with_logdir "chkrootkit-scan" "/var/log/chkrootkit"
# Deploys: chkrootkit-scan.service + chkrootkit-scan.timer + creates log dir
```

---

## Parallel Execution (`033-parallel-helpers.sh`)

### run_parallel_group

Runs multiple functions in parallel with single progress.

```bash
run_parallel_group "Configuring security" "Security configured" \
  _parallel_config_apparmor \
  _parallel_config_fail2ban \
  _parallel_config_auditd
```

**Returns:** Number of failed functions (0 = success)

### batch_install_packages

Installs all feature packages based on INSTALL_* flags.

```bash
batch_install_packages
```

**Checks flags:** `INSTALL_FIREWALL`, `INSTALL_TAILSCALE`, `INSTALL_AUDITD`, etc.

### install_base_packages

Installs base system packages (utilities, locales, chrony).

```bash
install_base_packages
```

### parallel_mark_configured

Marks feature as configured in parallel group.

```bash
_config_apparmor() {
  # ... configuration ...
  parallel_mark_configured "apparmor"
}
```

---

## Validation Functions (`040-043-validation-*.sh`)

### validate_hostname

Validates hostname format (alphanumeric, hyphens, 1-63 chars).

```bash
validate_hostname "my-server" && echo "valid"
```

### validate_fqdn

Validates fully qualified domain name.

```bash
validate_fqdn "server.example.com" && echo "valid"
```

### validate_email

Validates email address format.

```bash
validate_email "admin@example.com" && echo "valid"
```

### validate_subnet

Validates subnet in CIDR notation.

```bash
validate_subnet "10.0.0.0/24" && echo "valid"
```

### validate_ipv6

Validates IPv6 address (full, compressed, or mixed).

```bash
validate_ipv6 "2001:db8::1" && echo "valid"
```

### validate_ipv6_cidr

Validates IPv6 with CIDR prefix.

```bash
validate_ipv6_cidr "2001:db8::1/64" && echo "valid"
```

### validate_ipv6_gateway

Validates IPv6 gateway (accepts empty, "auto", or valid IPv6).

```bash
validate_ipv6_gateway "fe80::1" && echo "valid"
```

### validate_admin_username

Validates admin username (lowercase, starts with letter, blocks reserved).

```bash
validate_admin_username "deploy" && echo "valid"
```

### validate_tailscale_key

Validates Tailscale authentication key format.

```bash
validate_tailscale_key "tskey-auth-xxx-yyy" && echo "valid"
```

### validate_ssh_key_secure

Validates SSH key format and security (no weak keys).

```bash
validate_ssh_key_secure "$SSH_PUBLIC_KEY" && echo "valid"
```

### validate_dns_resolution

Validates FQDN resolves to expected IP.

```bash
validate_dns_resolution "server.example.com" "1.2.3.4"
# Returns: 0=match, 1=no resolution, 2=wrong IP
# Sets: DNS_RESOLVED_IP
```

### validate_disk_space

Validates available disk space.

```bash
validate_disk_space "/root" 5000  # 5GB minimum
# Sets: DISK_SPACE_MB
```

### get_password_error

Returns error message for invalid password.

```bash
error=$(get_password_error "weak")
[[ -n $error ]] && echo "$error"
```

### is_ascii_printable

Checks if string contains only ASCII printable characters.

```bash
is_ascii_printable "hello" && echo "valid"
```

---

## Logging Functions (`006-logging.sh`)

### log

Writes to log file (not shown to user).

```bash
log "INFO: Operation started"
log "ERROR: Connection failed"
log "WARNING: Timeout exceeded"
```

### metrics_start

Starts installation timer. No parameters.

```bash
metrics_start
```

**Side effects:** Sets `INSTALL_START_TIME` global.

### log_metric

Logs a completed step with elapsed time.

```bash
log_metric "iso_download"
log_metric "qemu_start"
```

**Requires:** `INSTALL_START_TIME` must be set (via `metrics_start`).

### metrics_finish

Logs final installation metrics summary. No parameters.

```bash
metrics_finish
```

**Requires:** `INSTALL_START_TIME` must be set.

---

## Live Logs Functions (`056-live-logs.sh`)

### start_task

Starts a task line with "..." suffix.

```bash
start_task "Installing packages"
```

**Side effects:** Adds log entry, sets `TASK_INDEX` to current position.

### complete_task

Updates a task log line with final status.

```bash
complete_task "$TASK_INDEX" "Packages installed" "success"  # Green ✓ (default)
complete_task "$TASK_INDEX" "Installation failed" "error"   # Red ✗
complete_task "$TASK_INDEX" "Skipped optional" "warning"    # Yellow ⚠
```

**Parameters:**
1. Task index in `LOG_LINES` array
2. Final message to display
3. Status: `success` (default), `error`, `warning`

### add_log

Adds a new log line and triggers re-render.

```bash
add_log "Configuring firewall"
```

### start_live_installation

Enters alternate screen buffer for live installation display.

```bash
start_live_installation
```

**Side effects:** Overrides `show_progress` with live version, hides cursor.

### finish_live_installation

Exits alternate screen buffer and restores terminal.

```bash
finish_live_installation
```

### add_subtask_log

Adds a single indented subtask log entry with tree structure prefix.

```bash
add_subtask_log "Installing package"
add_subtask_log "Optional step" "$CLR_GRAY"  # Custom color
```

**Parameters:**
1. Message to display
2. Optional color (default: `CLR_GRAY`)

### live_log_subtask

Alias for `add_subtask_log`. Adds subtask during live installation.

```bash
live_log_subtask "Configuring service"
```

### log_subtasks

Logs multiple items as comma-separated list with tree structure prefix.

```bash
log_subtasks "nginx" "php-fpm" "redis"
# Output:
#   │   nginx, php-fpm, redis
```

**Note:** Automatically wraps long lines at ~55 characters.

---

## ZFS Functions (`031-zfs-helpers.sh`, `053-system-drives.sh`)

### detect_existing_pools

Detects existing ZFS pools available for import.

```bash
detect_existing_pools
# Output: pool_name|state|/dev/disk1,/dev/disk2 (one per line)
```

**Returns:** Pool info via stdout (name|status|disks format).

### get_pool_disks

Gets disk paths for a specific pool.

```bash
disks=$(get_pool_disks "tank")
# Returns: /dev/nvme0n1,/dev/nvme1n1
```

### build_zpool_command

Builds zpool create command for given RAID type.

```bash
cmd=$(build_zpool_command "tank" "raid1" /dev/vda /dev/vdb)
# Returns: zpool create -f tank mirror /dev/vda /dev/vdb
```

### create_virtio_mapping

Creates mapping between physical and virtio disks for QEMU.

```bash
create_virtio_mapping "/dev/nvme2n1" "/dev/nvme0n1" "/dev/nvme1n1"
# Creates: /tmp/virtio_map.env
```

### load_virtio_mapping

Loads virtio mapping from saved file.

```bash
load_virtio_mapping
echo "${VIRTIO_MAP[/dev/nvme0n1]}"  # vdb
```

---

## Utility Functions (`012-utils.sh`)

### secure_delete_file

Securely deletes file (shred + dd fallback).

```bash
secure_delete_file "/tmp/passfile"
```

---

## Download Functions (`011-downloads.sh`)

### download_file

Downloads file with retry logic.

```bash
download_file "/tmp/iso.img" "https://example.com/file.iso"
```

---

## Password Functions (`030-password-utils.sh`)

### generate_password

Generates a secure random password.

```bash
password=$(generate_password)      # 16 chars (default)
password=$(generate_password 24)   # 24 chars
```

**Returns:** Random password (alphanumeric + `!@#$%^&*`) via stdout.

---

## Validation UI Functions (`032-validation-helpers.sh`)

### show_validation_error

Displays validation error message in gum style.

```bash
show_validation_error "Invalid hostname format"
```

**Side effects:** Shows error message, pauses for 3 seconds.

