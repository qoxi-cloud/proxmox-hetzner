# shellcheck shell=bash
# =============================================================================
# Configure non-root admin user
# Creates admin user with sudo privileges, deploys SSH key directly from wizard
# Grants Proxmox Administrator role and disables root@pam
# Root access is blocked for both SSH and Proxmox UI
# SSH key is NOT in answer.toml - it's deployed here directly to admin user
# =============================================================================

# Configuration function for admin user
_config_admin_user() {
  # Create user with home directory and bash shell, add to sudo group
  # shellcheck disable=SC2016
  remote_exec 'useradd -m -s /bin/bash -G sudo '"$ADMIN_USERNAME"'' || return 1

  # Set admin password
  # shellcheck disable=SC2016
  remote_exec 'echo '"${ADMIN_USERNAME}:${ADMIN_PASSWORD}"' | chpasswd' || return 1

  # Set up SSH directory for admin
  # shellcheck disable=SC2016
  remote_exec 'mkdir -p /home/$ADMIN_USERNAME/.ssh && chmod 700 /home/$ADMIN_USERNAME/.ssh' || return 1

  # Deploy SSH key directly to admin user (not copied from root - root has no SSH access)
  # Escape single quotes in the key for shell safety
  local escaped_key="${SSH_PUBLIC_KEY//\'/\'\\\'\'}"
  remote_exec "echo '${escaped_key}' > /home/${ADMIN_USERNAME}/.ssh/authorized_keys" || return 1

  # Set correct permissions and ownership
  # shellcheck disable=SC2016
  remote_exec 'chmod 600 /home/$ADMIN_USERNAME/.ssh/authorized_keys' || return 1
  # shellcheck disable=SC2016
  remote_exec 'chown -R $ADMIN_USERNAME:$ADMIN_USERNAME /home/$ADMIN_USERNAME/.ssh' || return 1

  # Configure passwordless sudo for admin
  # shellcheck disable=SC2016
  remote_exec 'echo '"$ADMIN_USERNAME"' ALL=(ALL) NOPASSWD:ALL > /etc/sudoers.d/'"$ADMIN_USERNAME"'' || return 1
  # shellcheck disable=SC2016
  remote_exec 'chmod 440 /etc/sudoers.d/'"$ADMIN_USERNAME"'' || return 1

  # Grant Proxmox UI access to admin user
  # Create PAM user in Proxmox (will auth against Linux PAM)
  # Using grep to check if user exists, avoiding || true which hides real errors
  remote_exec "pveum user list 2>/dev/null | grep -q '${ADMIN_USERNAME}@pam' || pveum user add ${ADMIN_USERNAME}@pam"

  # Grant Administrator role to admin user
  remote_exec "pveum acl modify / -user ${ADMIN_USERNAME}@pam -role Administrator" || {
    log "WARNING: Failed to grant Proxmox Administrator role"
  }

  # Disable root login in Proxmox UI (admin user is now the only way in)
  remote_exec "pveum user modify root@pam -enable 0" || {
    log "WARNING: Failed to disable root user in Proxmox UI"
  }
}

# Creates admin user with sudo privileges and deploys SSH key directly.
# Parameters: Uses global ADMIN_USERNAME, ADMIN_PASSWORD, SSH_PUBLIC_KEY
# Called before SSH hardening (which blocks root login)
# SSH key is deployed directly here, not via answer.toml
configure_admin_user() {
  log "Creating admin user: $ADMIN_USERNAME"
  if ! run_with_progress "Creating admin user" "Admin user created" _config_admin_user; then
    log "ERROR: Failed to create admin user"
    return 1
  fi
  log "Admin user ${ADMIN_USERNAME} created successfully"
  return 0
}
