# shellcheck shell=bash
# Display utilities

# Print success with checkmark. $1=label, $2=value (optional)
print_success() {
  if [[ $# -eq 2 ]]; then
    printf '%s\n' "${CLR_CYAN}✓${CLR_RESET} $1 ${CLR_CYAN}$2${CLR_RESET}"
  else
    printf '%s\n' "${CLR_CYAN}✓${CLR_RESET} $1"
  fi
}

# Print error with red cross. $1=message
print_error() {
  printf '%s\n' "${CLR_RED}✗${CLR_RESET} $1"
}

# Print warning with yellow icon. $1=message, $2="true" or value (optional)
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

# Print info with cyan icon. $1=message
print_info() {
  printf '%s\n' "${CLR_CYAN}ℹ${CLR_RESET} $1"
}

# Progress indicators

# Show gum spinner while process runs. $1=pid, $2=message, $3=done_msg/--silent
show_progress() {
  local pid=$1
  local message="${2:-Processing}"
  local done_message="${3:-$message}"
  local silent=false
  [[ ${3:-} == "--silent" || ${4:-} == "--silent" ]] && silent=true
  [[ ${3:-} == "--silent" ]] && done_message="$message"

  # Use gum spin to wait for the process
  local poll_interval="${PROGRESS_POLL_INTERVAL:-0.2}"
  gum spin --spinner meter --spinner.foreground "#ff8700" --title "$message" -- bash -c "
    while kill -0 $pid 2>/dev/null; do
      sleep $poll_interval
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

# Format wizard header with line-dot-line. $1=title
format_wizard_header() {
  local title="$1"

  # Use global constants for centering (from 000-init.sh and 003-banner.sh)
  local banner_pad="$_BANNER_PAD"
  local line_width=$((BANNER_WIDTH - 3)) # minus 3 as requested

  # Calculate line segments: left line + dot + right line = line_width
  # Dot takes 1 char, so each side = (line_width - 1) / 2
  local half=$(((line_width - 1) / 2))
  local left_line="" right_line="" i

  # Use loop instead of tr (tr breaks multi-byte unicode chars on macOS)
  for ((i = 0; i < half; i++)); do
    left_line+="━"
  done
  for ((i = 0; i < line_width - 1 - half; i++)); do
    right_line+="─"
  done

  # Center title above the dot (dot is at position 'half' from line start)
  local title_len=${#title}
  local dot_pos=$half
  local title_start=$((dot_pos - title_len / 2))
  local title_spaces=""
  ((title_start > 0)) && title_spaces=$(printf '%*s' "$title_start" '')

  # Output: label line, then line with dot
  # Add 2 spaces to center the shorter line relative to banner
  printf '%s  %s%s\n' "$banner_pad" "$title_spaces" "${CLR_ORANGE}${title}${CLR_RESET}"
  printf '%s  %s%s%s%s' "$banner_pad" "${CLR_CYAN}${left_line}" "${CLR_ORANGE}●" "${CLR_GRAY}${right_line}${CLR_RESET}" ""
}
