# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Services Settings Editors
# tailscale, ssl, shell, power_profile, features
# =============================================================================

# Edits Tailscale VPN configuration.
# Prompts for auth key if enabled, validates key format.
# Updates INSTALL_TAILSCALE, TAILSCALE_AUTH_KEY, SSL_TYPE, FIREWALL_MODE globals.
_edit_tailscale() {
  _wiz_start_edit

  _wiz_description \
    "  Tailscale VPN with stealth mode:" \
    "" \
    "  {{cyan:Enabled}}:  Access via Tailscale only (blocks public SSH)" \
    "  {{cyan:Disabled}}: Standard access via public IP" \
    "" \
    "  Stealth mode blocks ALL incoming traffic on public IP." \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_TOGGLE_OPTIONS" | _wiz_choose --header="Tailscale:"); then
    return
  fi

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

        # Ask about web access via Tailscale Serve
        _wiz_start_edit
        _wiz_description \
          "  Expose Proxmox Web UI via Tailscale Serve?" \
          "" \
          "  {{cyan:Enabled}}:  Access Web UI at https://<tailscale-hostname>" \
          "  {{cyan:Disabled}}: Web UI only via direct IP" \
          "" \
          "  Uses: tailscale serve --bg --https=443 https://127.0.0.1:8006" \
          ""

        _show_input_footer "filter" 3

        local webui_selected
        if webui_selected=$(printf '%s\n' "$WIZ_TOGGLE_OPTIONS" | _wiz_choose --header="Tailscale Web UI:"); then
          case "$webui_selected" in
            Enabled) TAILSCALE_WEBUI="yes" ;;
            Disabled) TAILSCALE_WEBUI="no" ;;
          esac
        else
          TAILSCALE_WEBUI="no" # Default to no on cancel
        fi

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
        TAILSCALE_WEBUI=""
        SSL_TYPE="" # Let user choose
      fi
      ;;
    Disabled)
      INSTALL_TAILSCALE="no"
      TAILSCALE_AUTH_KEY=""
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

# Edits SSL certificate type for Proxmox web interface.
# Validates FQDN and DNS resolution for Let's Encrypt.
# Updates SSL_TYPE global. Falls back to self-signed on validation failure.
_edit_ssl() {
  _wiz_start_edit

  _wiz_description \
    "  SSL certificate for Proxmox web interface:" \
    "" \
    "  {{cyan:Self-signed}}:   Works always, browser shows warning" \
    "  {{cyan:Let's Encrypt}}: Trusted cert, requires public DNS" \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_SSL_TYPES" | _wiz_choose --header="SSL Certificate:"); then
    return
  fi

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
    register_temp_file "$dns_result_file"

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

# Edits default shell for root user.
# Options: zsh (with Powerlevel10k) or bash.
# Updates SHELL_TYPE global.
_edit_shell() {
  _wiz_start_edit

  _wiz_description \
    "  Default shell for root user:" \
    "" \
    "  {{cyan:ZSH}}:  Modern shell with Powerlevel10k prompt" \
    "  {{cyan:Bash}}: Standard shell (minimal changes)" \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_SHELL_OPTIONS" | _wiz_choose --header="Shell:"); then
    return
  fi

  case "$selected" in
    "ZSH") SHELL_TYPE="zsh" ;;
    "Bash") SHELL_TYPE="bash" ;;
  esac
}

# Edits CPU frequency scaling governor.
# Dynamically detects available governors from sysfs.
# Updates CPU_GOVERNOR global.
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
    "  CPU frequency scaling governor:" \
    "" \
    "${descriptions[@]}" \
    ""

  # 1 header + N items for gum choose
  _show_input_footer "filter" $((${#options[@]} + 1))

  local options_str
  options_str=$(printf '%s\n' "${options[@]}")

  local selected
  if ! selected=$(printf '%s\n' "$options_str" | _wiz_choose --header="Power profile:"); then
    return
  fi

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
}

# =============================================================================
# Features - Security
# =============================================================================

# Edits security feature toggles via multi-select checkbox.
# Options: apparmor, auditd, aide, chkrootkit, lynis, needrestart.
# Updates corresponding INSTALL_* globals.
_edit_features_security() {
  _wiz_start_edit

  _wiz_description \
    "  Security features (use Space to toggle):" \
    "" \
    "  {{cyan:apparmor}}:    Mandatory access control (MAC)" \
    "  {{cyan:auditd}}:      Security audit logging" \
    "  {{cyan:aide}}:        File integrity monitoring (daily)" \
    "  {{cyan:chkrootkit}}:  Rootkit scanning (weekly)" \
    "  {{cyan:lynis}}:       Security auditing (weekly)" \
    "  {{cyan:needrestart}}: Auto-restart services after updates" \
    ""

  _show_input_footer "checkbox" 7

  local gum_args=(--header="Security:")
  [[ $INSTALL_APPARMOR == "yes" ]] && gum_args+=(--selected "apparmor")
  [[ $INSTALL_AUDITD == "yes" ]] && gum_args+=(--selected "auditd")
  [[ $INSTALL_AIDE == "yes" ]] && gum_args+=(--selected "aide")
  [[ $INSTALL_CHKROOTKIT == "yes" ]] && gum_args+=(--selected "chkrootkit")
  [[ $INSTALL_LYNIS == "yes" ]] && gum_args+=(--selected "lynis")
  [[ $INSTALL_NEEDRESTART == "yes" ]] && gum_args+=(--selected "needrestart")

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_FEATURES_SECURITY" | _wiz_choose_multi "${gum_args[@]}"); then
    return
  fi

  INSTALL_APPARMOR=$([[ $selected == *apparmor* ]] && echo "yes" || echo "no")
  INSTALL_AUDITD=$([[ $selected == *auditd* ]] && echo "yes" || echo "no")
  INSTALL_AIDE=$([[ $selected == *aide* ]] && echo "yes" || echo "no")
  INSTALL_CHKROOTKIT=$([[ $selected == *chkrootkit* ]] && echo "yes" || echo "no")
  INSTALL_LYNIS=$([[ $selected == *lynis* ]] && echo "yes" || echo "no")
  INSTALL_NEEDRESTART=$([[ $selected == *needrestart* ]] && echo "yes" || echo "no")
}

# =============================================================================
# Features - Monitoring
# =============================================================================

# Edits monitoring feature toggles via multi-select checkbox.
# Options: vnstat, netdata, promtail.
# Updates corresponding INSTALL_* globals.
_edit_features_monitoring() {
  _wiz_start_edit

  _wiz_description \
    "  Monitoring features (use Space to toggle):" \
    "" \
    "  {{cyan:vnstat}}:   Network traffic monitoring" \
    "  {{cyan:netdata}}:  Real-time monitoring (port 19999)" \
    "  {{cyan:promtail}}: Log collector for Loki" \
    ""

  _show_input_footer "checkbox" 4

  local gum_args=(--header="Monitoring:")
  [[ $INSTALL_VNSTAT == "yes" ]] && gum_args+=(--selected "vnstat")
  [[ $INSTALL_NETDATA == "yes" ]] && gum_args+=(--selected "netdata")
  [[ $INSTALL_PROMTAIL == "yes" ]] && gum_args+=(--selected "promtail")

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_FEATURES_MONITORING" | _wiz_choose_multi "${gum_args[@]}"); then
    return
  fi

  INSTALL_VNSTAT=$([[ $selected == *vnstat* ]] && echo "yes" || echo "no")
  INSTALL_NETDATA=$([[ $selected == *netdata* ]] && echo "yes" || echo "no")
  INSTALL_PROMTAIL=$([[ $selected == *promtail* ]] && echo "yes" || echo "no")
}

# =============================================================================
# Features - Tools
# =============================================================================

# Edits tools feature toggles via multi-select checkbox.
# Options: yazi (file manager), nvim (editor), ringbuffer (network tuning).
# Updates corresponding INSTALL_* globals.
_edit_features_tools() {
  _wiz_start_edit

  _wiz_description \
    "  Tools (use Space to toggle):" \
    "" \
    "  {{cyan:yazi}}:       Terminal file manager (Catppuccin theme)" \
    "  {{cyan:nvim}}:       Neovim as default editor" \
    "  {{cyan:ringbuffer}}: Network ring buffer tuning" \
    ""

  _show_input_footer "checkbox" 4

  local gum_args=(--header="Tools:")
  [[ $INSTALL_YAZI == "yes" ]] && gum_args+=(--selected "yazi")
  [[ $INSTALL_NVIM == "yes" ]] && gum_args+=(--selected "nvim")
  [[ $INSTALL_RINGBUFFER == "yes" ]] && gum_args+=(--selected "ringbuffer")

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_FEATURES_TOOLS" | _wiz_choose_multi "${gum_args[@]}"); then
    return
  fi

  INSTALL_YAZI=$([[ $selected == *yazi* ]] && echo "yes" || echo "no")
  INSTALL_NVIM=$([[ $selected == *nvim* ]] && echo "yes" || echo "no")
  INSTALL_RINGBUFFER=$([[ $selected == *ringbuffer* ]] && echo "yes" || echo "no")
}
