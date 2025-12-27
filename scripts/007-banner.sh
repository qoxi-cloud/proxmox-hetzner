# shellcheck shell=bash
# Banner display
# Note: cursor cleanup is handled by cleanup_and_error_handler in 00-init.sh

# Banner letter count for animation (P=0, r=1, o=2, x=3, m=4, o=5, x=6)
BANNER_LETTER_COUNT=7

# Banner height in lines (6 ASCII art + 1 empty + 1 tagline = 8, +1 for spacing = 9)
BANNER_HEIGHT=9

# Calculate banner padding from TERM_WIDTH and BANNER_WIDTH constants
_BANNER_PAD_SIZE=$(((TERM_WIDTH - BANNER_WIDTH) / 2))
printf -v _BANNER_PAD '%*s' "$_BANNER_PAD_SIZE" ''

# Display main ASCII banner
show_banner() {
  local p="$_BANNER_PAD"
  local tagline="${CLR_CYAN}Qoxi ${CLR_GRAY}Automated Installer ${CLR_GOLD}${VERSION}${CLR_RESET}"
  # Center the tagline within banner width
  local text="Qoxi Automated Installer ${VERSION}"
  local pad=$(((BANNER_WIDTH - ${#text}) / 2))
  local spaces
  printf -v spaces '%*s' "$pad" ''
  printf '%s\n' \
    "${p}${CLR_GRAY} _____                                             ${CLR_RESET}" \
    "${p}${CLR_GRAY}|  __ \\                                            ${CLR_RESET}" \
    "${p}${CLR_GRAY}| |__) | _ __   ___  ${CLR_ORANGE}__  __${CLR_GRAY}  _ __ ___    ___  ${CLR_ORANGE}__  __${CLR_RESET}" \
    "${p}${CLR_GRAY}|  ___/ | '__| / _ \\ ${CLR_ORANGE}\\ \\/ /${CLR_GRAY} | '_ \` _ \\  / _ \\ ${CLR_ORANGE}\\ \\/ /${CLR_RESET}" \
    "${p}${CLR_GRAY}| |     | |   | (_) |${CLR_ORANGE} >  <${CLR_GRAY}  | | | | | || (_) |${CLR_ORANGE} >  <${CLR_RESET}" \
    "${p}${CLR_GRAY}|_|     |_|    \\___/ ${CLR_ORANGE}/_/\\_\\${CLR_GRAY} |_| |_| |_| \\___/ ${CLR_ORANGE}/_/\\_\\${CLR_RESET}" \
    "" \
    "${p}${spaces}${tagline}"
}

# Display banner frame with highlighted letter. $1=letter_idx (0-6, -1=none)
_show_banner_frame() {
  local h="${1:--1}"
  local M="${CLR_GRAY}"
  local A="${CLR_ORANGE}"
  local R="${CLR_RESET}"
  local p="$_BANNER_PAD"

  # Line 1: _____ is top of P
  local line1="${p}${M} "
  [[ $h -eq 0 ]] && line1+="${A}_____${M}" || line1+="_____"
  line1+="                                             ${R}"

  # Line 2: |  __ \
  local line2="${p}${M}"
  [[ $h -eq 0 ]] && line2+="${A}|  __ \\${M}" || line2+='|  __ \'
  line2+="                                            ${R}"

  # Line 3: | |__) | _ __   ___  __  __  _ __ ___    ___  __  __
  local line3="${p}${M}"
  [[ $h -eq 0 ]] && line3+="${A}| |__) |${M}" || line3+="| |__) |"
  [[ $h -eq 1 ]] && line3+=" ${A}_ __${M}" || line3+=" _ __"
  [[ $h -eq 2 ]] && line3+="   ${A}___${M}" || line3+="   ___"
  [[ $h -eq 3 ]] && line3+="  ${A}__  __${M}" || line3+="  __  __"
  [[ $h -eq 4 ]] && line3+="  ${A}_ __ ___${M}" || line3+="  _ __ ___"
  [[ $h -eq 5 ]] && line3+="    ${A}___${M}" || line3+="    ___"
  [[ $h -eq 6 ]] && line3+="  ${A}__  __${M}" || line3+="  __  __"
  line3+="${R}"

  # Line 4: |  ___/ | '__| / _ \ \ \/ / | '_ ` _ \  / _ \ \ \/ /
  local line4="${p}${M}"
  [[ $h -eq 0 ]] && line4+="${A}|  ___/ ${M}" || line4+="|  ___/ "
  [[ $h -eq 1 ]] && line4+="${A}| '__|${M}" || line4+="| '__|"
  [[ $h -eq 2 ]] && line4+=" ${A}/ _ \\${M}" || line4+=' / _ \'
  [[ $h -eq 3 ]] && line4+=" ${A}\\ \\/ /${M}" || line4+=' \ \/ /'
  [[ $h -eq 4 ]] && line4+=" ${A}| '_ \` _ \\${M}" || line4+=" | '_ \` _ \\"
  [[ $h -eq 5 ]] && line4+="  ${A}/ _ \\${M}" || line4+='  / _ \'
  [[ $h -eq 6 ]] && line4+=" ${A}\\ \\/ /${M}" || line4+=' \ \/ /'
  line4+="${R}"

  # Line 5: | |     | |   | (_) | >  <  | | | | | || (_) | >  <
  local line5="${p}${M}"
  [[ $h -eq 0 ]] && line5+="${A}| |     ${M}" || line5+="| |     "
  [[ $h -eq 1 ]] && line5+="${A}| |${M}" || line5+="| |"
  [[ $h -eq 2 ]] && line5+="   ${A}| (_) |${M}" || line5+="   | (_) |"
  [[ $h -eq 3 ]] && line5+="${A} >  <${M}" || line5+=" >  <"
  [[ $h -eq 4 ]] && line5+="  ${A}| | | | | |${M}" || line5+="  | | | | | |"
  [[ $h -eq 5 ]] && line5+="${A}| (_) |${M}" || line5+="| (_) |"
  [[ $h -eq 6 ]] && line5+="${A} >  <${M}" || line5+=" >  <"
  line5+="${R}"

  # Line 6: |_|     |_|    \___/ /_/\_\ |_| |_| |_| \___/ /_/\_\
  local line6="${p}${M}"
  [[ $h -eq 0 ]] && line6+="${A}|_|     ${M}" || line6+="|_|     "
  [[ $h -eq 1 ]] && line6+="${A}|_|${M}" || line6+="|_|"
  [[ $h -eq 2 ]] && line6+="    ${A}\\___/${M}" || line6+='    \___/'
  [[ $h -eq 3 ]] && line6+=" ${A}/_/\\_\\${M}" || line6+=' /_/\_\'
  [[ $h -eq 4 ]] && line6+=" ${A}|_| |_| |_|${M}" || line6+=" |_| |_| |_|"
  [[ $h -eq 5 ]] && line6+=" ${A}\\___/${M}" || line6+=' \___/'
  [[ $h -eq 6 ]] && line6+=" ${A}/_/\\_\\${M}" || line6+=' /_/\_\'
  line6+="${R}"

  # Tagline (centered within banner width)
  local text="Qoxi Automated Installer ${VERSION}"
  local pad=$(((BANNER_WIDTH - ${#text}) / 2))
  local spaces
  printf -v spaces '%*s' "$pad" ''
  local line_tagline="${p}${spaces}${CLR_CYAN}Qoxi ${M}Automated Installer ${CLR_GOLD}${VERSION}${R}"

  # Output all lines atomically to prevent interference
  # Build the entire frame first, then output it all at once
  local frame
  frame=$(printf '\033[H\033[J%s\n%s\n%s\n%s\n%s\n%s\n\n%s\n' \
    "$line1" \
    "$line2" \
    "$line3" \
    "$line4" \
    "$line5" \
    "$line6" \
    "$line_tagline")

  # Output the entire frame at once
  printf '%s' "$frame"
}

# Background animation control

# PID of background animation process
BANNER_ANIMATION_PID=""

# Start animated banner in background. $1=frame_delay (default 0.1)
show_banner_animated_start() {
  local frame_delay="${1:-0.1}"

  # Skip animation in non-interactive environments
  [[ ! -t 1 ]] && return

  # Kill any existing animation
  show_banner_animated_stop 2>/dev/null

  # Hide cursor
  _wiz_hide_cursor

  # Clear screen once
  clear

  # Start animation in background subshell
  (
    local direction=1
    local current_letter=0

    # Trap to ensure clean exit and handle window resize
    trap 'exit 0' TERM INT
    trap 'clear' WINCH

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

# Stop background animated banner, show static banner
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
  _wiz_show_cursor
}
