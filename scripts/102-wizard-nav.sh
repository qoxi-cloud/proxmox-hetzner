# shellcheck shell=bash
# Configuration Wizard - Navigation Header and Key Input
# Screen navigation, header rendering, and keyboard handling

# Screen definitions

# Screen names for navigation
WIZ_SCREENS=("Basic" "Proxmox" "Network" "Storage" "Services" "Access")
WIZ_CURRENT_SCREEN=0

# Navigation column width
_NAV_COL_WIDTH=10

# Navigation header helpers

# Center text (strips ANSI for width calc). $1=text → centered text
_wiz_center() {
  local text="$1"
  local term_width
  term_width=$(tput cols 2>/dev/null || echo 80)

  # Strip ANSI escape codes to get visible length
  local visible_text
  visible_text=$(printf '%s' "$text" | sed 's/\x1b\[[0-9;]*m//g')
  local text_len=${#visible_text}

  # Calculate padding
  local padding=$(((term_width - text_len) / 2))
  ((padding < 0)) && padding=0

  # Print padding + text
  printf '%*s%s' "$padding" "" "$text"
}

# Repeat character N times. $1=char, $2=count
_nav_repeat() {
  local char="$1" count="$2" i
  for ((i = 0; i < count; i++)); do
    printf '%s' "$char"
  done
}

# Get nav color for screen state. $1=screen_idx, $2=current_idx → color
_nav_color() {
  local idx="$1" current="$2"
  if [[ $idx -eq $current ]]; then
    printf '%s\n' "$CLR_ORANGE"
  elif [[ $idx -lt $current ]]; then
    printf '%s\n' "$CLR_CYAN"
  else
    printf '%s\n' "$CLR_GRAY"
  fi
}

# Get nav dot for screen state. $1=screen_idx, $2=current_idx → ◉/●/○
_nav_dot() {
  local idx="$1" current="$2"
  if [[ $idx -eq $current ]]; then
    printf '%s\n' "◉"
  elif [[ $idx -lt $current ]]; then
    printf '%s\n' "●"
  else
    printf '%s\n' "○"
  fi
}

# Get nav line style. $1=screen_idx, $2=current_idx, $3=length → ━━━/───
_nav_line() {
  local idx="$1" current="$2" len="$3"
  if [[ $idx -lt $current ]]; then
    _nav_repeat "━" "$len"
  else
    _nav_repeat "─" "$len"
  fi
}

# Renders the screen navigation header with wizard-style dots.
# Shows: screen names row + dots with connecting lines row.
# Uses: CLR_CYAN for completed, CLR_ORANGE for active, CLR_GRAY for pending.
_wiz_render_nav() {
  local current=$WIZ_CURRENT_SCREEN
  local total=${#WIZ_SCREENS[@]}
  local col=$_NAV_COL_WIDTH

  # Calculate padding to center relative to terminal width
  local nav_width=$((col * total))
  local pad_left=$(((TERM_WIDTH - nav_width) / 2))
  local padding=""
  ((pad_left > 0)) && padding=$(printf '%*s' $pad_left '')

  # Screen names row
  local labels="$padding"
  for i in "${!WIZ_SCREENS[@]}"; do
    local name="${WIZ_SCREENS[$i]}"
    local name_len=${#name}
    local pad_left=$(((col - name_len) / 2))
    local pad_right=$((col - name_len - pad_left))
    local centered
    centered=$(printf '%*s%s%*s' $pad_left '' "$name" $pad_right '')
    labels+="$(_nav_color "$i" "$current")${centered}${CLR_RESET}"
  done

  # Dots with connecting lines row
  local dots="$padding"
  local center_pad=$(((col - 1) / 2))
  local right_pad=$((col - center_pad - 1))

  for i in "${!WIZ_SCREENS[@]}"; do
    local color line_color dot
    color=$(_nav_color "$i" "$current")
    dot=$(_nav_dot "$i" "$current")

    if [[ $i -eq 0 ]]; then
      # First: pad + dot + line_right
      dots+=$(printf '%*s' $center_pad '')
      dots+="${color}${dot}${CLR_RESET}"
      # Line after first dot uses current dot's completion state
      local line_clr
      line_clr=$([[ $i -lt $current ]] && echo "$CLR_CYAN" || echo "$CLR_GRAY")
      dots+="${line_clr}$(_nav_line "$i" "$current" "$right_pad")${CLR_RESET}"
    elif [[ $i -eq $((total - 1)) ]]; then
      # Last: line_left + dot
      local prev_line_clr
      prev_line_clr=$([[ $((i - 1)) -lt $current ]] && echo "$CLR_CYAN" || echo "$CLR_GRAY")
      dots+="${prev_line_clr}$(_nav_line "$((i - 1))" "$current" "$center_pad")${CLR_RESET}"
      dots+="${color}${dot}${CLR_RESET}"
    else
      # Middle: line_left + dot + line_right
      local prev_line_clr
      prev_line_clr=$([[ $((i - 1)) -lt $current ]] && echo "$CLR_CYAN" || echo "$CLR_GRAY")
      dots+="${prev_line_clr}$(_nav_line "$((i - 1))" "$current" "$center_pad")${CLR_RESET}"
      dots+="${color}${dot}${CLR_RESET}"
      local next_line_clr
      next_line_clr=$([[ $i -lt $current ]] && echo "$CLR_CYAN" || echo "$CLR_GRAY")
      dots+="${next_line_clr}$(_nav_line "$i" "$current" "$right_pad")${CLR_RESET}"
    fi
  done

  printf '%s\n%s\n' "$labels" "$dots"
}

# Key reading

# Read single key press (arrow keys → WIZ_KEY: up/down/left/right/enter/quit/esc)
_wiz_read_key() {
  local key
  IFS= read -rsn1 key

  # Handle escape sequences (arrow keys)
  if [[ $key == $'\x1b' ]]; then
    read -rsn2 -t 0.1 key
    case "$key" in
      '[A') WIZ_KEY="up" ;;
      '[B') WIZ_KEY="down" ;;
      '[C') WIZ_KEY="right" ;;
      '[D') WIZ_KEY="left" ;;
      *) WIZ_KEY="esc" ;;
    esac
  elif [[ $key == "" ]]; then
    WIZ_KEY="enter"
  elif [[ $key == "q" || $key == "Q" ]]; then
    WIZ_KEY="quit"
  elif [[ $key == "s" || $key == "S" ]]; then
    WIZ_KEY="start"
  else
    WIZ_KEY="$key"
  fi
}
