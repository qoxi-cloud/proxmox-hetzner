# shellcheck shell=bash
# =============================================================================
# Gum-based wizard UI - Input wrappers
# =============================================================================
# Provides gum-based input functions: text input, single/multi select,
# confirmation, spinner, and styled messages.

# =============================================================================
# Gum-based input wrappers
# =============================================================================

# Prompts for text input.
# Parameters:
#   $1 - Prompt label
#   $2 - Default/initial value (optional)
#   $3 - Placeholder text (optional)
#   $4 - Password mode: "true" or "false" (optional)
# wiz_input prompts the user for text input using gum and echoes the entered value to stdout.
# The first argument is the prompt label. The second optional argument is a default value
# (used as the initial value and, if the third argument is omitted, as the placeholder).
# The third optional argument is a placeholder string. The fourth optional argument is
# "true" to enable password mode (hides input); any other value leaves input visible.
# Styling and width are derived from WIZARD_WIDTH and global color variables; the function
# writes the collected input to stdout.
wiz_input() {
  local prompt="$1"
  local default="${2:-}"
  local placeholder="${3:-$default}"
  local password="${4:-false}"

  local args=(
    --prompt "$prompt "
    --cursor.foreground "$GUM_ACCENT"
    --prompt.foreground "$GUM_PRIMARY"
    --placeholder.foreground "$GUM_MUTED"
    --width "$((WIZARD_WIDTH - 4))"
  )

  [[ -n $default ]] && args+=(--value "$default")
  [[ -n $placeholder ]] && args+=(--placeholder "$placeholder")
  [[ $password == "true" ]] && args+=(--password)

  gum input "${args[@]}"
}

# Prompts for selection from a list.
# Parameters:
#   $1 - Header/question text
#   $@ - Remaining args: list of options
# Returns: Selected option via stdout
# wiz_choose prompts the user to select one option from the provided list and echoes the selected option.
# It sets the global WIZ_SELECTED_INDEX variable to the 0-based index of the chosen option.
wiz_choose() {
  local header="$1"
  shift
  local options=("$@")

  local result
  result=$(gum choose \
    --header "$header" \
    --cursor "› " \
    --cursor.foreground "$GUM_ACCENT" \
    --selected.foreground "$GUM_PRIMARY" \
    --header.foreground "$GUM_MUTED" \
    --height 10 \
    "${options[@]}")

  # Find selected index
  WIZ_SELECTED_INDEX=0
  for i in "${!options[@]}"; do
    if [[ ${options[$i]} == "$result" ]]; then
      WIZ_SELECTED_INDEX=$i
      break
    fi
  done

  printf "%s" "$result"
}

# Prompts for multi-selection.
# Parameters:
#   $1 - Header/question text
#   $@ - Remaining args: list of options
# Returns: Selected options (newline-separated) via stdout
# wiz_choose_multi prompts the user to select multiple options with gum, prints the newline-separated selections to stdout, and sets the global WIZ_SELECTED_INDICES array to the 0-based indices of the chosen options.
wiz_choose_multi() {
  local header="$1"
  shift
  local options=("$@")

  local result
  result=$(gum choose \
    --header "$header" \
    --no-limit \
    --cursor "› " \
    --cursor.foreground "$GUM_ACCENT" \
    --selected.foreground "$GUM_SUCCESS" \
    --header.foreground "$GUM_MUTED" \
    --height 12 \
    "${options[@]}")

  # Build array of selected indices
  WIZ_SELECTED_INDICES=()
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    for i in "${!options[@]}"; do
      if [[ ${options[$i]} == "$line" ]]; then
        WIZ_SELECTED_INDICES+=("$i")
        break
      fi
    done
  done <<<"$result"

  printf "%s" "$result"
}

# Prompts for yes/no confirmation.
# Parameters:
#   $1 - Question text
# wiz_confirm prompts the user with a yes/no confirmation using gum.
# Returns exit code 0 if the user confirms (yes), non-zero otherwise.
wiz_confirm() {
  local question="$1"

  gum confirm \
    --prompt.foreground "$GUM_PRIMARY" \
    --selected.background "$GUM_ACCENT" \
    --selected.foreground "#000000" \
    --unselected.background "$GUM_MUTED" \
    --unselected.foreground "#FFFFFF" \
    "$question"
}

# Displays spinner while running a command.
# Parameters:
#   $1 - Title/message
#   $@ - Remaining args: command to run
# wiz_spin displays a styled spinner with the given title while running the provided command and returns the command's exit code.
wiz_spin() {
  local title="$1"
  shift

  gum spin \
    --spinner points \
    --spinner.foreground "$GUM_ACCENT" \
    --title "$title" \
    --title.foreground "$GUM_PRIMARY" \
    -- "$@"
}

# Displays styled message.
# Parameters:
#   $1 - Type: "error", "warning", "success", "info"
#   $2 - Message text
# wiz_msg displays a styled message prefixed by an icon determined by `type` ("error", "warning", "success", "info", or default) and prints it with the corresponding color.
wiz_msg() {
  local type="$1"
  local msg="$2"
  local color icon

  case "$type" in
    error)
      color="$GUM_ERROR"
      icon="✗"
      ;;
    warning)
      color="$GUM_WARNING"
      icon="⚠"
      ;;
    success)
      color="$GUM_SUCCESS"
      icon="✓"
      ;;
    info)
      color="$GUM_PRIMARY"
      icon="ℹ"
      ;;
    *)
      color="$GUM_MUTED"
      icon="•"
      ;;
  esac

  gum style --foreground "$color" "$icon $msg"
}

# =============================================================================
# Navigation handling
# =============================================================================

# Waits for navigation keypress.
# wiz_wait_nav waits for a navigation keypress and prints one of "next", "back", or "quit" to stdout.
wiz_wait_nav() {
  local key
  while true; do
    IFS= read -rsn1 key
    case "$key" in
      "" | $'\n')
        echo "next"
        return
        ;;
      "b" | "B")
        echo "back"
        return
        ;;
      "q" | "Q")
        echo "quit"
        return
        ;;
      $'\x1b')
        # Consume escape sequence (arrow keys, etc.)
        read -rsn2 -t 0.1 _ || true
        ;;
    esac
  done
}

# Handles quit confirmation.
# wiz_handle_quit prompts the user to confirm quitting and handles the response.
# If the user confirms, clears the screen, prints an error-styled "Installation cancelled." message and exits with status 1; otherwise returns with status 1.
wiz_handle_quit() {
  echo ""
  if wiz_confirm "Are you sure you want to quit?"; then
    clear
    gum style --foreground "$GUM_ERROR" "Installation cancelled."
    exit 1
  fi
  return 1
}
