# shellcheck shell=bash
# =============================================================================
# Banner display
# Note: cursor cleanup is handled by cleanup_and_error_handler in 00-init.sh
# =============================================================================

# Banner letter count for animation (P=0, r=1, o=2, x=3, m=4, o=5, x=6)
BANNER_LETTER_COUNT=7

# ANSI escape codes for banner animation
ANSI_CURSOR_HIDE=$'\033[?25l'
ANSI_CURSOR_SHOW=$'\033[?25h'

# Display main ASCII banner
# Usage: show_banner
show_banner() {
  printf '%s\n' \
    "" \
    "${CLR_GRAY} _____                                             ${CLR_RESET}" \
    "${CLR_GRAY}|  __ \\                                            ${CLR_RESET}" \
    "${CLR_GRAY}| |__) | _ __   ___  ${CLR_ORANGE}__  __${CLR_GRAY}  _ __ ___    ___  ${CLR_ORANGE}__  __${CLR_RESET}" \
    "${CLR_GRAY}|  ___/ | '__| / _ \\ ${CLR_ORANGE}\\ \\/ /${CLR_GRAY} | '_ \` _ \\  / _ \\ ${CLR_ORANGE}\\ \\/ /${CLR_RESET}" \
    "${CLR_GRAY}| |     | |   | (_) |${CLR_ORANGE} >  <${CLR_GRAY}  | | | | | || (_) |${CLR_ORANGE} >  <${CLR_RESET}" \
    "${CLR_GRAY}|_|     |_|    \\___/ ${CLR_ORANGE}/_/\\_\\${CLR_GRAY} |_| |_| |_| \\___/ ${CLR_ORANGE}/_/\\_\\${CLR_RESET}" \
    "" \
    "${CLR_HETZNER}            Hetzner ${CLR_GRAY}Automated Installer${CLR_RESET}"
}

# Displays animated banner with highlighted letter.
# Parameters:
#   $1 - Letter index to highlight (0-6 for P,r,o,x,m,o,x), -1 for none
# Side effects: Outputs styled banner with one letter highlighted
_show_banner_frame() {
  local h="${1:--1}"
  local M="${CLR_GRAY}"
  local A="${CLR_ORANGE}"
  local R="${CLR_RESET}"

  # Line 1: _____ is top of P
  local line1="${M} "
  [[ $h -eq 0 ]] && line1+="${A}_____${M}" || line1+="_____"
  line1+="                                             ${R}"

  # Line 2: |  __ \
  local line2="${M}"
  [[ $h -eq 0 ]] && line2+="${A}|  __ \\${M}" || line2+='|  __ \'
  line2+="                                            ${R}"

  # Line 3: | |__) | _ __   ___  __  __  _ __ ___    ___  __  __
  local line3="${M}"
  [[ $h -eq 0 ]] && line3+="${A}| |__) |${M}" || line3+="| |__) |"
  [[ $h -eq 1 ]] && line3+=" ${A}_ __${M}" || line3+=" _ __"
  [[ $h -eq 2 ]] && line3+="   ${A}___${M}" || line3+="   ___"
  [[ $h -eq 3 ]] && line3+="  ${A}__  __${M}" || line3+="  __  __"
  [[ $h -eq 4 ]] && line3+="  ${A}_ __ ___${M}" || line3+="  _ __ ___"
  [[ $h -eq 5 ]] && line3+="    ${A}___${M}" || line3+="    ___"
  [[ $h -eq 6 ]] && line3+="  ${A}__  __${M}" || line3+="  __  __"
  line3+="${R}"

  # Line 4: |  ___/ | '__| / _ \ \ \/ / | '_ ` _ \  / _ \ \ \/ /
  local line4="${M}"
  [[ $h -eq 0 ]] && line4+="${A}|  ___/ ${M}" || line4+="|  ___/ "
  [[ $h -eq 1 ]] && line4+="${A}| '__|${M}" || line4+="| '__|"
  [[ $h -eq 2 ]] && line4+=" ${A}/ _ \\${M}" || line4+=' / _ \'
  [[ $h -eq 3 ]] && line4+=" ${A}\\ \\/ /${M}" || line4+=' \ \/ /'
  [[ $h -eq 4 ]] && line4+=" ${A}| '_ \` _ \\${M}" || line4+=" | '_ \` _ \\"
  [[ $h -eq 5 ]] && line4+="  ${A}/ _ \\${M}" || line4+='  / _ \'
  [[ $h -eq 6 ]] && line4+=" ${A}\\ \\/ /${M}" || line4+=' \ \/ /'
  line4+="${R}"

  # Line 5: | |     | |   | (_) | >  <  | | | | | || (_) | >  <
  local line5="${M}"
  [[ $h -eq 0 ]] && line5+="${A}| |     ${M}" || line5+="| |     "
  [[ $h -eq 1 ]] && line5+="${A}| |${M}" || line5+="| |"
  [[ $h -eq 2 ]] && line5+="   ${A}| (_) |${M}" || line5+="   | (_) |"
  [[ $h -eq 3 ]] && line5+="${A} >  <${M}" || line5+=" >  <"
  [[ $h -eq 4 ]] && line5+="  ${A}| | | | | |${M}" || line5+="  | | | | | |"
  [[ $h -eq 5 ]] && line5+="${A}| (_) |${M}" || line5+="| (_) |"
  [[ $h -eq 6 ]] && line5+="${A} >  <${M}" || line5+=" >  <"
  line5+="${R}"

  # Line 6: |_|     |_|    \___/ /_/\_\ |_| |_| |_| \___/ /_/\_\
  local line6="${M}"
  [[ $h -eq 0 ]] && line6+="${A}|_|     ${M}" || line6+="|_|     "
  [[ $h -eq 1 ]] && line6+="${A}|_|${M}" || line6+="|_|"
  [[ $h -eq 2 ]] && line6+="    ${A}\\___/${M}" || line6+='    \___/'
  [[ $h -eq 3 ]] && line6+=" ${A}/_/\\_\\${M}" || line6+=' /_/\_\'
  [[ $h -eq 4 ]] && line6+=" ${A}|_| |_| |_|${M}" || line6+=" |_| |_| |_|"
  [[ $h -eq 5 ]] && line6+=" ${A}\\___/${M}" || line6+=' \___/'
  [[ $h -eq 6 ]] && line6+=" ${A}/_/\\_\\${M}" || line6+=' /_/\_\'
  line6+="${R}"

  # Hetzner line
  local line_hetzner="${CLR_HETZNER}            Hetzner ${M}Automated Installer${R}"

  # Output all lines
  printf '\033[H\033[J' # Move cursor home and clear screen from cursor to end
  printf '%s\n' \
    "" \
    "$line1" \
    "$line2" \
    "$line3" \
    "$line4" \
    "$line5" \
    "$line6" \
    "" \
    "$line_hetzner" \
    ""
}

# =============================================================================
# Background animation control
# =============================================================================

# PID of background animation process
BANNER_ANIMATION_PID=""

# Starts animated banner in background.
# The animation runs until stopped with show_banner_animated_stop().
# Parameters:
#   $1 - Frame delay in seconds (default: 0.1)
# Side effects: Sets BANNER_ANIMATION_PID, clears screen, starts background animation
show_banner_animated_start() {
  local frame_delay="${1:-0.1}"

  # Skip animation in non-interactive environments
  [[ ! -t 1 ]] && return

  # Kill any existing animation
  show_banner_animated_stop 2>/dev/null

  # Hide cursor
  printf '%s' "$ANSI_CURSOR_HIDE"

  # Clear screen once
  clear

  # Start animation in background subshell
  (
    local direction=1
    local current_letter=0

    # Trap to ensure clean exit
    trap 'exit 0' TERM INT

    # Redirect any stray output to /dev/null
    exec 3>&1
    exec 1>/dev/tty
    exec 2>/dev/null

    while true; do
      _show_banner_frame "$current_letter"
      sleep "$frame_delay"

      # Move to next letter
      if [[ $direction -eq 1 ]]; then
        ((current_letter++))
        if [[ $current_letter -ge $BANNER_LETTER_COUNT ]]; then
          current_letter=$((BANNER_LETTER_COUNT - 2))
          direction=-1
        fi
      else
        ((current_letter--))
        if [[ $current_letter -lt 0 ]]; then
          current_letter=1
          direction=1
        fi
      fi
    done
  ) &

  BANNER_ANIMATION_PID=$!
}

# Stops background animated banner.
# Shows static banner after stopping animation.
# Side effects: Kills background process, clears BANNER_ANIMATION_PID, shows static banner
show_banner_animated_stop() {
  if [[ -n $BANNER_ANIMATION_PID ]]; then
    # Kill the background process
    kill "$BANNER_ANIMATION_PID" 2>/dev/null
    wait "$BANNER_ANIMATION_PID" 2>/dev/null
    BANNER_ANIMATION_PID=""
  fi

  # Clear screen and show static banner
  clear
  show_banner

  # Restore cursor
  printf '%s' "$ANSI_CURSOR_SHOW"
}

# =============================================================================
# Note: Banner display is handled by 99-main.sh with animated intro
# =============================================================================
