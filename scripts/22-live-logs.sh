# shellcheck shell=bash
# =============================================================================
# Live installation logs with logo and auto-scroll
# =============================================================================

# Get terminal dimensions
get_terminal_dimensions() {
  TERM_HEIGHT=$(tput lines)
  TERM_WIDTH=$(tput cols)
}

# Logo height (number of lines) - ASCII banner from show_banner()
LOGO_HEIGHT=9

# Calculate available space for logs
calculate_log_area() {
  get_terminal_dimensions
  LOG_AREA_HEIGHT=$((TERM_HEIGHT - LOGO_HEIGHT - 2))
}

# Array to store log lines
declare -a LOG_LINES=()
LOG_COUNT=0

# Save cursor position after logo
save_cursor_position() {
  printf '\033[s'
}

# Restore cursor to saved position
restore_cursor_position() {
  printf '\033[u'
  printf '\033[J'
}

# Add log entry
add_log() {
  local message="$1"
  LOG_LINES+=("$message")
  ((LOG_COUNT++))
  render_logs
}

# Render all logs (with auto-scroll, no flicker)
render_logs() {
  restore_cursor_position
  local start_line=0
  if ((LOG_COUNT > LOG_AREA_HEIGHT)); then
    start_line=$((LOG_COUNT - LOG_AREA_HEIGHT))
  fi
  for ((i = start_line; i < LOG_COUNT; i++)); do
    echo "${LOG_LINES[$i]}"
  done
}

# Start task (shows working ellipsis ...)
start_task() {
  local message="$1"
  add_log "$message..."
  TASK_INDEX=$((LOG_COUNT - 1))
}

# Complete task with checkmark
complete_task() {
  local task_index="$1"
  local message="$2"
  LOG_LINES[task_index]="$message ${CLR_CYAN}✓${CLR_RESET}"
  render_logs
}

# Add sub-task log entry (indented with tree structure)
add_subtask_log() {
  local message="$1"
  add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}${message}${CLR_RESET}"
}

# Start live installation display
start_live_installation() {
  if ! command -v gum &>/dev/null; then
    log "WARNING: gum is not installed, live logs disabled"
    return 1
  fi

  # Set flag that live logs are active
  LIVE_LOGS_ACTIVE=true

  # Save original show_progress function if it exists
  if type show_progress &>/dev/null 2>&1; then
    eval "$(declare -f show_progress | sed '1s/show_progress/show_progress_original/')"
  fi

  # Override show_progress with our live version
  # shellcheck disable=SC2317,SC2329
  show_progress() {
    live_show_progress "$@"
  }

  # Export the function so it's available in subshells
  export -f show_progress 2>/dev/null || true

  calculate_log_area
  clear
  show_banner
  save_cursor_position
  tput civis # Hide cursor

  # Add empty line after banner for spacing
  add_log ""

  # Set trap to restore cursor on exit
  trap 'tput cnorm' EXIT RETURN
}

# Finish live installation display
finish_live_installation() {
  LIVE_LOGS_ACTIVE=false

  # Restore original show_progress if it was saved
  if type show_progress_original &>/dev/null 2>&1; then
    # shellcheck disable=SC2317,SC2329
    show_progress() {
      show_progress_original "$@"
    }
  fi

  tput cnorm # Show cursor
  echo ""
}

# =============================================================================
# Installation process sections
# =============================================================================

# Generic section header function
# Parameters:
#   $1 - Section name
#   $2 - Optional: "first" to skip empty line before section
live_log_section() {
  local section_name="$1"
  local first="${2:-}"

  [[ $first != "first" ]] && add_log ""
  add_log "${CLR_CYAN}▼ $section_name${CLR_RESET}"
}

# Convenience wrappers for sections (for backward compatibility)
live_log_system_preparation() {
  live_log_section "Rescue System Preparation" "first"
}

live_log_iso_download() {
  live_log_section "Proxmox ISO Download"
}

live_log_proxmox_installation() {
  live_log_section "Proxmox Installation"
}

live_log_system_configuration() {
  live_log_section "System Configuration"
}

# Security Configuration section - shown conditionally
live_log_security_configuration() {
  # Only show if any security feature is being configured
  if [[ ${INSTALL_TAILSCALE:-} == "yes" ]] || [[ ${FAIL2BAN_INSTALLED:-} == "yes" ]] || [[ ${INSTALL_AUDITD:-} == "yes" ]]; then
    add_log ""
    add_log "${CLR_CYAN}▼ Security Configuration${CLR_RESET}"
  fi
}

# SSL Configuration section - shown conditionally
live_log_ssl_configuration() {
  if [[ ${SSL_TYPE:-} == "letsencrypt" ]]; then
    add_log ""
    add_log "${CLR_CYAN}▼ SSL Configuration${CLR_RESET}"
  fi
}

# Validation & Finalization section
live_log_validation_finalization() {
  live_log_section "Validation & Finalization"
}

# Installation complete message
live_log_installation_complete() {
  add_log ""
  add_log "${CLR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLR_RESET}"
  add_log "${CLR_CYAN}✓ Installation completed successfully!${CLR_RESET}"
  add_log "${CLR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLR_RESET}"
  add_log ""
}

# Flag to track if live logs are active
LIVE_LOGS_ACTIVE=false

# Override show_progress when live logs are active
# This version updates the live log display instead of using gum spin
live_show_progress() {
  local pid=$1
  local message="${2:-Processing}"
  local done_message="${3:-$message}"
  local silent=false
  [[ ${3:-} == "--silent" || ${4:-} == "--silent" ]] && silent=true
  [[ ${3:-} == "--silent" ]] && done_message="$message"

  # Add task to live display with spinner
  start_task "  ${CLR_GRAY}├─${CLR_RESET} ${message}"
  local task_idx=$TASK_INDEX

  # Wait for process with periodic updates
  while kill -0 "$pid" 2>/dev/null; do
    sleep 0.3
    # Update the task line with animated dots (orange)
    local dots_count=$((($(date +%s) % 3) + 1))
    local dots
    dots=$(printf '.%.0s' $(seq 1 $dots_count))
    LOG_LINES[task_idx]="  ${CLR_GRAY}├─${CLR_RESET} ${message}${CLR_ORANGE}${dots}${CLR_RESET}"
    render_logs
  done

  # Get exit code
  wait "$pid" 2>/dev/null
  local exit_code=$?

  # Update with final status
  if [[ $exit_code -eq 0 ]]; then
    if [[ $silent != true ]]; then
      complete_task "$task_idx" "  ${CLR_GRAY}├─${CLR_RESET} ${done_message}"
    else
      # Remove the line for silent mode
      unset 'LOG_LINES[task_idx]'
      LOG_LINES=("${LOG_LINES[@]}")
      ((LOG_COUNT--))
      render_logs
    fi
  else
    LOG_LINES[task_idx]="  ${CLR_GRAY}├─${CLR_RESET} ${message} ${CLR_RED}✗${CLR_RESET}"
    render_logs
  fi

  return $exit_code
}

# Add a live log entry for completed task
live_log_task_complete() {
  local message="$1"
  add_log "  ${CLR_GRAY}├─${CLR_RESET} ${message} ${CLR_CYAN}✓${CLR_RESET}"
}

# Add a live log entry for subtask info
live_log_subtask() {
  local message="$1"
  add_subtask_log "$message"
}
