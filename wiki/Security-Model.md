# Security Model

Security practices and credential handling in the Proxmox Installer.

## Overview

The installer handles sensitive data including:

- Root password for Proxmox
- Admin user password
- SSH private/public keys
- Tailscale authentication keys
- API tokens

## Credential Lifecycle

```text
Generation → Storage → Usage → Cleanup
    ↓           ↓        ↓        ↓
  Random     Passfile   SSH    Secure
  /dev/urandom  /dev/shm  sshpass  shred
```

## Password Generation

### Root Password

Generated in `034-password-utils.sh`:

```bash
generate_password() {
  local length="${1:-24}"
  local chars='A-Za-z0-9!@#$%^&*()-_=+[]{}|;:,.<>?'
  tr -dc "$chars" </dev/urandom | head -c "$length"
}
```

**Characteristics:**

- 24 characters by default
- Alphanumeric + special characters
- Cryptographically random from `/dev/urandom`
- Never logged or echoed to screen

### Admin Password

Same generation method, separate variable:

```bash
ADMIN_PASSWORD=$(generate_password 24)
```

## Passfile Management

SSH passwords are stored in temporary passfiles, never passed on command line.

### Session Initialization

```bash
_ssh_session_init() {
  # Prefer /dev/shm (RAM-backed, no disk writes)
  local passfile_dir="/dev/shm"
  if [[ ! -d /dev/shm ]] || [[ ! -w /dev/shm ]]; then
    passfile_dir="/tmp"
  fi
  
  # Predictable path with $$ so subshells share same file
  local passfile_path="${passfile_dir}/pve-ssh-session.$$"
  
  # Create with restricted permissions
  printf '%s\n' "$NEW_ROOT_PASSWORD" >"$passfile_path"
  chmod 600 "$passfile_path"
}
```

### SSH Usage

```bash
# Password read from file, never on command line
sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "$@"
```

This prevents password exposure in:

- Process listings (`ps aux`)
- Shell history
- System logs

### Session Cleanup

```bash
_ssh_session_cleanup() {
  # Secure deletion with shred
  if command -v shred &>/dev/null; then
    shred -u -z "$passfile_path" 2>/dev/null
  else
    # Fallback: overwrite with zeros
    local file_size=$(stat -c%s "$passfile_path")
    dd if=/dev/zero of="$passfile_path" bs=1 count="$file_size" conv=notrunc
    rm -f "$passfile_path"
  fi
}
```

**shred options:**

- `-u` - unlink (delete) after overwriting
- `-z` - add final zero overwrite to hide shredding

## Cleanup Trap

Global cleanup handler ensures credentials are deleted on any exit:

```bash
# In 003-init.sh
trap 'cleanup_and_error_handler' EXIT

cleanup_and_error_handler() {
  # Only run in main shell (not subshells)
  [[ $BASHPID != "$$" ]] && return
  
  # Secure delete passfile
  _ssh_session_cleanup
  
  # Kill QEMU if running
  [[ $QEMU_PID ]] && kill "$QEMU_PID" 2>/dev/null
  
  # Clean temp files
  for f in "${_TEMP_FILES[@]}"; do
    [[ -f $f ]] && rm -f "$f"
  done
}
```

## Input Validation

All user inputs are validated before use:

### SSH Keys

```bash
validate_ssh_key_secure() {
  # Verify OpenSSH format
  echo "$key" | ssh-keygen -l -f - >/dev/null 2>&1 || return 1
  
  # Check key strength
  case "$key_type" in
    ssh-ed25519) return 0 ;;  # Always secure
    ssh-rsa)
      [[ $bits -ge 2048 ]] || return 1  # Minimum 2048 bits
      ;;
    ecdsa-*)
      [[ $bits -ge 256 ]] || return 1   # Minimum ECDSA-256
      ;;
    *) return 1 ;;  # Reject unknown types (DSA, etc.)
  esac
}
```

### Tailscale Keys

```bash
validate_tailscale_key() {
  # Format: tskey-auth-<id>-<secret> or tskey-client-<id>-<secret>
  [[ $key =~ ^tskey-(auth|client)-[a-zA-Z0-9]+-[a-zA-Z0-9]+$ ]]
}
```

### Passwords

```bash
get_password_error() {
  [[ -z $password ]] && echo "Password cannot be empty!"
  [[ ${#password} -lt 8 ]] && echo "Password must be at least 8 characters"
  is_ascii_printable "$password" || echo "Invalid characters detected"
}
```

## Template Security

### Special Character Escaping

Template substitution escapes dangerous characters:

```bash
# In apply_template_vars:
value="${value//\\/\\\\}"    # Escape backslashes
value="${value//&/\\&}"      # Escape ampersands
value="${value//|/\\|}"      # Escape pipes
value="${value//$'\n'/\\$'\n'}"  # Escape newlines
```

This prevents:

- Shell injection via template values
- Sed command injection

### No eval with User Input

The codebase never uses `eval` with user-provided data:

```bash
# BAD - vulnerable to injection
eval "HOSTNAME=$user_input"

# GOOD - direct assignment
HOSTNAME="$user_input"
```

## Network Security

### SSH Options for QEMU

```bash
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
```

**Why this is safe:**

- Only used for local QEMU VM (localhost)
- VM is ephemeral (destroyed after installation)
- Not suitable for production remote servers

### Port Checking

```bash
check_port_available() {
  if ss -tuln | grep -q ":$port "; then
    return 1  # Port in use
  fi
}
```

## Credential Display

Credentials are only shown on the final completion screen:

```bash
# In 380-configure-finalize.sh
_show_completion_screen() {
  # Display to terminal only, not logged
  print_success "Root Password" "$NEW_ROOT_PASSWORD"
  print_success "Admin Password" "$ADMIN_PASSWORD"
}
```

**Never logged:**

```bash
# Logging function filters sensitive data
log() {
  # Passwords never passed to log function
  echo "[$(date)] $*" >> "$LOG_FILE"
}
```

## File Permissions

### Sensitive Files

```bash
chmod 600 "$passfile"  # Owner read/write only
chmod 600 "/etc/ssh/sshd_config"
chmod 700 "/root/.ssh"
chmod 600 "/root/.ssh/authorized_keys"
```

### Systemd Overrides

For services requiring credentials:

```bash
[Service]
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes
PrivateTmp=yes
```

## API Token Handling

Proxmox API tokens are:

1. Generated on the remote system
2. Captured via SSH
3. Displayed once on completion
4. Not stored locally

```bash
# Token generation on remote
pvesh create /access/users/admin@pve/token/automation --privsep 0

# Token captured and displayed, not saved
```

## Security Checklist

When adding new features:

- [ ] Never log passwords or tokens
- [ ] Use passfiles for SSH authentication
- [ ] Validate all user inputs
- [ ] Escape special characters in templates
- [ ] Set restrictive file permissions
- [ ] Clean up sensitive files on exit
- [ ] Use `/dev/urandom` for random generation
- [ ] Prefer `/dev/shm` for temp credential files
- [ ] Add to cleanup trap if creating temp files
- [ ] Never use `eval` with user data
