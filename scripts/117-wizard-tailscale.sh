# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Tailscale Settings Editors
# =============================================================================

# Prompts for Tailscale auth key with validation.
# Returns: auth key via stdout, empty if cancelled
_tailscale_get_auth_key() {
  _wiz_input_validated "validate_tailscale_key" "Invalid key format. Expected: tskey-auth-xxx-xxx" \
    --placeholder "tskey-auth-..." \
    --prompt "Auth Key: "
}

# Prompts for Tailscale Web UI (Serve) configuration.
# Side effects: Sets TAILSCALE_WEBUI global
_tailscale_configure_webui() {
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

  _wiz_toggle "TAILSCALE_WEBUI" "Tailscale Web UI:" "no"
}

# Enables Tailscale with auth key and configures related settings.
# Parameters: $1 - auth key
# Side effects: Sets INSTALL_TAILSCALE, TAILSCALE_AUTH_KEY, SSL_TYPE, FIREWALL_MODE
_tailscale_enable() {
  local auth_key="$1"

  INSTALL_TAILSCALE="yes"
  TAILSCALE_AUTH_KEY="$auth_key"

  _tailscale_configure_webui

  SSL_TYPE="self-signed"
  if [[ -z $INSTALL_FIREWALL ]]; then
    INSTALL_FIREWALL="yes"
    FIREWALL_MODE="stealth"
  fi
}

# Disables Tailscale and clears related settings.
# Side effects: Clears INSTALL_TAILSCALE, TAILSCALE_AUTH_KEY, TAILSCALE_WEBUI, SSL_TYPE
_tailscale_disable() {
  INSTALL_TAILSCALE="no"
  TAILSCALE_AUTH_KEY=""
  TAILSCALE_WEBUI=""
  SSL_TYPE=""
  if [[ -z $INSTALL_FIREWALL ]]; then
    INSTALL_FIREWALL="yes"
    FIREWALL_MODE="standard"
  fi
}

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

  _show_input_footer "filter" 3

  local result
  _wiz_toggle "INSTALL_TAILSCALE" "Tailscale:"
  result=$?

  if [[ $result -eq 1 ]]; then
    return
  elif [[ $result -eq 2 ]]; then
    # Enabled - get auth key
    local auth_key
    auth_key=$(_tailscale_get_auth_key)
    if [[ -n $auth_key ]]; then
      _tailscale_enable "$auth_key"
    else
      _tailscale_disable
    fi
  else
    _tailscale_disable
  fi
}
