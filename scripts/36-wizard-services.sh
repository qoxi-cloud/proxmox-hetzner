# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Services Settings Editors
# tailscale, ssl, shell, power_profile, features
# =============================================================================

_edit_tailscale() {
  clear
  show_banner
  echo ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(echo -e "Disabled\nEnabled" | gum choose \
    --header="Tailscale:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  case "$selected" in
    Enabled)
      # Request auth key (required for Tailscale)
      clear
      show_banner
      echo ""
      gum style --foreground "$HEX_GRAY" "Enter Tailscale authentication key"
      echo ""
      _show_input_footer

      local auth_key
      auth_key=$(gum input \
        --placeholder "tskey-auth-..." \
        --prompt "Auth Key: " \
        --prompt.foreground "$HEX_CYAN" \
        --cursor.foreground "$HEX_ORANGE" \
        --width 60 \
        --no-show-help)

      # If auth key provided, enable Tailscale with stealth mode
      if [[ -n $auth_key ]]; then
        INSTALL_TAILSCALE="yes"
        TAILSCALE_AUTH_KEY="$auth_key"
        TAILSCALE_SSH="yes"
        TAILSCALE_WEBUI="yes"
        TAILSCALE_DISABLE_SSH="yes"
        STEALTH_MODE="yes"
        SSL_TYPE="self-signed" # Tailscale uses its own certs
      else
        # Auth key required - disable Tailscale if not provided
        INSTALL_TAILSCALE="no"
        TAILSCALE_AUTH_KEY=""
        TAILSCALE_SSH=""
        TAILSCALE_WEBUI=""
        TAILSCALE_DISABLE_SSH=""
        STEALTH_MODE=""
        SSL_TYPE="" # Let user choose
      fi
      ;;
    Disabled)
      INSTALL_TAILSCALE="no"
      TAILSCALE_AUTH_KEY=""
      TAILSCALE_SSH=""
      TAILSCALE_WEBUI=""
      TAILSCALE_DISABLE_SSH=""
      STEALTH_MODE=""
      SSL_TYPE="" # Let user choose
      ;;
  esac
}

_edit_ssl() {
  clear
  show_banner
  echo ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(echo "$WIZ_SSL_TYPES" | gum choose \
    --header="SSL Certificate:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && SSL_TYPE="$selected"
}

_edit_shell() {
  clear
  show_banner
  echo ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(echo "$WIZ_SHELL_OPTIONS" | gum choose \
    --header="Shell:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && SHELL_TYPE="$selected"
}

_edit_power_profile() {
  clear
  show_banner
  echo ""

  # 1 header + 5 items for gum choose
  _show_input_footer "filter" 6

  local selected
  selected=$(echo "$WIZ_CPU_GOVERNORS" | gum choose \
    --header="Power profile:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && CPU_GOVERNOR="$selected"
}

_edit_features() {
  clear
  show_banner
  echo ""

  # 1 header + 4 items for multi-select checkbox
  _show_input_footer "checkbox" 5

  # Build pre-selected items based on current configuration
  local preselected=()
  [[ $INSTALL_VNSTAT == "yes" ]] && preselected+=("vnstat")
  [[ $INSTALL_AUDITD == "yes" ]] && preselected+=("auditd")
  [[ $INSTALL_YAZI == "yes" ]] && preselected+=("yazi")
  [[ $INSTALL_NVIM == "yes" ]] && preselected+=("nvim")

  # Use gum choose with --no-limit for multi-select
  local selected
  local gum_args=(
    --no-limit
    --header="Features:"
    --header.foreground "$HEX_CYAN"
    --cursor "${CLR_ORANGE}›${CLR_RESET} "
    --cursor.foreground "$HEX_NONE"
    --cursor-prefix "◦ "
    --selected.foreground "$HEX_WHITE"
    --selected-prefix "${CLR_CYAN}✓${CLR_RESET} "
    --unselected-prefix "◦ "
    --no-show-help
  )

  # Add preselected items if any
  for item in "${preselected[@]}"; do
    gum_args+=(--selected "$item")
  done

  selected=$(echo "$WIZ_OPTIONAL_FEATURES" | gum choose "${gum_args[@]}")

  # Parse selection
  INSTALL_VNSTAT="no"
  INSTALL_AUDITD="no"
  INSTALL_YAZI="no"
  INSTALL_NVIM="no"
  if echo "$selected" | grep -q "vnstat"; then
    INSTALL_VNSTAT="yes"
  fi
  if echo "$selected" | grep -q "auditd"; then
    INSTALL_AUDITD="yes"
  fi
  if echo "$selected" | grep -q "yazi"; then
    INSTALL_YAZI="yes"
  fi
  if echo "$selected" | grep -q "nvim"; then
    INSTALL_NVIM="yes"
  fi
}
