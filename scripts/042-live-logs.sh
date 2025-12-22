# shellcheck shell=bash
# =============================================================================
# Live installation logs with logo and auto-scroll
# =============================================================================

# Gets current terminal dimensions for log area calculations.
# Side effects: Sets _LOG_TERM_HEIGHT and _LOG_TERM_WIDTH globals
get_terminal_dimensions() {
  _LOG_TERM_HEIGHT=$(tput lines)
  _LOG_TERM_WIDTH=$(tput cols)
}

# Logo height uses BANNER_HEIGHT constant from 003-banner.sh
# Fallback to 9 if not defined (6 ASCII art + 1 empty + 1 tagline + 1 spacing)
LOGO_HEIGHT=${BANNER_HEIGHT:-9}

# Fixed header height (title label + line with dot + 2 blank lines)
HEADER_HEIGHT=4

# Calculates available vertical space for log display.
# Subtracts banner height and header from terminal height.
# Side effects: Sets LOG_AREA_HEIGHT global
calculate_log_area() {
  get_terminal_dimensions
  LOG_AREA_HEIGHT=$((_LOG_TERM_HEIGHT - LOGO_HEIGHT - HEADER_HEIGHT - 1))
}

# Array to store log lines
declare -a LOG_LINES=()
LOG_COUNT=0

# Adds a log entry to the live display and triggers re-render.
# Parameters:
#   $1 - Message to display
# Side effects: Appends to LOG_LINES array, increments LOG_COUNT
add_log() {
  local message="$1"
  LOG_LINES+=("$message")
  ((LOG_COUNT++))
  render_logs
}

# Renders installation header in wizard style with progress indicator.
# Positions cursor below banner and displays "Installing Proxmox" header.
_render_install_header() {
  # Use ANSI escape instead of tput for speed
  printf '\033[%d;0H' "$((LOGO_HEIGHT + 1))"
  format_wizard_header "Installing Proxmox"
  _wiz_blank_line
  _wiz_blank_line
}

# Renders all log lines with auto-scroll behavior.
# Shows most recent logs that fit in LOG_AREA_HEIGHT, clears remaining lines.
# Uses ANSI escapes for flicker-free updates.
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

# Starts a task with "..." suffix indicating work in progress.
# Parameters:
#   $1 - Task description message
# Side effects: Adds log entry, sets TASK_INDEX to current position
start_task() {
  local message="$1"
  add_log "$message..."
  TASK_INDEX=$((LOG_COUNT - 1))
}

# Completes a task by updating its log line with status indicator.
# Parameters:
#   $1 - Task index in LOG_LINES array
#   $2 - Final message to display
#   $3 - Status: "success" (default, ✓), "error" (✗), "warning" (⚠)
# Side effects: Updates LOG_LINES[task_index], re-renders logs
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

# Adds an indented sub-task log entry with tree structure prefix.
# Parameters:
#   $1 - Subtask message to display
add_subtask_log() {
  local message="$1"
  add_log "${CLR_ORANGE}│${CLR_RESET}   ${CLR_GRAY}${message}${CLR_RESET}"
}

# Starts live installation display in alternate screen buffer.
# Overrides show_progress with live version, hides cursor.
# Side effects: Enters alternate screen, sets up EXIT trap
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

# Finishes live installation display and restores normal terminal.
# Shows cursor and exits alternate screen buffer.
finish_live_installation() {
  tput cnorm # Show cursor
  tput rmcup # Exit alternate screen buffer
}

# Live version of show_progress that updates the live log display.
# Shows animated dots while waiting for process, updates status on completion.
# Parameters:
#   $1 - PID of process to wait for
#   $2 - Progress message (shown while running)
#   $3 - Done message (optional, defaults to $2)
#   $4 - Optional "--silent" flag to suppress output on success
# Returns: Exit code from the waited process
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

# Adds a live log entry for subtask info with tree structure.
# Parameters:
#   $1 - Subtask message
live_log_subtask() {
  local message="$1"
  add_subtask_log "$message"
}

# Logs multiple items as comma-separated list wrapped across lines.
# Automatically wraps long lines at max_width characters.
# Parameters:
#   $@ - Items to display (array or space-separated string)
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
