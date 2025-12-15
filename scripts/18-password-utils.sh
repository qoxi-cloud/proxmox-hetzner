# shellcheck shell=bash
# =============================================================================
# Password utilities
# =============================================================================

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
