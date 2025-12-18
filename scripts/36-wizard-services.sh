# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Services Settings Editors
# tailscale, ssl, shell, power_profile, features
# =============================================================================

_edit_tailscale() {
  _wiz_start_edit

  _wiz_description \
    "Tailscale VPN with stealth mode:" \
    "" \
    "  {{cyan:Enabled}}:  Access via Tailscale only (blocks public SSH)" \
    "  {{cyan:Disabled}}: Standard access via public IP" \
    "" \
    "  Stealth mode blocks ALL incoming traffic on public IP." \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(
    echo -e "Disabled\nEnabled" | _wiz_choose \
      --header="Tailscale:"
  )

  case "$selected" in
    Enabled)
      # Request auth key (required for Tailscale)
      _wiz_input_screen "Enter Tailscale authentication key"

      local auth_key
      auth_key=$(
        _wiz_input \
          --placeholder "tskey-auth-..." \
          --prompt "Auth Key: "
      )

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

  _wiz_description \
    "SSL certificate for Proxmox web interface:" \
    "" \
    "  {{cyan:Self-signed}}:   Works always, browser shows warning" \
    "  {{cyan:Let's Encrypt}}: Trusted cert, requires public DNS" \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(
    echo "$WIZ_SSL_TYPES" | _wiz_choose \
      --header="SSL Certificate:"
  )

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
      _wiz_hide_cursor
      _wiz_error "Error: Hostname not configured!"
      _wiz_blank_line
      _wiz_dim "Let's Encrypt requires a fully qualified domain name."
      _wiz_dim "Please configure hostname first."
      sleep 3
      SSL_TYPE="self-signed"
      return
    fi

    if [[ $FQDN == *.local ]] || ! validate_fqdn "$FQDN"; then
      _wiz_start_edit
      _wiz_hide_cursor
      _wiz_error "Error: Invalid domain name!"
      _wiz_blank_line
      _wiz_dim "Current hostname: ${CLR_ORANGE}${FQDN}${CLR_RESET}"
      _wiz_dim "Let's Encrypt requires a valid public FQDN (e.g., pve.example.com)."
      _wiz_dim "Domains ending with .local are not supported."
      sleep 3
      SSL_TYPE="self-signed"
      return
    fi

    # Check DNS resolution
    _wiz_start_edit
    _wiz_hide_cursor
    _wiz_blank_line
    _wiz_dim "Domain: ${CLR_ORANGE}${FQDN}${CLR_RESET}"
    _wiz_dim "Expected IP: ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
    _wiz_blank_line

    # Run DNS validation in background with animated dots
    local dns_result_file
    dns_result_file=$(mktemp)

    (
      validate_dns_resolution "$FQDN" "$MAIN_IPV4"
      echo $? >"$dns_result_file"
    ) >/dev/null 2>&1 &

    local dns_pid=$!

    # Show animated dots while validating (like live logs)
    printf "%s" "${CLR_CYAN}Validating DNS resolution${CLR_RESET}"
    while kill -0 "$dns_pid" 2>/dev/null; do
      sleep 0.3
      local dots_count=$((($(date +%s) % 3) + 1))
      local dots
      dots=$(printf '.%.0s' $(seq 1 $dots_count))
      # Update line with animated dots (up to 3)
      printf "\r%sValidating DNS resolution%s%-3s%s" "${CLR_CYAN}" "${CLR_ORANGE}" "$dots" "${CLR_RESET}"
    done

    wait "$dns_pid" 2>/dev/null
    local dns_result
    dns_result=$(cat "$dns_result_file")
    rm -f "$dns_result_file"

    # Clear the line
    printf "\r%-80s\r" " "

    if [[ $dns_result -eq 1 ]]; then
      # No DNS resolution
      _wiz_hide_cursor
      _wiz_error "✗ Domain does not resolve to any IP address"
      _wiz_blank_line
      _wiz_dim "Please configure DNS A record:"
      _wiz_dim "  ${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
      _wiz_blank_line
      _wiz_dim "Falling back to self-signed certificate."
      sleep 5
      SSL_TYPE="self-signed"
      return
    elif [[ $dns_result -eq 2 ]]; then
      # Wrong IP
      _wiz_hide_cursor
      _wiz_error "✗ Domain resolves to wrong IP address"
      _wiz_blank_line
      _wiz_dim "Current DNS: ${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_RED}${DNS_RESOLVED_IP}${CLR_RESET}"
      _wiz_dim "Expected:    ${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
      _wiz_blank_line
      _wiz_dim "Please update DNS A record to point to ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
      _wiz_blank_line
      _wiz_dim "Falling back to self-signed certificate."
      sleep 5
      SSL_TYPE="self-signed"
      return
    else
      # Success
      _wiz_info "✓ DNS resolution successful"
      _wiz_dim "  ${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_CYAN}${DNS_RESOLVED_IP}${CLR_RESET}"
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
  selected=$(
    echo "$WIZ_SHELL_OPTIONS" | _wiz_choose \
      --header="Shell:"
  )

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

  _wiz_description \
    "CPU frequency scaling governor:" \
    "" \
    "  {{cyan:Performance}}:  Max frequency always (highest power)" \
    "  {{cyan:Balanced}}:     Scale based on load (ondemand)" \
    "  {{cyan:Adaptive}}:     Kernel-managed scaling (schedutil)" \
    "  {{cyan:Power saving}}: Prefer low frequency (powersave)" \
    "  {{cyan:Conservative}}: Gradual frequency changes" \
    ""

  # 1 header + 5 items for gum choose
  _show_input_footer "filter" 6

  local selected
  selected=$(
    echo "$WIZ_CPU_GOVERNORS" | _wiz_choose \
      --header="Power profile:"
  )

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

  _wiz_description \
    "Optional features (use Space to toggle):" \
    "" \
    "  {{cyan:vnstat}}:     Network traffic monitoring" \
    "  {{cyan:apparmor}}:   Mandatory access control (MAC)" \
    "  {{cyan:auditd}}:     Security audit logging" \
    "  {{cyan:aide}}:       File integrity monitoring" \
    "  {{cyan:chkrootkit}}: Weekly rootkit scanning" \
    "  {{cyan:prometheus}}: Node exporter for metrics (port 9100)" \
    "  {{cyan:yazi}}:       Terminal file manager" \
    "  {{cyan:nvim}}:       Neovim as default editor" \
    ""

  # 1 header + 8 items for multi-select checkbox
  _show_input_footer "checkbox" 9

  # Build pre-selected items based on current configuration
  local preselected=()
  [[ $INSTALL_VNSTAT == "yes" ]] && preselected+=("vnstat")
  [[ $INSTALL_APPARMOR == "yes" ]] && preselected+=("apparmor")
  [[ $INSTALL_AUDITD == "yes" ]] && preselected+=("auditd")
  [[ $INSTALL_AIDE == "yes" ]] && preselected+=("aide")
  [[ $INSTALL_CHKROOTKIT == "yes" ]] && preselected+=("chkrootkit")
  [[ $INSTALL_PROMETHEUS == "yes" ]] && preselected+=("prometheus")
  [[ $INSTALL_YAZI == "yes" ]] && preselected+=("yazi")
  [[ $INSTALL_NVIM == "yes" ]] && preselected+=("nvim")

  # Use _wiz_choose with --no-limit for multi-select
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

  selected=$(echo "$WIZ_OPTIONAL_FEATURES" | _wiz_choose "${gum_args[@]}")

  # Parse selection
  INSTALL_VNSTAT="no"
  INSTALL_APPARMOR="no"
  INSTALL_AUDITD="no"
  INSTALL_AIDE="no"
  INSTALL_CHKROOTKIT="no"
  INSTALL_PROMETHEUS="no"
  INSTALL_YAZI="no"
  INSTALL_NVIM="no"
  if echo "$selected" | grep -q "vnstat"; then
    INSTALL_VNSTAT="yes"
  fi
  if echo "$selected" | grep -q "apparmor"; then
    INSTALL_APPARMOR="yes"
  fi
  if echo "$selected" | grep -q "auditd"; then
    INSTALL_AUDITD="yes"
  fi
  if echo "$selected" | grep -q "aide"; then
    INSTALL_AIDE="yes"
  fi
  if echo "$selected" | grep -q "chkrootkit"; then
    INSTALL_CHKROOTKIT="yes"
  fi
  if echo "$selected" | grep -q "prometheus"; then
    INSTALL_PROMETHEUS="yes"
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
  selected=$(
    echo -e "Disabled\nEnabled" | _wiz_choose \
      --header="API Token (privileged, no expiration):"
  )

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
      API_TOKEN_NAME="automation"
      ;;
  esac
}
