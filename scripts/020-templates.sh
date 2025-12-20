# shellcheck shell=bash
# =============================================================================
# Template processing utilities
# =============================================================================

# Applies template variable substitutions to a file.
# Parameters:
#   $1 - File path to modify
#   $@ - VAR=VALUE pairs for substitution (replaces {{VAR}} with VALUE)
# Returns: 0 on success, 1 if file not found or critical variable empty
apply_template_vars() {
  local file="$1"
  shift

  if [[ ! -f $file ]]; then
    log "ERROR: Template file not found: $file"
    return 1
  fi

  # Build sed command with all substitutions
  local sed_args=()
  local has_empty_critical=false

  if [[ $# -gt 0 ]]; then
    # Use provided VAR=VALUE pairs
    for pair in "$@"; do
      local var="${pair%%=*}"
      local value="${pair#*=}"

      # Warn about empty values that will leave placeholders
      if [[ -z $value ]]; then
        log "WARNING: Template variable $var is empty for $file"
        # Check if this placeholder exists in the file
        if grep -qF "{{${var}}}" "$file" 2>/dev/null; then
          log "WARNING: Placeholder {{${var}}} will remain in $file"
          has_empty_critical=true
        fi
      fi

      # Escape special characters in value for sed replacement
      # - \ must be escaped first (before adding more backslashes)
      # - & is replaced with matched pattern
      # - | is our delimiter
      # - newlines need special handling
      value="${value//\\/\\\\}"
      value="${value//&/\\&}"
      value="${value//|/\\|}"
      # Handle newlines - replace with escaped newline for sed
      value="${value//$'\n'/\\$'\n'}"

      sed_args+=(-e "s|{{${var}}}|${value}|g")
    done
  fi

  if [[ ${#sed_args[@]} -gt 0 ]]; then
    sed -i "${sed_args[@]}" "$file"
  fi

  # Verify no unsubstituted placeholders remain
  if grep -qE '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null; then
    local remaining
    remaining=$(grep -oE '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null | sort -u | tr '\n' ' ')
    log "WARNING: Unsubstituted placeholders remain in $file: $remaining"
  fi

  # Return error if critical placeholders would remain
  if [[ $has_empty_critical == true ]]; then
    return 1
  fi

  return 0
}

# Applies common template variables to a file using global variables.
# Substitutes placeholders for IP, hostname, DNS, network settings.
# Parameters:
#   $1 - File path to modify
# Returns: 0 on success, 1 if critical variable is empty
apply_common_template_vars() {
  local file="$1"

  # Warn about empty critical variables
  local -a critical_vars=(MAIN_IPV4 MAIN_IPV4_GW PVE_HOSTNAME INTERFACE_NAME)
  for var in "${critical_vars[@]}"; do
    if [[ -z ${!var:-} ]]; then
      log "WARNING: [apply_common_template_vars] Critical variable $var is empty for $file"
    fi
  done

  apply_template_vars "$file" \
    "MAIN_IPV4=${MAIN_IPV4:-}" \
    "MAIN_IPV4_GW=${MAIN_IPV4_GW:-}" \
    "MAIN_IPV6=${MAIN_IPV6:-}" \
    "FIRST_IPV6_CIDR=${FIRST_IPV6_CIDR:-}" \
    "IPV6_GATEWAY=${IPV6_GATEWAY:-fe80::1}" \
    "FQDN=${FQDN:-}" \
    "HOSTNAME=${PVE_HOSTNAME:-}" \
    "INTERFACE_NAME=${INTERFACE_NAME:-}" \
    "PRIVATE_IP_CIDR=${PRIVATE_IP_CIDR:-}" \
    "PRIVATE_SUBNET=${PRIVATE_SUBNET:-}" \
    "BRIDGE_MTU=${BRIDGE_MTU:-9000}" \
    "DNS_PRIMARY=${DNS_PRIMARY:-1.1.1.1}" \
    "DNS_SECONDARY=${DNS_SECONDARY:-1.0.0.1}" \
    "DNS6_PRIMARY=${DNS6_PRIMARY:-2606:4700:4700::1111}" \
    "DNS6_SECONDARY=${DNS6_SECONDARY:-2606:4700:4700::1001}" \
    "LOCALE=${LOCALE:-en_US.UTF-8}" \
    "KEYBOARD=${KEYBOARD:-us}" \
    "COUNTRY=${COUNTRY:-US}" \
    "BAT_THEME=${BAT_THEME:-Catppuccin Mocha}"
}

# Post-processes interfaces template when IPv6 is disabled.
# Removes inet6 sections to prevent invalid config with empty addresses.
# Parameters:
#   $1 - Path to interfaces file
postprocess_interfaces_ipv6() {
  local file="$1"

  if [[ ! -f $file ]]; then
    log "ERROR: Interfaces file not found: $file"
    return 1
  fi

  # Only process if IPv6 is disabled
  if [[ -z ${MAIN_IPV6:-} ]] || [[ ${IPV6_MODE:-} == "disabled" ]]; then
    log "IPv6 disabled - removing inet6 sections from interfaces"
    # Remove "iface ... inet6 static" blocks (keeps loopback)
    sed -i '/^iface .* inet6 static$/,/^$/d' "$file"
  fi
}

# Downloads template from GitHub repository with validation.
# Parameters:
#   $1 - Local path to save template
#   $2 - Optional remote filename (defaults to basename of $1)
# Returns: 0 on success, 1 on failure
# Note: Templates have .tmpl extension on GitHub but saved locally without it
download_template() {
  local local_path="$1"
  local remote_file="${2:-$(basename "$local_path")}"
  # Add .tmpl extension for remote file (all templates use .tmpl on GitHub)
  local url="${GITHUB_BASE_URL}/templates/${remote_file}.tmpl"

  if ! download_file "$local_path" "$url"; then
    return 1
  fi

  # Verify file is not empty after download
  if [[ ! -s $local_path ]]; then
    print_error "Template $remote_file is empty or download failed"
    log "ERROR: Template $remote_file is empty after download"
    return 1
  fi

  # Validate template integrity based on file type
  local filename
  filename=$(basename "$local_path")
  case "$filename" in
    answer.toml)
      if ! grep -q "\[global\]" "$local_path" 2>/dev/null; then
        print_error "Template $remote_file appears corrupted (missing [global] section)"
        log "ERROR: Template $remote_file corrupted - missing [global] section"
        return 1
      fi
      ;;
    sshd_config)
      if ! grep -q "PasswordAuthentication" "$local_path" 2>/dev/null; then
        print_error "Template $remote_file appears corrupted (missing PasswordAuthentication)"
        log "ERROR: Template $remote_file corrupted - missing PasswordAuthentication"
        return 1
      fi
      ;;
    *.sh)
      # Shell scripts should start with shebang or at least contain some bash syntax
      if ! head -1 "$local_path" | grep -qE "^#!.*bash|^# shellcheck|^export " && ! grep -qE "(if|then|echo|function|export)" "$local_path" 2>/dev/null; then
        print_error "Template $remote_file appears corrupted (invalid shell script)"
        log "ERROR: Template $remote_file corrupted - invalid shell script"
        return 1
      fi
      ;;
    *.conf | *.sources | *.service | *.timer)
      # Config files should have some content
      if [[ $(wc -l <"$local_path" 2>/dev/null || echo 0) -lt 2 ]]; then
        print_error "Template $remote_file appears corrupted (too short)"
        log "ERROR: Template $remote_file corrupted - file too short"
        return 1
      fi
      ;;
  esac

  log "Template $remote_file downloaded and validated successfully"
  return 0
}
