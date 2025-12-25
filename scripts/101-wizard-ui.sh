# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Core UI Primitives
# =============================================================================
# Gum wrappers, cursor control, and basic styling functions

# Indent for notification content (SSH key info, generated passwords, etc.)
WIZ_NOTIFY_INDENT="   "

# =============================================================================
# Cursor control
# =============================================================================

# Hides terminal cursor.
_wiz_hide_cursor() { printf '\033[?25l'; }

# Shows terminal cursor.
_wiz_show_cursor() { printf '\033[?25h'; }

# =============================================================================
# Basic styling helpers
# =============================================================================

# Outputs a blank line.
_wiz_blank_line() { printf '\n'; }

# Outputs red error-styled text with notification indent and error icon.
# Supports gum style flags (e.g., --bold) before the message.
_wiz_error() {
  local flags=()
  while [[ ${1:-} == --* ]]; do
    flags+=("$1")
    shift
  done
  gum style --foreground "$HEX_RED" "${flags[@]}" "${WIZ_NOTIFY_INDENT}✗ $*"
}

# Outputs yellow warning-styled text with notification indent.
# Supports gum style flags (e.g., --bold) before the message.
_wiz_warn() {
  local flags=()
  while [[ ${1:-} == --* ]]; do
    flags+=("$1")
    shift
  done
  gum style --foreground "$HEX_YELLOW" "${flags[@]}" "${WIZ_NOTIFY_INDENT}$*"
}

# Outputs cyan info-styled text with notification indent and success icon.
# Supports gum style flags (e.g., --bold) before the message.
_wiz_info() {
  local flags=()
  while [[ ${1:-} == --* ]]; do
    flags+=("$1")
    shift
  done
  gum style --foreground "$HEX_CYAN" "${flags[@]}" "${WIZ_NOTIFY_INDENT}✓ $*"
}

# Outputs gray dimmed text with notification indent.
# Supports gum style flags (e.g., --bold) before the message.
_wiz_dim() {
  local flags=()
  while [[ ${1:-} == --* ]]; do
    flags+=("$1")
    shift
  done
  gum style --foreground "$HEX_GRAY" "${flags[@]}" "${WIZ_NOTIFY_INDENT}$*"
}

# Displays a description block for menu screens with inline color support.
# Outputs all lines at once for flicker-free rendering.
# Parameters:
#   $@ - Lines to display, supports {{cyan:text}} syntax for highlights
# Usage: _wiz_description "Line 1" "Line 2" "" "Line with {{cyan:highlight}} or {{yellow:warning}}"
_wiz_description() {
  local output=""
  for line in "$@"; do
    # Replace {{color:text}} with actual color codes
    line="${line//\{\{cyan:/${CLR_CYAN}}"
    line="${line//\{\{yellow:/${CLR_YELLOW}}"
    line="${line//\}\}/${CLR_GRAY}}"
    output+="${CLR_GRAY}${line}${CLR_RESET}\n"
  done
  printf '%b' "$output"
}

# =============================================================================
# Gum wrappers
# =============================================================================

# Gum confirm wrapper with consistent project styling, centered horizontally.
# Parameters: Same as gum confirm
_wiz_confirm() {
  local prompt="$1"
  shift

  # Center the dialog using gum's padding (top right bottom left)
  # Buttons are ~15 chars wide, use max of prompt or button width
  local content_width left_pad
  content_width=$((${#prompt} > 15 ? ${#prompt} : 15))
  left_pad=$(((TERM_WIDTH - content_width) / 2))
  ((left_pad < 0)) && left_pad=0

  # Custom centered footer (matching project style)
  # Print blank lines + footer, then move cursor up so gum draws above
  local footer_text
  footer_text="${CLR_GRAY}[${CLR_ORANGE}←→${CLR_GRAY}] toggle  [${CLR_ORANGE}Enter${CLR_GRAY}] submit  [${CLR_ORANGE}Y${CLR_GRAY}] yes  [${CLR_ORANGE}N${CLR_GRAY}] no${CLR_RESET}"
  _wiz_blank_line
  _wiz_blank_line
  printf '%s\n' "$(_wiz_center "$footer_text")"

  # gum confirm uses 2 lines (prompt + buttons), plus 2 blank + 1 footer = 5 lines up
  tput cuu 5

  gum confirm "$prompt" "$@" \
    --no-show-help \
    --padding "0 0 0 $left_pad" \
    --prompt.foreground "$HEX_ORANGE" \
    --selected.background "$HEX_ORANGE"
}

# Gum choose wrapper for single-select menus with project styling.
# Parameters: Same as gum choose
_wiz_choose() {
  gum choose \
    --padding "0 0 0 1" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --item.foreground "$HEX_WHITE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help \
    "$@"
}

# Gum choose wrapper for multi-select checkboxes (feature toggles).
# Uses no-limit mode with checkmark indicators.
# Parameters: Same as gum choose
_wiz_choose_multi() {
  gum choose \
    --no-limit \
    --padding "0 0 0 1" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --cursor-prefix "◦ " \
    --selected.foreground "$HEX_WHITE" \
    --selected-prefix "${CLR_CYAN}✓${CLR_RESET} " \
    --unselected-prefix "◦ " \
    --no-show-help \
    "$@"
}

# Gum input wrapper for text entry with project styling.
# Parameters: Same as gum input
_wiz_input() {
  gum input \
    --padding "0 0 0 1" \
    --prompt.foreground "$HEX_CYAN" \
    --cursor.foreground "$HEX_ORANGE" \
    --no-show-help \
    "$@"
}

# Gum filter wrapper for searchable lists with project styling.
# Parameters: Same as gum filter
_wiz_filter() {
  gum filter \
    --padding "0 0 0 1" \
    --placeholder "Type to search..." \
    --indicator "›" \
    --height 5 \
    --no-show-help \
    --prompt.foreground "$HEX_CYAN" \
    --indicator.foreground "$HEX_ORANGE" \
    --match.foreground "$HEX_ORANGE" \
    "$@"
}

# =============================================================================
# Screen helpers
# =============================================================================

# Clears screen using ANSI escape (faster than clear command).
_wiz_clear() {
  printf '\033[H\033[J'
}

# Clears screen and shows banner for edit screens.
# Common pattern used at start of field editor functions.
_wiz_start_edit() {
  _wiz_clear
  show_banner
  _wiz_blank_line
}

# Prepares screen for input with optional description lines.
# Clears screen, shows banner, displays description, and adds footer.
# Parameters:
#   $@ - Optional description lines to display above input
_wiz_input_screen() {
  _wiz_start_edit
  # Show description lines if provided
  for line in "$@"; do
    _wiz_dim "$line"
  done
  [[ $# -gt 0 ]] && printf '\n'
  _show_input_footer
}

# =============================================================================
# Value formatting
# =============================================================================

# Format value for display - shows placeholder if empty
# Parameters:
#   $1 - value to display
#   $2 - placeholder text (default: "→ set value")
_wiz_fmt() {
  local value="$1"
  local placeholder="${2:-→ set value}"
  if [[ -n $value ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "${CLR_GRAY}${placeholder}${CLR_RESET}"
  fi
}
