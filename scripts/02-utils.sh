# shellcheck shell=bash
# =============================================================================
# General utilities
# =============================================================================

# Downloads file with retry logic and integrity verification.
# Parameters:
#   $1 - Output file path
#   $2 - URL to download from
# Returns: 0 on success, 1 on failure
download_file() {
  local output_file="$1"
  local url="$2"
  local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"
  local retry_delay="${DOWNLOAD_RETRY_DELAY:-2}"
  local retry_count=0

  while [ "$retry_count" -lt "$max_retries" ]; do
    if wget -q -O "$output_file" "$url"; then
      if [ -s "$output_file" ]; then
        # Check file integrity - verify it's not corrupted/empty
        local file_type
        file_type=$(file "$output_file" 2>/dev/null || echo "")

        # For files detected as "empty" or suspicious "data", verify size
        if echo "$file_type" | grep -q "empty"; then
          print_error "Downloaded file is empty: $output_file"
          retry_count=$((retry_count + 1))
          continue
        fi

        return 0
      else
        print_error "Downloaded file is empty: $output_file"
      fi
    else
      print_warning "Download failed (attempt $((retry_count + 1))/$max_retries): $url"
    fi
    retry_count=$((retry_count + 1))
    [ "$retry_count" -lt "$max_retries" ] && sleep "$retry_delay"
  done

  log "ERROR: Failed to download $url after $max_retries attempts"
  return 1
}

# =============================================================================
# Template processing utilities
# =============================================================================

# Applies template variable substitutions to a file.
# Parameters:
#   $1 - File path to modify
#   $@ - VAR=VALUE pairs for substitution (replaces {{VAR}} with VALUE)
# Returns: 0 on success, 1 if file not found
apply_template_vars() {
  local file="$1"
  shift

  if [[ ! -f $file ]]; then
    log "ERROR: Template file not found: $file"
    return 1
  fi

  # Build sed command with all substitutions
  local sed_args=()

  if [[ $# -gt 0 ]]; then
    # Use provided VAR=VALUE pairs
    for pair in "$@"; do
      local var="${pair%%=*}"
      local value="${pair#*=}"
      # Escape special characters in value for sed
      value="${value//\\/\\\\}"
      value="${value//&/\\&}"
      value="${value//|/\\|}"
      sed_args+=(-e "s|{{${var}}}|${value}|g")
    done
  fi

  if [[ ${#sed_args[@]} -gt 0 ]]; then
    sed -i "${sed_args[@]}" "$file"
  fi
}

# Applies common template variables to a file using global variables.
# Substitutes placeholders for IP, hostname, DNS, network settings.
# Parameters:
#   $1 - File path to modify
apply_common_template_vars() {
  local file="$1"

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
    "DNS_TERTIARY=${DNS_TERTIARY:-8.8.8.8}" \
    "DNS_QUATERNARY=${DNS_QUATERNARY:-8.8.4.4}" \
    "DNS6_PRIMARY=${DNS6_PRIMARY:-2606:4700:4700::1111}" \
    "DNS6_SECONDARY=${DNS6_SECONDARY:-2606:4700:4700::1001}"
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
    *.conf | *.sources | *.service)
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

# Generates a secure random password.
# Parameters:
#   $1 - Password length (default: 16)
# Returns: Random password via stdout
generate_password() {
  local length="${1:-16}"
  # Use /dev/urandom with base64, filter to alphanumeric + some special chars
  tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c "$length"
}

# Reads password from user with asterisks shown for each character.
# Parameters:
#   $1 - Prompt text
# Returns: Password via stdout
read_password() {
  local prompt="$1"
  local password=""
  local char=""

  # Output prompt to stderr so it's visible when stdout is captured
  echo -n "$prompt" >&2

  while IFS= read -r -s -n1 char; do
    if [[ -z $char ]]; then
      break
    fi
    if [[ $char == $'\x7f' || $char == $'\x08' ]]; then
      if [[ -n $password ]]; then
        password="${password%?}"
        echo -ne "\b \b" >&2
      fi
    else
      password+="$char"
      echo -n "*" >&2
    fi
  done

  # Newline to stderr for display
  echo "" >&2
  # Password to stdout for capture
  echo "$password"
}

# Prompts for input with validation loop until valid value provided.
# Parameters:
#   $1 - Prompt text
#   $2 - Default value
#   $3 - Validator function name
#   $4 - Error message for invalid input
# Returns: Validated input value via stdout
prompt_validated() {
  local prompt="$1"
  local default="$2"
  local validator="$3"
  local error_msg="$4"
  local result=""

  while true; do
    read -r -e -p "$prompt" -i "$default" result
    if $validator "$result"; then
      echo "$result"
      return 0
    fi
    print_error "$error_msg"
  done
}

# =============================================================================
# Progress indicators
# =============================================================================

# Shows progress indicator with gum spinner while process runs.
# Parameters:
#   $1 - PID of process to wait for
#   $2 - Progress message
#   $3 - Optional done message or "--silent" to clear line on success
#   $4 - Optional "--silent" flag
# Returns: Exit code of the waited process
show_progress() {
  local pid=$1
  local message="${2:-Processing}"
  local done_message="${3:-$message}"
  local silent=false
  [[ ${3:-} == "--silent" || ${4:-} == "--silent" ]] && silent=true
  [[ ${3:-} == "--silent" ]] && done_message="$message"

  # Use gum spin to wait for the process
  gum spin --spinner meter --spinner.foreground "#ff8700" --title "$message" -- bash -c "
    while kill -0 $pid 2>/dev/null; do
      sleep 0.2
    done
  "

  # Get exit code from the original process
  wait "$pid" 2>/dev/null
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    if [[ $silent != true ]]; then
      printf "${CLR_CYAN}✓${CLR_RESET} %s\n" "$done_message"
    fi
  else
    printf "${CLR_RED}✗${CLR_RESET} %s\n" "$message"
  fi

  return $exit_code
}

# Shows timed progress bar with visual animation.
# Parameters:
#   $1 - Progress message
#   $2 - Duration in seconds (default: 5-7 random)
show_timed_progress() {
  local message="$1"
  local duration="${2:-$((5 + RANDOM % 3))}" # 5-7 seconds default
  local steps=20
  local sleep_interval
  sleep_interval=$(awk "BEGIN {printf \"%.2f\", $duration / $steps}")

  local current=0
  while [[ $current -le $steps ]]; do
    local pct=$((current * 100 / steps))
    local filled=$current
    local empty=$((steps - filled))
    local bar_filled="" bar_empty=""

    # Build progress bar strings without spawning subprocesses
    printf -v bar_filled '%*s' "$filled" ''
    bar_filled="${bar_filled// /█}"
    printf -v bar_empty '%*s' "$empty" ''
    bar_empty="${bar_empty// /░}"

    printf "\r${CLR_ORANGE}%s [${CLR_ORANGE}%s${CLR_RESET}${CLR_GRAY}%s${CLR_RESET}${CLR_ORANGE}] %3d%%${CLR_RESET}" \
      "$message" "$bar_filled" "$bar_empty" "$pct"

    if [[ $current -lt $steps ]]; then
      sleep "$sleep_interval"
    fi
    current=$((current + 1))
  done

  # Clear the progress bar line
  printf "\r\e[K"
}

# Formats time duration in seconds to human-readable string.
# Parameters:
#   $1 - Duration in seconds
# Returns: Formatted duration (e.g., "1h 30m 45s") via stdout
format_duration() {
  local seconds="$1"
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  local secs=$((seconds % 60))

  if [[ $hours -gt 0 ]]; then
    echo "${hours}h ${minutes}m ${secs}s"
  else
    echo "${minutes}m ${secs}s"
  fi
}
