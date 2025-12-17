# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - SSH Key Editor
# ssh_key
# =============================================================================

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

      _wiz_warn "Detected SSH key from Rescue System:"
      _wiz_blank_line
      echo -e "${CLR_GRAY}Type:${CLR_RESET}    ${SSH_KEY_TYPE}"
      echo -e "${CLR_GRAY}Key:${CLR_RESET}     ${SSH_KEY_SHORT}"
      [[ -n $SSH_KEY_COMMENT ]] && echo -e "${CLR_GRAY}Comment:${CLR_RESET} ${SSH_KEY_COMMENT}"
      _wiz_blank_line

      # 1 header + 2 options
      _show_input_footer "filter" 3

      local choice
      choice=$(
        echo -e "Use detected key\nEnter different key" | _wiz_choose \
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
        --prompt "SSH Key: " \  --width 60
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

    # Validate the entered key
    if validate_ssh_key "$new_key"; then
      SSH_PUBLIC_KEY="$new_key"
      break
    else
      show_validation_error "Invalid SSH key format"
      # If we had a detected key, return to menu, otherwise retry manual entry
      if [[ -n $detected_key ]]; then
        continue
      fi
    fi
  done
}
