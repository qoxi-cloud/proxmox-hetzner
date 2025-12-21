# shellcheck shell=bash
# =============================================================================
# Display utilities
# =============================================================================

# Prints success message with checkmark.
# Parameters:
#   $1 - Label or full message
#   $2 - Optional value (highlighted in cyan)
print_success() {
  if [[ $# -eq 2 ]]; then
    printf '%s\n' "${CLR_CYAN}✓${CLR_RESET} $1 ${CLR_CYAN}$2${CLR_RESET}"
  else
    printf '%s\n' "${CLR_CYAN}✓${CLR_RESET} $1"
  fi
}

# Prints error message with red cross icon.
# Parameters:
#   $1 - Error message to display
print_error() {
  printf '%s\n' "${CLR_RED}✗${CLR_RESET} $1"
}

# Prints warning message with yellow warning icon.
# Parameters:
#   $1 - Warning message or label
#   $2 - Optional: "true" for nested indent, or value to highlight in cyan
print_warning() {
  local message="$1"
  local second="${2:-false}"
  local indent=""

  # Check if second argument is a value (not "true" for nested)
  if [[ $# -eq 2 && $second != "true" ]]; then
    printf '%s\n' "${CLR_YELLOW}⚠️${CLR_RESET} $message ${CLR_CYAN}$second${CLR_RESET}"
  else
    if [[ $second == "true" ]]; then
      indent="  "
    fi
    printf '%s\n' "${indent}${CLR_YELLOW}⚠️${CLR_RESET} $message"
  fi
}

# Prints informational message with cyan info symbol.
# Parameters:
#   $1 - Informational message to display
print_info() {
  printf '%s\n' "${CLR_CYAN}ℹ${CLR_RESET} $1"
}

# Prints section header in cyan.
# Parameters:
#   $1 - Section header text
print_section() {
  printf '%s\n' "${CLR_CYAN}$1${CLR_RESET}"
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

# Formats wizard-style centered header with dots.
# Usage: format_wizard_header "Title"
# Returns: centered "● Title ●" with orange dots and cyan text
format_wizard_header() {
  local title="$1"
  # "● Title ●" = 4 chars for dots/spaces + title length
  local content_len=$((${#title} + 4))
  local padding=$(((TERM_WIDTH - content_len) / 2))
  local spaces=""
  ((padding > 0)) && spaces=$(printf '%*s' "$padding" "")
  printf '%s' "${spaces}${CLR_ORANGE}●${CLR_RESET} ${CLR_CYAN}${title}${CLR_RESET} ${CLR_ORANGE}●${CLR_RESET}"
}
