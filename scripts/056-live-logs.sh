# shellcheck shell=bash
# Live installation logs with logo and auto-scroll

# Get terminal dimensions. Sets _LOG_TERM_HEIGHT, _LOG_TERM_WIDTH.
get_terminal_dimensions() {
  _LOG_TERM_HEIGHT=$(tput lines)
  _LOG_TERM_WIDTH=$(tput cols)
}

# Logo height uses BANNER_HEIGHT constant from 003-banner.sh
# Fallback to 9 if not defined (6 ASCII art + 1 empty + 1 tagline + 1 spacing)
LOGO_HEIGHT=${BANNER_HEIGHT:-9}

# Fixed header height (title label + line with dot + 2 blank lines)
HEADER_HEIGHT=4

# Calculate log area height. Sets LOG_AREA_HEIGHT.
calculate_log_area() {
  get_terminal_dimensions
  LOG_AREA_HEIGHT=$((_LOG_TERM_HEIGHT - LOGO_HEIGHT - HEADER_HEIGHT - 1))
}

# Array to store log lines
declare -a LOG_LINES=()
LOG_COUNT=0

# Add log entry to live display. $1=message
add_log() {
  local message="$1"
  LOG_LINES+=("$message")
  ((LOG_COUNT++))
  render_logs
}

# Renders installation header in wizard style with progress indicator.
# Positions cursor below banner and displays "Installing Proxmox" header.
# Output goes to /dev/tty to prevent leaking into log files
_render_install_header() {
  # Use ANSI escape instead of tput for speed
  printf '\033[%d;0H' "$((LOGO_HEIGHT + 1))"
  format_wizard_header "Installing Proxmox"
  _wiz_blank_line
  _wiz_blank_line
} >/dev/tty 2>/dev/null

# Renders all log lines with auto-scroll behavior.
# Shows most recent logs that fit in LOG_AREA_HEIGHT, clears remaining lines.
# Uses ANSI escapes for flicker-free updates.
# IMPORTANT: All output goes to /dev/tty to prevent leaking into log files
render_logs() {
  _render_install_header

  local start_line=0
  local lines_printed=0
  if ((LOG_COUNT > LOG_AREA_HEIGHT)); then
    start_line=$((LOG_COUNT - LOG_AREA_HEIGHT))
  fi
  for ((i = start_line; i < LOG_COUNT; i++)); do
    printf '%s\033[K\n' "${LOG_LINES[$i]}"
    ((lines_printed++))
  done

  # Clear any remaining lines below (in case log count decreased)
  local remaining=$((LOG_AREA_HEIGHT - lines_printed))
  for ((i = 0; i < remaining; i++)); do
    printf '\033[K\n'
  done
} >/dev/tty 2>/dev/null

# Start task with "..." suffix. $1=message. Sets TASK_INDEX.
start_task() {
  local message="$1"
  add_log "$message..."
  TASK_INDEX=$((LOG_COUNT - 1))
}

# Complete task with status. $1=idx, $2=message, $3=status (success/error/warning)
complete_task() {
  local task_index="$1"
  local message="$2"
  local status="${3:-success}"
  local indicator
  case "$status" in
    error) indicator="${CLR_RED}✗${CLR_RESET}" ;;
    warning) indicator="${CLR_YELLOW}⚠${CLR_RESET}" ;;
    *) indicator="${CLR_CYAN}✓${CLR_RESET}" ;;
  esac
  LOG_LINES[task_index]="$message $indicator"
  render_logs
}

# Add indented subtask with tree prefix. $1=message, $2=color (optional)
add_subtask_log() {
  local message="$1"
  local color="${2:-$CLR_GRAY}"
  add_log "${CLR_ORANGE}│${CLR_RESET}   ${color}${message}${CLR_RESET}"
}

# Start live installation display in alternate screen buffer
start_live_installation() {
  # Override show_progress with live version
  # shellcheck disable=SC2317,SC2329
  show_progress() {
    live_show_progress "$@"
  }

  calculate_log_area
  tput smcup # Enter alternate screen buffer
  tput civis # Hide cursor immediately
  _wiz_clear
  show_banner

  # Chain with existing cleanup handler - restore terminal THEN run global cleanup
  # shellcheck disable=SC2064
  trap "tput cnorm 2>/dev/null; tput rmcup 2>/dev/null; cleanup_and_error_handler" EXIT
}

# Finishes live installation display and restores normal terminal.
# Shows cursor and exits alternate screen buffer.
finish_live_installation() {
  tput cnorm # Show cursor
  tput rmcup # Exit alternate screen buffer
}

# Show progress with animated dots. $1=pid, $2=message, $3=done_msg, $4=--silent
live_show_progress() {
  local pid=$1
  local message="${2:-Processing}"
  local done_message="${3:-$message}"
  local silent=false
  [[ ${3:-} == "--silent" || ${4:-} == "--silent" ]] && silent=true
  [[ ${3:-} == "--silent" ]] && done_message="$message"

  # Add task to live display with spinner
  start_task "${CLR_ORANGE}├─${CLR_RESET} ${message}"
  local task_idx=$TASK_INDEX

  # Wait for process with periodic updates
  while kill -0 "$pid" 2>/dev/null; do
    sleep 0.3 # Animation timing, kept at 0.3 for visual smoothness
    # Update the task line with animated dots (orange)
    local dots_count=$((($(date +%s) % 3) + 1))
    local dots
    dots=$(printf '.%.0s' $(seq 1 $dots_count))
    LOG_LINES[task_idx]="${CLR_ORANGE}├─${CLR_RESET} ${message}${CLR_ORANGE}${dots}${CLR_RESET}"
    render_logs
  done

  # Get exit code
  wait "$pid" 2>/dev/null
  local exit_code=$?

  # Update with final status
  if [[ $exit_code -eq 0 ]]; then
    if [[ $silent != true ]]; then
      complete_task "$task_idx" "${CLR_ORANGE}├─${CLR_RESET} ${done_message}"
    else
      # Remove the line for silent mode
      unset 'LOG_LINES[task_idx]'
      LOG_LINES=("${LOG_LINES[@]}")
      ((LOG_COUNT--))
      render_logs
    fi
  else
    complete_task "$task_idx" "${CLR_ORANGE}├─${CLR_RESET} ${message}" "error"
  fi

  return $exit_code
}

# Add subtask to live log. $1=message
live_log_subtask() {
  local message="$1"
  add_subtask_log "$message"
}

# Log items as comma-separated wrapped list. $@=items
log_subtasks() {
  local max_width=55
  local current_line=""
  local first=true

  for item in "$@"; do
    local addition
    if [[ $first == true ]]; then
      addition="$item"
      first=false
    else
      addition=", $item"
    fi

    if [[ $((${#current_line} + ${#addition})) -gt $max_width && -n $current_line ]]; then
      add_subtask_log "${current_line},"
      current_line="$item"
    else
      current_line+="$addition"
    fi
  done

  # Print remaining items
  if [[ -n $current_line ]]; then
    add_subtask_log "$current_line"
  fi
}
