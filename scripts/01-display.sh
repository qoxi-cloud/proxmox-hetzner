# shellcheck shell=bash
# =============================================================================
# Display utilities
# =============================================================================

# Colorizes the output of boxes (post-process).
# Adds cyan frame and colors for [OK], [WARN], [ERROR] markers.
# Reads from stdin, writes to stdout.
colorize_status() {
  while IFS= read -r line; do
    # Top/bottom border
    if [[ $line =~ ^\+[-+]+\+$ ]]; then
      echo "${CLR_GRAY}${line}${CLR_RESET}"
    # Content line with | borders
    elif [[ $line =~ ^(\|)(.*)\|$ ]]; then
      local content="${BASH_REMATCH[2]}"
      # Color status markers
      content="${content//\[OK\]/${CLR_CYAN}[OK]${CLR_RESET}}"
      content="${content//\[WARN\]/${CLR_YELLOW}[WARN]${CLR_RESET}}"
      content="${content//\[ERROR\]/${CLR_RED}[ERROR]${CLR_RESET}}"
      echo "${CLR_GRAY}|${CLR_RESET}${content}${CLR_GRAY}|${CLR_RESET}"
    else
      echo "$line"
    fi
  done
}

# Prints success message with checkmark.
# Parameters:
#   $1 - Label or full message
#   $2 - Optional value (highlighted in cyan)
print_success() {
  if [[ $# -eq 2 ]]; then
    echo -e "${CLR_CYAN}✓${CLR_RESET} $1 ${CLR_CYAN}$2${CLR_RESET}"
  else
    echo -e "${CLR_CYAN}✓${CLR_RESET} $1"
  fi
}

# Prints error message with red cross icon.
# Parameters:
#   $1 - Error message to display
print_error() {
  echo -e "${CLR_RED}✗${CLR_RESET} $1"
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
    # Two-argument format: label and value
    echo -e "${CLR_YELLOW}⚠️${CLR_RESET} $message ${CLR_CYAN}$second${CLR_RESET}"
  else
    # Original format: message with optional nested indent
    if [[ $second == "true" ]]; then
      indent="  "
    fi
    echo -e "${indent}${CLR_YELLOW}⚠️${CLR_RESET} $message"
  fi
}

# Prints informational message with cyan info symbol.
# Parameters:
#   $1 - Informational message to display
print_info() {
  echo -e "${CLR_CYAN}ℹ${CLR_RESET} $1"
}
