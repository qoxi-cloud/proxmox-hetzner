#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Configure Proxmox API Token
# =============================================================================

create_api_token() {
  [[ $INSTALL_API_TOKEN != "yes" ]] && return 0

  log "INFO: Creating Proxmox API token: ${API_TOKEN_NAME}"

  # Check if token already exists and remove
  local existing
  existing=$(remote_exec "pveum user token list root@pam 2>/dev/null | grep -q '${API_TOKEN_NAME}' && echo 'exists' || echo ''" || true)

  if [[ $existing == "exists" ]]; then
    log "WARNING: Token ${API_TOKEN_NAME} exists, removing first"
    remote_exec "pveum user token remove root@pam ${API_TOKEN_NAME}" || true
  fi

  # Create privileged token without expiration using JSON output
  local output
  output=$(remote_exec "pveum user token add root@pam ${API_TOKEN_NAME} --privsep 0 --expire 0 --output-format json 2>&1" || true)

  if [[ -z $output ]]; then
    log "ERROR: Failed to create API token - empty output"
    print_warning "API token creation failed - continuing without it"
    return 1
  fi

  # Parse JSON output to extract token value using jq
  local token_value
  token_value=$(echo "$output" | jq -r '.value // empty' 2>/dev/null || true)

  if [[ -z $token_value ]]; then
    log "ERROR: Failed to extract token value from pveum output"
    log "DEBUG: pveum output: $output"
    print_warning "API token creation failed - continuing without it"
    return 1
  fi

  # Store for final display
  API_TOKEN_VALUE="$token_value"
  API_TOKEN_ID="root@pam!${API_TOKEN_NAME}"

  # Save to temp file for display after installation
  cat >/tmp/pve-install-api-token.env <<EOF
API_TOKEN_VALUE=$token_value
API_TOKEN_ID=$API_TOKEN_ID
API_TOKEN_NAME=$API_TOKEN_NAME
EOF

  log "INFO: API token created successfully: ${API_TOKEN_ID}"
  return 0
}
