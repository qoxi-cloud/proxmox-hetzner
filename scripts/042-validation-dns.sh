# shellcheck shell=bash
# DNS validation functions

# Validate FQDN resolves to IP. $1=fqdn, $2=expected_ip. Sets DNS_RESOLVED_IP.
validate_dns_resolution() {
  local fqdn="$1"
  local expected_ip="$2"
  local resolved_ip=""
  local dns_timeout="${DNS_LOOKUP_TIMEOUT:-5}" # Default 5 second timeout
  local retry_delay="${DNS_RETRY_DELAY:-10}"   # Default 10 second delay between retries
  local max_attempts=3

  # Determine which DNS tool to use (check once, not in loop)
  local dns_tool=""
  if cmd_exists dig; then
    dns_tool="dig"
  elif cmd_exists host; then
    dns_tool="host"
  elif cmd_exists nslookup; then
    dns_tool="nslookup"
  fi

  # If no DNS tool available, log warning and return no resolution
  if [[ -z $dns_tool ]]; then
    log "WARNING: No DNS lookup tool available (dig, host, or nslookup)"
    DNS_RESOLVED_IP=""
    return 1
  fi

  # Retry loop for DNS resolution
  for attempt in $(seq 1 "$max_attempts"); do
    resolved_ip=""

    # Try each public DNS server until we get a result (use global DNS_SERVERS)
    for dns_server in "${DNS_SERVERS[@]}"; do
      case "$dns_tool" in
        dig)
          # dig supports +time for timeout
          resolved_ip=$(timeout "$dns_timeout" dig +short +time=3 +tries=1 A "$fqdn" "@${dns_server}" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
          ;;
        host)
          # host supports -W for timeout
          resolved_ip=$(timeout "$dns_timeout" host -W 3 -t A "$fqdn" "$dns_server" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
          ;;
        nslookup)
          # nslookup doesn't have timeout option, use timeout command
          # Filter out server's Address line (has #port) to get resolved IP
          resolved_ip=$(timeout "$dns_timeout" nslookup -timeout=3 "$fqdn" "$dns_server" 2>/dev/null | awk '/^Address:/ && !/#/ {print $2; exit}')
          ;;
      esac

      if [[ -n $resolved_ip ]]; then
        break
      fi
    done

    # Fallback to system resolver if public DNS fails
    if [[ -z $resolved_ip ]]; then
      case "$dns_tool" in
        dig)
          resolved_ip=$(timeout "$dns_timeout" dig +short +time=3 +tries=1 A "$fqdn" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
          ;;
        *)
          if cmd_exists getent; then
            resolved_ip=$(timeout "$dns_timeout" getent ahosts "$fqdn" 2>/dev/null | grep STREAM | head -1 | awk '{print $1}')
          fi
          ;;
      esac
    fi

    # If we got a result, process it
    if [[ -n $resolved_ip ]]; then
      DNS_RESOLVED_IP="$resolved_ip"
      if [[ $resolved_ip == "$expected_ip" ]]; then
        return 0 # Match
      else
        return 2 # Wrong IP
      fi
    fi

    # No resolution on this attempt
    if [[ $attempt -lt $max_attempts ]]; then
      log "WARN: DNS lookup for $fqdn failed (attempt $attempt/$max_attempts), retrying in ${retry_delay}s..."
      sleep "$retry_delay"
    fi
  done

  # All attempts failed
  log "ERROR: Failed to resolve $fqdn after $max_attempts attempts"
  DNS_RESOLVED_IP=""
  return 1 # No resolution
}
