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
    printf '%s\n' "$WIZ_TOGGLE_OPTIONS" | _wiz_choose \
      --header="Tailscale:"
  )

  case "$selected" in
    Enabled)
      # Request auth key with validation loop
      local auth_key=""

      while true; do
        _wiz_start_edit
        _show_input_footer

        auth_key=$(
          _wiz_input \
            --placeholder "tskey-auth-..." \
            --prompt "Auth Key: "
        )

        # Empty = cancel
        [[ -z $auth_key ]] && break

        # Validate key format
        if validate_tailscale_key "$auth_key"; then
          break
        fi

        show_validation_error "Invalid key format. Expected: tskey-auth-xxx-xxx"
      done

      # If valid auth key provided, enable Tailscale
      if [[ -n $auth_key ]]; then
        INSTALL_TAILSCALE="yes"
        TAILSCALE_AUTH_KEY="$auth_key"
        TAILSCALE_SSH="yes"
        TAILSCALE_WEBUI="yes"
        SSL_TYPE="self-signed" # Tailscale uses its own certs
        # Suggest stealth firewall mode when Tailscale is enabled
        if [[ -z $INSTALL_FIREWALL ]]; then
          INSTALL_FIREWALL="yes"
          FIREWALL_MODE="stealth"
        fi
      else
        # Auth key required - disable Tailscale if not provided
        INSTALL_TAILSCALE="no"
        TAILSCALE_AUTH_KEY=""
        TAILSCALE_SSH=""
        TAILSCALE_WEBUI=""
        SSL_TYPE="" # Let user choose
      fi
      ;;
    Disabled)
      INSTALL_TAILSCALE="no"
      TAILSCALE_AUTH_KEY=""
      TAILSCALE_SSH=""
      TAILSCALE_WEBUI=""
      SSL_TYPE="" # Let user choose
      # Suggest standard firewall when Tailscale is disabled
      if [[ -z $INSTALL_FIREWALL ]]; then
        INSTALL_FIREWALL="yes"
        FIREWALL_MODE="standard"
      fi
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
    printf '%s\n' "$WIZ_SSL_TYPES" | _wiz_choose \
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
      printf '%s\n' "$?" >"$dns_result_file"
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

  _wiz_description \
    "Default shell for root user:" \
    "" \
    "  {{cyan:ZSH}}:  Modern shell with Powerlevel10k prompt" \
    "  {{cyan:Bash}}: Standard shell (minimal changes)" \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(
    printf '%s\n' "$WIZ_SHELL_OPTIONS" | _wiz_choose \
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

  # Detect available governors from sysfs
  local avail_governors=""
  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]]; then
    avail_governors=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
  fi

  # Build dynamic options based on available governors
  local options=()
  local descriptions=()

  # Always show Performance if available
  if [[ -z $avail_governors ]] || printf '%s\n' "$avail_governors" | grep -qw "performance"; then
    options+=("Performance")
    descriptions+=("  {{cyan:Performance}}:  Max frequency (highest power)")
  fi

  # Show governor-specific options
  if printf '%s\n' "$avail_governors" | grep -qw "ondemand"; then
    options+=("Balanced")
    descriptions+=("  {{cyan:Balanced}}:     Scale based on load")
  elif printf '%s\n' "$avail_governors" | grep -qw "powersave"; then
    # intel_pstate powersave is actually dynamic scaling
    options+=("Balanced")
    descriptions+=("  {{cyan:Balanced}}:     Dynamic scaling (power efficient)")
  fi

  if printf '%s\n' "$avail_governors" | grep -qw "schedutil"; then
    options+=("Adaptive")
    descriptions+=("  {{cyan:Adaptive}}:     Kernel-managed scaling")
  fi

  if printf '%s\n' "$avail_governors" | grep -qw "conservative"; then
    options+=("Conservative")
    descriptions+=("  {{cyan:Conservative}}: Gradual frequency changes")
  fi

  # Fallback if no governors detected
  if [[ ${#options[@]} -eq 0 ]]; then
    options=("Performance" "Balanced")
    descriptions=(
      "  {{cyan:Performance}}:  Max frequency (highest power)"
      "  {{cyan:Balanced}}:     Dynamic scaling (power efficient)"
    )
  fi

  _wiz_description \
    "CPU frequency scaling governor:" \
    "" \
    "${descriptions[@]}" \
    ""

  # 1 header + N items for gum choose
  _show_input_footer "filter" $((${#options[@]} + 1))

  local options_str
  options_str=$(printf '%s\n' "${options[@]}")

  local selected
  selected=$(
    printf '%s\n' "$options_str" | _wiz_choose \
      --header="Power profile:"
  )

  if [[ -n $selected ]]; then
    # Map display names to governor values
    case "$selected" in
      "Performance") CPU_GOVERNOR="performance" ;;
      "Balanced")
        # Use ondemand if available, otherwise powersave
        if printf '%s\n' "$avail_governors" | grep -qw "ondemand"; then
          CPU_GOVERNOR="ondemand"
        else
          CPU_GOVERNOR="powersave"
        fi
        ;;
      "Adaptive") CPU_GOVERNOR="schedutil" ;;
      "Conservative") CPU_GOVERNOR="conservative" ;;
    esac
  fi
}

# =============================================================================
# Features - Security
# =============================================================================

_edit_features_security() {
  _wiz_start_edit

  _wiz_description \
    "Security features (use Space to toggle):" \
    "" \
    "  {{cyan:apparmor}}:    Mandatory access control (MAC)" \
    "  {{cyan:auditd}}:      Security audit logging" \
    "  {{cyan:aide}}:        File integrity monitoring (daily)" \
    "  {{cyan:chkrootkit}}:  Rootkit scanning (weekly)" \
    "  {{cyan:lynis}}:       Security auditing (weekly)" \
    "  {{cyan:needrestart}}: Auto-restart services after updates" \
    ""

  _show_input_footer "checkbox" 7

  local preselected=()
  [[ $INSTALL_APPARMOR == "yes" ]] && preselected+=("apparmor")
  [[ $INSTALL_AUDITD == "yes" ]] && preselected+=("auditd")
  [[ $INSTALL_AIDE == "yes" ]] && preselected+=("aide")
  [[ $INSTALL_CHKROOTKIT == "yes" ]] && preselected+=("chkrootkit")
  [[ $INSTALL_LYNIS == "yes" ]] && preselected+=("lynis")
  [[ $INSTALL_NEEDRESTART == "yes" ]] && preselected+=("needrestart")

  local gum_args=(
    --no-limit
    --header="Security:"
    --header.foreground "$HEX_CYAN"
    --cursor "${CLR_ORANGE}›${CLR_RESET} "
    --cursor.foreground "$HEX_NONE"
    --cursor-prefix "◦ "
    --selected.foreground "$HEX_WHITE"
    --selected-prefix "${CLR_CYAN}✓${CLR_RESET} "
    --unselected-prefix "◦ "
    --no-show-help
  )

  for item in "${preselected[@]}"; do
    gum_args+=(--selected "$item")
  done

  local selected
  selected=$(printf '%s\n' apparmor auditd aide chkrootkit lynis needrestart | _wiz_choose "${gum_args[@]}")

  INSTALL_APPARMOR="no"
  INSTALL_AUDITD="no"
  INSTALL_AIDE="no"
  INSTALL_CHKROOTKIT="no"
  INSTALL_LYNIS="no"
  INSTALL_NEEDRESTART="no"

  [[ $selected == *apparmor* ]] && INSTALL_APPARMOR="yes"
  [[ $selected == *auditd* ]] && INSTALL_AUDITD="yes"
  [[ $selected == *aide* ]] && INSTALL_AIDE="yes"
  [[ $selected == *chkrootkit* ]] && INSTALL_CHKROOTKIT="yes"
  [[ $selected == *lynis* ]] && INSTALL_LYNIS="yes"
  [[ $selected == *needrestart* ]] && INSTALL_NEEDRESTART="yes"
}

# =============================================================================
# Features - Monitoring
# =============================================================================

_edit_features_monitoring() {
  _wiz_start_edit

  _wiz_description \
    "Monitoring features (use Space to toggle):" \
    "" \
    "  {{cyan:vnstat}}:   Network traffic monitoring" \
    "  {{cyan:netdata}}:  Real-time monitoring (port 19999)" \
    "  {{cyan:promtail}}: Log collector for Loki" \
    ""

  _show_input_footer "checkbox" 4

  local preselected=()
  [[ $INSTALL_VNSTAT == "yes" ]] && preselected+=("vnstat")
  [[ $INSTALL_NETDATA == "yes" ]] && preselected+=("netdata")
  [[ $INSTALL_PROMTAIL == "yes" ]] && preselected+=("promtail")

  local gum_args=(
    --no-limit
    --header="Monitoring:"
    --header.foreground "$HEX_CYAN"
    --cursor "${CLR_ORANGE}›${CLR_RESET} "
    --cursor.foreground "$HEX_NONE"
    --cursor-prefix "◦ "
    --selected.foreground "$HEX_WHITE"
    --selected-prefix "${CLR_CYAN}✓${CLR_RESET} "
    --unselected-prefix "◦ "
    --no-show-help
  )

  for item in "${preselected[@]}"; do
    gum_args+=(--selected "$item")
  done

  local selected
  selected=$(printf '%s\n' vnstat netdata promtail | _wiz_choose "${gum_args[@]}")

  INSTALL_VNSTAT="no"
  INSTALL_NETDATA="no"
  INSTALL_PROMTAIL="no"

  [[ $selected == *vnstat* ]] && INSTALL_VNSTAT="yes"
  [[ $selected == *netdata* ]] && INSTALL_NETDATA="yes"
  [[ $selected == *promtail* ]] && INSTALL_PROMTAIL="yes"
}

# =============================================================================
# Features - Tools
# =============================================================================

_edit_features_tools() {
  _wiz_start_edit

  _wiz_description \
    "Tools (use Space to toggle):" \
    "" \
    "  {{cyan:yazi}}:       Terminal file manager (Catppuccin theme)" \
    "  {{cyan:nvim}}:       Neovim as default editor" \
    "  {{cyan:ringbuffer}}: Network ring buffer tuning" \
    ""

  _show_input_footer "checkbox" 4

  local preselected=()
  [[ $INSTALL_YAZI == "yes" ]] && preselected+=("yazi")
  [[ $INSTALL_NVIM == "yes" ]] && preselected+=("nvim")
  [[ $INSTALL_RINGBUFFER == "yes" ]] && preselected+=("ringbuffer")

  local gum_args=(
    --no-limit
    --header="Tools:"
    --header.foreground "$HEX_CYAN"
    --cursor "${CLR_ORANGE}›${CLR_RESET} "
    --cursor.foreground "$HEX_NONE"
    --cursor-prefix "◦ "
    --selected.foreground "$HEX_WHITE"
    --selected-prefix "${CLR_CYAN}✓${CLR_RESET} "
    --unselected-prefix "◦ "
    --no-show-help
  )

  for item in "${preselected[@]}"; do
    gum_args+=(--selected "$item")
  done

  local selected
  selected=$(printf '%s\n' yazi nvim ringbuffer | _wiz_choose "${gum_args[@]}")

  INSTALL_YAZI="no"
  INSTALL_NVIM="no"
  INSTALL_RINGBUFFER="no"

  [[ $selected == *yazi* ]] && INSTALL_YAZI="yes"
  [[ $selected == *nvim* ]] && INSTALL_NVIM="yes"
  [[ $selected == *ringbuffer* ]] && INSTALL_RINGBUFFER="yes"
}

# =============================================================================
# API Token Editor
# =============================================================================

_edit_api_token() {
  _wiz_start_edit

  _wiz_description \
    "Proxmox API token for automation:" \
    "" \
    "  {{cyan:Enabled}}:  Create privileged token (Terraform, Ansible)" \
    "  {{cyan:Disabled}}: No API token" \
    "" \
    "  Token has full root@pam permissions, no expiration." \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  selected=$(
    printf '%s\n' "$WIZ_TOGGLE_OPTIONS" | _wiz_choose \
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
