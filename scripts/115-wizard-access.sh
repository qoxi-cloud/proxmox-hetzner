# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Access Settings Editors
# Admin user, SSH key, API token
# =============================================================================

# Edits SSH public key for admin user access.
# Auto-detects key from Rescue System if available.
# Validates key format using ssh-keygen. Updates SSH_PUBLIC_KEY global.
_edit_ssh_key() {
  while true; do
    _wiz_start_edit

    # Detect SSH key from Rescue System
    local detected_key
    detected_key=$(get_rescue_ssh_key)

    # If key detected, show menu with auto-detect option
    if [[ -n $detected_key ]]; then
      # Parse detected key for display
      parse_ssh_key "$detected_key"

      _wiz_hide_cursor
      _wiz_warn "Detected SSH key from Rescue System:"
      _wiz_blank_line
      printf '%s\n' "${CLR_GRAY}Type:${CLR_RESET}    ${SSH_KEY_TYPE}"
      printf '%s\n' "${CLR_GRAY}Key:${CLR_RESET}     ${SSH_KEY_SHORT}"
      [[ -n $SSH_KEY_COMMENT ]] && printf '%s\n' "${CLR_GRAY}Comment:${CLR_RESET} ${SSH_KEY_COMMENT}"
      _wiz_blank_line

      # 1 header + 2 options
      _show_input_footer "filter" 3

      local choice
      choice=$(
        printf '%s\n' "$WIZ_SSH_KEY_OPTIONS" | _wiz_choose \
          --header="SSH Key:"
      )

      # If user cancelled (Esc)
      if [[ -z $choice ]]; then
        return
      fi

      case "$choice" in
        "Use detected key")
          SSH_PUBLIC_KEY="$detected_key"
          break
          ;;
        "Enter different key")
          # Fall through to manual entry below
          ;;
      esac
    fi

    # Manual entry
    _wiz_input_screen "Paste your SSH public key (ssh-rsa, ssh-ed25519, etc.)"

    local new_key
    new_key=$(
      _wiz_input \
        --placeholder "ssh-ed25519 AAAA... user@host" \
        --value "$SSH_PUBLIC_KEY" \
        --prompt "SSH Key: "
    )

    # If empty or cancelled, check if we had detected key
    if [[ -z $new_key ]]; then
      # If we had a detected key, return to menu
      if [[ -n $detected_key ]]; then
        continue
      else
        # No detected key, just return
        return
      fi
    fi

    # Validate the entered key (secure validation with ssh-keygen)
    if validate_ssh_key_secure "$new_key"; then
      SSH_PUBLIC_KEY="$new_key"
      break
    else
      show_validation_error "Invalid SSH key. Must be ED25519, RSA/ECDSA ≥2048 bits"
      # If we had a detected key, return to menu, otherwise retry manual entry
      if [[ -n $detected_key ]]; then
        continue
      fi
    fi
  done
}

# =============================================================================
# Admin User Editors
# =============================================================================

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
  while true; do
    _wiz_start_edit

    # 1 header + 2 options (Manual/Generate)
    _show_input_footer "filter" 3

    local choice
    choice=$(
      printf '%s\n' "$WIZ_PASSWORD_OPTIONS" | _wiz_choose \
        --header="Admin Password:"
    )

    # If user cancelled (Esc)
    if [[ -z $choice ]]; then
      return
    fi

    case "$choice" in
      "Generate password")
        ADMIN_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")

        _wiz_start_edit
        _wiz_hide_cursor
        _wiz_warn "Please save this password - it will be required for sudo and Proxmox UI"
        _wiz_blank_line
        printf '%s\n' "${CLR_CYAN}Generated admin password:${CLR_RESET} ${CLR_ORANGE}${ADMIN_PASSWORD}${CLR_RESET}"
        _wiz_blank_line
        printf '%s\n' "${CLR_GRAY}Press any key to continue...${CLR_RESET}"
        read -n 1 -s -r
        break
        ;;
      "Manual entry")
        _wiz_start_edit
        _show_input_footer

        local new_password
        new_password=$(
          _wiz_input \
            --password \
            --placeholder "Enter admin password" \
            --prompt "Admin Password: "
        )

        # If empty or cancelled, return to menu
        if [[ -z $new_password ]]; then
          continue
        fi

        # Validate password
        local password_error
        password_error=$(get_password_error "$new_password")
        if [[ -n $password_error ]]; then
          show_validation_error "$password_error"
          continue
        fi

        # Password is valid
        ADMIN_PASSWORD="$new_password"
        break
        ;;
    esac
  done
}

# =============================================================================
# API Token Editor
# =============================================================================

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

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_TOGGLE_OPTIONS" | _wiz_choose --header="API Token (privileged, no expiration):"); then
    return
  fi

  case "$selected" in
    Enabled)
      # Request token name
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
        INSTALL_API_TOKEN="yes"
      else
        # Invalid name - use default
        API_TOKEN_NAME="automation"
        INSTALL_API_TOKEN="yes"
      fi
      ;;
    Disabled)
      INSTALL_API_TOKEN="no"
      ;;
  esac
}
