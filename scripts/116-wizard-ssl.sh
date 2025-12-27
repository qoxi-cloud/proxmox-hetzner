# shellcheck shell=bash
# Configuration Wizard - SSL Settings Editors

# Validate FQDN for Let's Encrypt. Returns 0=valid, 1=missing, 2=invalid
_ssl_validate_fqdn() {
  if [[ -z $FQDN ]]; then
    _wiz_start_edit
    _wiz_hide_cursor
    _wiz_description \
      "  {{red:✗ Hostname not configured!}}" \
      "" \
      "  Let's Encrypt requires a fully qualified domain name." \
      "  Please configure hostname first."
    sleep "${WIZARD_MESSAGE_DELAY:-3}"
    return 1
  fi

  if [[ $FQDN == *.local ]] || ! validate_fqdn "$FQDN"; then
    _wiz_start_edit
    _wiz_hide_cursor
    _wiz_description \
      "  {{red:✗ Invalid domain name!}}" \
      "" \
      "  Current hostname: {{orange:${FQDN}}}" \
      "  Let's Encrypt requires a valid public FQDN (e.g., pve.example.com)." \
      "  Domains ending with .local are not supported."
    sleep "${WIZARD_MESSAGE_DELAY:-3}"
    return 2
  fi

  return 0
}

# Run DNS validation with progress. Returns 0=ok, 1=no resolve, 2=wrong IP
_ssl_check_dns_animated() {
  _wiz_start_edit
  _wiz_hide_cursor
  _wiz_blank_line
  _wiz_dim "Domain: ${CLR_ORANGE}${FQDN}${CLR_RESET}"
  _wiz_dim "Expected IP: ${CLR_ORANGE}${MAIN_IPV4}${CLR_RESET}"
  _wiz_blank_line

  local dns_result_file
  dns_result_file=$(mktemp)
  register_temp_file "$dns_result_file"

  (
    validate_dns_resolution "$FQDN" "$MAIN_IPV4"
    printf '%s\n' "$?" >"$dns_result_file"
  ) >/dev/null 2>&1 &

  local dns_pid=$!

  printf "%s" "${CLR_CYAN}Validating DNS resolution${CLR_RESET}"
  while kill -0 "$dns_pid" 2>/dev/null; do
    sleep 0.3
    local dots_count=$((($(date +%s) % 3) + 1))
    local dots
    dots=$(printf '.%.0s' $(seq 1 $dots_count))
    printf "\r%sValidating DNS resolution%s%-3s%s" "${CLR_CYAN}" "${CLR_ORANGE}" "$dots" "${CLR_RESET}"
  done

  wait "$dns_pid" 2>/dev/null
  local dns_result
  dns_result=$(cat "$dns_result_file")
  rm -f "$dns_result_file"

  printf "\r%-80s\r" " "
  return "$dns_result"
}

# Show DNS error and fallback to self-signed. $1=error_type (1=no resolve, 2=wrong IP)
_ssl_show_dns_error() {
  local error_type="$1"

  _wiz_hide_cursor
  if [[ $error_type -eq 1 ]]; then
    _wiz_description \
      "  {{red:✗ Domain does not resolve to any IP address}}" \
      "" \
      "  Please configure DNS A record:" \
      "  {{orange:${FQDN}}} → {{orange:${MAIN_IPV4}}}" \
      "" \
      "  Falling back to self-signed certificate."
  else
    _wiz_description \
      "  {{red:✗ Domain resolves to wrong IP address}}" \
      "" \
      "  Current DNS: {{orange:${FQDN}}} → {{red:${DNS_RESOLVED_IP}}}" \
      "  Expected:    {{orange:${FQDN}}} → {{orange:${MAIN_IPV4}}}" \
      "" \
      "  Please update DNS A record to point to {{orange:${MAIN_IPV4}}}" \
      "" \
      "  Falling back to self-signed certificate."
  fi
  sleep "$((WIZARD_MESSAGE_DELAY + 2))"
}

# Validate Let's Encrypt requirements. Returns 0=valid, 1=fallback to self-signed
_ssl_validate_letsencrypt() {
  _ssl_validate_fqdn || return 1

  local dns_result
  _ssl_check_dns_animated
  dns_result=$?

  if [[ $dns_result -ne 0 ]]; then
    _ssl_show_dns_error "$dns_result"
    return 1
  fi

  _wiz_info "DNS resolution successful"
  _wiz_dim "${CLR_ORANGE}${FQDN}${CLR_RESET} → ${CLR_CYAN}${DNS_RESOLVED_IP}${CLR_RESET}"
  sleep "${WIZARD_MESSAGE_DELAY:-3}"
  return 0
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

  _show_input_footer "filter" 3

  if ! _wiz_choose_mapped "SSL_TYPE" "SSL Certificate:" \
    "${WIZ_MAP_SSL_TYPE[@]}"; then
    return
  fi

  # Validate Let's Encrypt requirements, fallback to self-signed if not met
  if [[ $SSL_TYPE == "letsencrypt" ]]; then
    if ! _ssl_validate_letsencrypt; then
      SSL_TYPE="self-signed"
    fi
  fi
}
