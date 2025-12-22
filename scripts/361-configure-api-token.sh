#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Configure Proxmox API Token
# =============================================================================

# Creates privileged Proxmox API token for automation (Terraform, Ansible).
# Token has Administrator role with no expiration.
# Side effects: Sets API_TOKEN_VALUE, API_TOKEN_ID globals, writes to /tmp
create_api_token() {
  [[ $INSTALL_API_TOKEN != "yes" ]] && return 0

  log "INFO: Creating Proxmox API token for ${ADMIN_USERNAME}: ${API_TOKEN_NAME}"

  # Note: PAM user and Administrator role are set up in 302-configure-admin.sh

  # Check if token already exists and remove
  local existing
  existing=$(remote_exec "pveum user token list ${ADMIN_USERNAME}@pam 2>/dev/null | grep -q '${API_TOKEN_NAME}' && echo 'exists' || echo ''")

  if [[ $existing == "exists" ]]; then
    log "WARNING: Token ${API_TOKEN_NAME} exists, removing first"
    remote_exec "pveum user token remove ${ADMIN_USERNAME}@pam ${API_TOKEN_NAME}" || {
      log "ERROR: Failed to remove existing token"
      return 1
    }
  fi

  # Create privileged token without expiration using JSON output
  local output
  output=$(remote_exec "pveum user token add ${ADMIN_USERNAME}@pam ${API_TOKEN_NAME} --privsep 0 --expire 0 --output-format json 2>&1")

  if [[ -z $output ]]; then
    log "ERROR: Failed to create API token - empty output"
    return 1
  fi

  # Filter out perl locale warnings and other non-JSON output
  # Only keep lines that could be valid JSON (starting with { or containing "value")
  local json_output
  json_output=$(echo "$output" | grep -v "^perl:" | grep -v "^warning:" | grep -E '^\{|"value"' | head -1)

  # Parse JSON output to extract token value using jq
  local token_value
  token_value=$(echo "$json_output" | jq -r '.value // empty' 2>/dev/null || true)

  if [[ -z $token_value ]]; then
    log "ERROR: Failed to extract token value from pveum output"
    log "DEBUG: pveum output: $output"
    return 1
  fi

  # Store for final display
  API_TOKEN_VALUE="$token_value"
  API_TOKEN_ID="${ADMIN_USERNAME}@pam!${API_TOKEN_NAME}"

  # Save to temp file for display after installation (restricted permissions)
  (
    umask 0077
    cat >/tmp/pve-install-api-token.env <<EOF
API_TOKEN_VALUE=$token_value
API_TOKEN_ID=$API_TOKEN_ID
API_TOKEN_NAME=$API_TOKEN_NAME
EOF
  )

  log "INFO: API token created successfully: ${API_TOKEN_ID}"
  return 0
}
