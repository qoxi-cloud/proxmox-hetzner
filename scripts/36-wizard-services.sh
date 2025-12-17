# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Services Settings Editors
# tailscale, ssl, shell, power_profile, features
# =============================================================================

_edit_tailscale() {
  _wiz_start_edit

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
      _wiz_input_screen "Enter Tailscale authentication key"

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
  _wiz_start_edit

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

  # Map display names to internal values
  local ssl_type=""
  case "$selected" in
    "Self-signed") ssl_type="self-signed" ;;
    "Let's Encrypt") ssl_type="letsencrypt" ;;
  esac

  # Validate Let's Encrypt selection
  if [[ $ssl_type == "letsencrypt" ]]; then
    # Check if FQDN is set and is a valid domain
    if [[ -z $FQDN ]]; then
      _wiz_start_edit
      gum style --foreground "$HEX_RED" "Error: Hostname not configured!"
      echo ""
      gum style --foreground "$HEX_GRAY" "Let's Encrypt requires a fully qualified domain name."
      gum style --foreground "$HEX_GRAY" "Please configure hostname first."
      sleep 3
      SSL_TYPE="self-signed"
      return
    fi

    if [[ $FQDN == *.local ]] || ! validate_fqdn "$FQDN"; then
      _wiz_start_edit
      gum style --foreground "$HEX_RED" "Error: Invalid domain name!"
      echo ""
      gum style --foreground "$HEX_GRAY" "Current hostname: ${CLR_ORANGE}${FQDN}${CLR_RESET}"
      gum style --foreground "$HEX_GRAY" "Let's Encrypt requires a valid public FQDN (e.g., pve.example.com)."
      gum style --foreground "$HEX_GRAY" "Domains ending with .local are not supported."
      sleep 3
      SSL_TYPE="self-signed"
      return
    fi

    # Check DNS resolution
    _wiz_start_edit
    gum style --foreground "$HEX_CYAN" "Validating DNS resolution..."
    echo ""
    gum style --foreground "$HEX_GRAY" "Domain: ${CLR_ORANGE}${FQDN}${CLR_RESET}"
    gum style --foreground "$HEX_GRAY" "Expected IP: ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
    echo ""

    local dns_result
    validate_dns_resolution "$FQDN" "$MAIN_IPV4"
    dns_result=$?

    if [[ $dns_result -eq 1 ]]; then
      # No DNS resolution
      gum style --foreground "$HEX_RED" "✗ Domain does not resolve to any IP address"
      echo ""
      gum style --foreground "$HEX_GRAY" "Please configure DNS A record:"
      gum style --foreground "$HEX_GRAY" "  ${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
      echo ""
      gum style --foreground "$HEX_GRAY" "Falling back to self-signed certificate."
      sleep 5
      SSL_TYPE="self-signed"
      return
    elif [[ $dns_result -eq 2 ]]; then
      # Wrong IP
      gum style --foreground "$HEX_RED" "✗ Domain resolves to wrong IP address"
      echo ""
      gum style --foreground "$HEX_GRAY" "Current DNS: ${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_RED}${DNS_RESOLVED_IP}${CLR_RESET}"
      gum style --foreground "$HEX_GRAY" "Expected:    ${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
      echo ""
      gum style --foreground "$HEX_GRAY" "Please update DNS A record to point to ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
      echo ""
      gum style --foreground "$HEX_GRAY" "Falling back to self-signed certificate."
      sleep 5
      SSL_TYPE="self-signed"
      return
    else
      # Success
      gum style --foreground "$HEX_CYAN" "✓ DNS resolution successful"
      gum style --foreground "$HEX_GRAY" "  ${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_CYAN}${DNS_RESOLVED_IP}${CLR_RESET}"
      sleep 3
      SSL_TYPE="$ssl_type"
    fi
  else
    [[ -n $ssl_type ]] && SSL_TYPE="$ssl_type"
  fi
}

_edit_shell() {
  _wiz_start_edit

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

  if [[ -n $selected ]]; then
    # Map display names to internal values
    case "$selected" in
      "ZSH") SHELL_TYPE="zsh" ;;
      "Bash") SHELL_TYPE="bash" ;;
    esac
  fi
}

_edit_power_profile() {
  _wiz_start_edit

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

  if [[ -n $selected ]]; then
    # Map display names to internal values
    case "$selected" in
      "Performance") CPU_GOVERNOR="performance" ;;
      "Balanced") CPU_GOVERNOR="ondemand" ;;
      "Power saving") CPU_GOVERNOR="powersave" ;;
      "Adaptive") CPU_GOVERNOR="schedutil" ;;
      "Conservative") CPU_GOVERNOR="conservative" ;;
    esac
  fi
}

_edit_features() {
  _wiz_start_edit

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

# =============================================================================
# API Token Editor
# =============================================================================

_edit_api_token() {
  _wiz_start_edit

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(echo -e "Disabled\nEnabled" | gum choose \
    --header="API Token (privileged, no expiration):" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  case "$selected" in
    Enabled)
      # Request token name
      _wiz_input_screen "Enter API token name (default: automation)"

      local token_name
      token_name=$(gum input \
        --placeholder "automation" \
        --prompt "Token name: " \
        --prompt.foreground "$HEX_CYAN" \
        --cursor.foreground "$HEX_ORANGE" \
        --width 40 \
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
      API_TOKEN_NAME="automation"
      ;;
  esac
}
