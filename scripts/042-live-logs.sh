# shellcheck shell=bash
# =============================================================================
# Live installation logs with logo and auto-scroll
# =============================================================================

# Get terminal dimensions
get_terminal_dimensions() {
  TERM_HEIGHT=$(tput lines)
  TERM_WIDTH=$(tput cols)
}

# Logo height uses BANNER_HEIGHT constant from 003-banner.sh
# Fallback to 9 if not defined (6 ASCII art + 1 empty + 1 tagline + 1 spacing)
LOGO_HEIGHT=${BANNER_HEIGHT:-9}

# Fixed header height (empty + title + empty)
HEADER_HEIGHT=3

# Calculate available space for logs
calculate_log_area() {
  get_terminal_dimensions
  LOG_AREA_HEIGHT=$((TERM_HEIGHT - LOGO_HEIGHT - HEADER_HEIGHT - 1))
}

# Array to store log lines
declare -a LOG_LINES=()
LOG_COUNT=0

# Add log entry
add_log() {
  local message="$1"
  LOG_LINES+=("$message")
  ((LOG_COUNT++))
  render_logs
}

# Render header in wizard style (centered like completion screen)
_render_install_header() {
  # Use ANSI escape instead of tput for speed
  printf '\033[%d;0H' "$((LOGO_HEIGHT + 1))"
  printf '\n%s\n\n' "                     ${CLR_ORANGE}●${CLR_RESET} ${CLR_CYAN}Installing Proxmox${CLR_RESET} ${CLR_ORANGE}●${CLR_RESET}"
}

# Render all logs (with auto-scroll, no flicker)
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
}

# Start task (shows working ellipsis ...)
start_task() {
  local message="$1"
  add_log "$message..."
  TASK_INDEX=$((LOG_COUNT - 1))
}

# Complete task with status indicator
# Parameters:
#   $1 - task index
#   $2 - message
#   $3 - status: "success" (default, ✓), "error" (✗), "warning" (⚠)
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

# Add sub-task log entry (indented with tree structure)
add_subtask_log() {
  local message="$1"
  add_log "${CLR_ORANGE}│${CLR_RESET}   ${CLR_GRAY}${message}${CLR_RESET}"
}

# Start live installation display
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

  # Set trap to restore cursor and exit alternate buffer on exit
  trap 'tput cnorm; tput rmcup' EXIT RETURN
}

# Finish live installation display
finish_live_installation() {
  tput cnorm # Show cursor
  tput rmcup # Exit alternate screen buffer
}

# Live version of show_progress - updates the live log display
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
    sleep 0.3
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

# Add a live log entry for subtask info
live_log_subtask() {
  local message="$1"
  add_subtask_log "$message"
}

# Log multiple items as comma-separated list wrapped across lines
# Usage: log_subtasks "${array[@]}" or log_subtasks $string
# Output: │   item1, item2, item3,
#         │   item4, item5
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
      add_log "${CLR_ORANGE}│${CLR_RESET}   ${CLR_GRAY}${current_line},${CLR_RESET}"
      current_line="$item"
    else
      current_line+="$addition"
    fi
  done

  # Print remaining items
  if [[ -n $current_line ]]; then
    add_log "${CLR_ORANGE}│${CLR_RESET}   ${CLR_GRAY}${current_line}${CLR_RESET}"
  fi
}
