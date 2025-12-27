# shellcheck shell=bash
# Configuration Wizard - Admin User & API Token Editors

# Edits non-root admin username for SSH and Proxmox access.
# Validates username format (lowercase, no reserved names).
# Updates ADMIN_USERNAME global.
_edit_admin_username() {
  while true; do
    _wiz_start_edit

    _wiz_description \
      "  Non-root admin username for SSH and Proxmox access:" \
      "" \
      "  Root SSH login will be {{cyan:completely disabled}}." \
      "  All SSH access must use this admin account." \
      "  The admin user will have sudo privileges." \
      ""

    _show_input_footer

    local new_username
    new_username=$(
      _wiz_input \
        --placeholder "e.g., sysadmin, deploy, operator" \
        --value "$ADMIN_USERNAME" \
        --prompt "Admin username: "
    )

    # If empty (cancelled), return to menu
    if [[ -z $new_username ]]; then
      return
    fi

    # Validate username
    if validate_admin_username "$new_username"; then
      ADMIN_USERNAME="$new_username"
      break
    else
      show_validation_error "Invalid username. Use lowercase letters/numbers, 1-32 chars. Reserved names (root, admin) not allowed."
    fi
  done
}

# Edits admin password via manual entry or generation.
# Shows generated password for user to save.
# Updates ADMIN_PASSWORD global.
_edit_admin_password() {
  _wiz_password_editor \
    "ADMIN_PASSWORD" \
    "Admin Password:" \
    "it will be required for sudo and Proxmox UI" \
    "Generated admin password:"
}

# API Token Editor

# Edits Proxmox API token creation settings.
# Prompts for token name if enabled (default: automation).
# Updates INSTALL_API_TOKEN and API_TOKEN_NAME globals.
_edit_api_token() {
  _wiz_start_edit

  _wiz_description \
    "  Proxmox API token for automation:" \
    "" \
    "  {{cyan:Enabled}}:  Create privileged token (Terraform, Ansible)" \
    "  {{cyan:Disabled}}: No API token" \
    "" \
    "  Token has full Administrator permissions, no expiration." \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local result
  _wiz_toggle "INSTALL_API_TOKEN" "API Token (privileged, no expiration):"
  result=$?

  [[ $result -eq 1 ]] && return
  [[ $result -ne 2 ]] && return

  # Enabled - request token name
  _wiz_input_screen "Enter API token name (default: automation)"

  local token_name
  token_name=$(_wiz_input \
    --placeholder "automation" \
    --prompt "Token name: " \
    --no-show-help \
    --value="${API_TOKEN_NAME:-automation}")

  # Validate: alphanumeric, dash, underscore only
  if [[ -n $token_name && $token_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
    API_TOKEN_NAME="$token_name"
  else
    API_TOKEN_NAME="automation"
  fi
}
