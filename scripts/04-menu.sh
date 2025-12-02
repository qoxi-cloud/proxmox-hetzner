# shellcheck shell=bash
# =============================================================================
# Interactive menu selection (radio buttons - single select)
# =============================================================================
# Usage: radio_menu "Title" "header_content" "label1|desc1" "label2|desc2" ...
# Sets: MENU_SELECTED (0-based index of selected option)
# Fixed width: 60 characters for consistent appearance

MENU_BOX_WIDTH=60

# Internal helper: wraps text to fit within box width.
# Parameters:
#   $1 - Text to wrap
#   $2 - Prefix for continuation lines
#   $3 - Maximum width
# Returns: Wrapped text via stdout
_wrap_text() {
    local text="$1"
    local prefix="$2"
    local max_width="$3"
    local result=""
    local line=""
    local first_line=true

    # Split text into words
    for word in $text; do
        if [[ -z "$line" ]]; then
            line="$word"
        elif [[ $((${#line} + 1 + ${#word})) -le $max_width ]]; then
            line+=" $word"
        else
            if [[ "$first_line" == true ]]; then
                result+="$line"$'\n'
                first_line=false
            else
                result+="${prefix}${line}"$'\n'
            fi
            line="$word"
        fi
    done

    # Add remaining text
    if [[ -n "$line" ]]; then
        if [[ "$first_line" == true ]]; then
            result+="$line"
        else
            result+="${prefix}${line}"
        fi
    fi

    echo "$result"
}

# Displays interactive radio menu for single selection.
# Parameters:
#   $1 - Menu title
#   $2 - Header content
#   $@ - Items in format "label|description"
# Side effects: Sets MENU_SELECTED global (0-based index)
radio_menu() {
    local title="$1"
    local header="$2"
    shift 2
    local items=("$@")

    local -a labels=()
    local -a descriptions=()

    # Parse items into labels and descriptions
    for item in "${items[@]}"; do
        labels+=("${item%%|*}")
        descriptions+=("${item#*|}")
    done

    local selected=0
    local key=""
    local box_lines=0
    local num_options=${#labels[@]}

    # Function to draw the menu box with fixed width
    _draw_menu() {
        local content=""
        # Inner width: box_width - 4 (borders) - 2 (padding) = 54
        # Description prefix "    └─ " is 7 chars, so max desc width is 47
        local desc_max_width=47
        local desc_prefix="       "  # 7 spaces for continuation lines

        # Add header content if provided
        if [[ -n "$header" ]]; then
            content+="$header"$'\n'
        fi

        # Add options
        for i in "${!labels[@]}"; do
            if [ $i -eq $selected ]; then
                content+="[*] ${labels[$i]}"$'\n'
                if [[ -n "${descriptions[$i]}" ]]; then
                    local wrapped_desc
                    wrapped_desc=$(_wrap_text "${descriptions[$i]}" "$desc_prefix" "$desc_max_width")
                    content+="    └─ ${wrapped_desc}"$'\n'
                fi
            else
                content+="[ ] ${labels[$i]}"$'\n'
                if [[ -n "${descriptions[$i]}" ]]; then
                    local wrapped_desc
                    wrapped_desc=$(_wrap_text "${descriptions[$i]}" "$desc_prefix" "$desc_max_width")
                    content+="    └─ ${wrapped_desc}"$'\n'
                fi
            fi
        done

        # Remove trailing newline
        content="${content%$'\n'}"

        {
            echo "$title"
            echo "$content"
        } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH
    }

    # Hide cursor
    tput civis

    # Calculate box height
    box_lines=$(_draw_menu | wc -l)

    # Colorize menu output
    # - Box frame and [○] in cyan, [●] green, text white
    # - Lines with "! " and key info are warnings (yellow)
    _colorize_menu() {
        while IFS= read -r line; do
            # Top/bottom border
            if [[ "$line" =~ ^\+[-+]+\+$ ]]; then
                echo "${CLR_GRAY}${line}${CLR_RESET}"
            # Content line with | borders
            elif [[ "$line" =~ ^(\|)(.*)\|$ ]]; then
                local content="${BASH_REMATCH[2]}"
                # Apply content colors
                # Yellow for warnings and info lines (apply BEFORE checkbox colors)
                if [[ "$content" == *"! "* ]]; then
                    content="${content//! /${CLR_YELLOW}⚠️ }"
                    # Remove one trailing space to compensate for emoji width
                    content="${content% }"
                    content="${content}${CLR_RESET}"
                fi
                # Lines starting with "  - " should be entirely yellow
                if [[ "$content" =~ ^(.*)\ \ -\ (.*)$ ]]; then
                    local prefix="${BASH_REMATCH[1]}"
                    local rest="${BASH_REMATCH[2]}"
                    content="${prefix}${CLR_YELLOW}  - ${rest}${CLR_RESET}"
                fi
                content="${content//Detected key from Rescue System:/${CLR_YELLOW}Detected key from Rescue System:${CLR_RESET}}"
                content="${content//Type:/${CLR_YELLOW}Type:${CLR_RESET}}"
                content="${content//Key:/${CLR_YELLOW}Key:${CLR_RESET}}"
                content="${content//Comment:/${CLR_YELLOW}Comment:${CLR_RESET}}"
                # Checkbox colors (apply AFTER yellow to ensure correct colors)
                content="${content//\[\*\]/${CLR_ORANGE}[●]${CLR_RESET}}"
                content="${content//\[ \]/${CLR_GRAY}[○]${CLR_RESET}}"
                echo "${CLR_GRAY}|${CLR_RESET}${content}${CLR_GRAY}|${CLR_RESET}"
            else
                echo "$line"
            fi
        done
    }

    # Draw initial menu
    _draw_menu | _colorize_menu

    while true; do
        # Read a single keypress
        IFS= read -rsn1 key

        # Check for escape sequence (arrow keys)
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key || true
            case "$key" in
                '[A') # Up arrow
                    ((selected--)) || true
                    [ $selected -lt 0 ] && selected=$((num_options - 1))
                    ;;
                '[B') # Down arrow
                    ((selected++)) || true
                    [ $selected -ge $num_options ] && selected=0
                    ;;
            esac
        elif [[ "$key" == "" ]]; then
            # Enter pressed - confirm selection
            break
        elif [[ "$key" =~ ^[1-9]$ ]] && [ "$key" -le "$num_options" ]; then
            # Number key pressed
            selected=$((key - 1))
            break
        fi

        # Move cursor up to redraw menu (fixes scroll issue)
        tput cuu $box_lines

        # Clear lines and redraw
        for ((i=0; i<box_lines; i++)); do
            printf "\033[2K\n"
        done
        tput cuu $box_lines

        # Draw the menu with colors
        _draw_menu | _colorize_menu
    done

    # Show cursor again
    tput cnorm

    # Clear the menu box
    tput cuu $box_lines
    for ((i=0; i<box_lines; i++)); do
        printf "\033[2K\n"
    done
    tput cuu $box_lines

    # Set result
    MENU_SELECTED=$selected
}

# Displays input box and prompts for value.
# Parameters:
#   $1 - Box title
#   $2 - Content/description
#   $3 - Input prompt text
#   $4 - Default value
# Side effects: Sets INPUT_VALUE global
input_box() {
    local title="$1"
    local content="$2"
    local prompt="$3"
    local default="$4"

    # Colorize input box: cyan frame, yellow text
    _colorize_input_box() {
        while IFS= read -r line; do
            # Top/bottom border (lines with + and -)
            if [[ "$line" =~ ^\+[-+]+\+$ ]]; then
                echo -e "${CLR_GRAY}${line}${CLR_RESET}"
            # Content line with | borders
            elif [[ "$line" =~ ^(\|)(.*)\|$ ]]; then
                local content="${BASH_REMATCH[2]}"
                echo -e "${CLR_GRAY}|${CLR_RESET}${CLR_YELLOW}${content}${CLR_RESET}${CLR_GRAY}|${CLR_RESET}"
            else
                echo "$line"
            fi
        done
    }

    local box_lines
    box_lines=$({
        echo "$title"
        echo "$content"
    } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH | wc -l)

    {
        echo "$title"
        echo "$content"
    } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH | _colorize_input_box

    read -r -e -p "$prompt" -i "$default" INPUT_VALUE

    # Clear the input box
    tput cuu $((box_lines + 1))
    for ((i=0; i<box_lines+1; i++)); do
        printf "\033[2K\n"
    done
    tput cuu $((box_lines + 1))
}

# =============================================================================
# Interactive checkbox menu (multi-select)
# =============================================================================

# Displays interactive checkbox menu for multiple selection.
# Parameters:
#   $1 - Menu title
#   $2 - Header content
#   $@ - Items in format "label|description|default" (default: 1=checked, 0=unchecked)
# Navigation: Space toggles selection, Enter confirms
# Side effects: Sets CHECKBOX_RESULTS array (1=selected, 0=not selected)
checkbox_menu() {
    local title="$1"
    local header="$2"
    shift 2
    local items=("$@")

    local -a labels=()
    local -a descriptions=()
    local -a selected_states=()

    # Parse items into labels, descriptions, and default states
    for item in "${items[@]}"; do
        local label="${item%%|*}"
        local rest="${item#*|}"
        local desc="${rest%%|*}"
        local default_state="${rest##*|}"
        labels+=("$label")
        descriptions+=("$desc")
        selected_states+=("${default_state:-0}")
    done

    local cursor=0
    local key=""
    local box_lines=0
    local num_options=${#labels[@]}

    # Function to draw the checkbox menu
    _draw_checkbox_menu() {
        local content=""
        # Inner width: box_width - 4 (borders) - 2 (padding) = 54
        # Description prefix "       └─ " is 10 chars, so max desc width is 44
        local desc_max_width=44
        local desc_prefix="          "  # 10 spaces for continuation lines

        # Add header content if provided
        if [[ -n "$header" ]]; then
            content+="$header"$'\n'
        fi

        # Add options with checkboxes
        for i in "${!labels[@]}"; do
            local checkbox
            if [[ "${selected_states[$i]}" == "1" ]]; then
                checkbox="[x]"
            else
                checkbox="[ ]"
            fi

            if [ "$i" -eq "$cursor" ]; then
                content+="> ${checkbox} ${labels[$i]}"$'\n'
            else
                content+="  ${checkbox} ${labels[$i]}"$'\n'
            fi
            if [[ -n "${descriptions[$i]}" ]]; then
                local wrapped_desc
                wrapped_desc=$(_wrap_text "${descriptions[$i]}" "$desc_prefix" "$desc_max_width")
                content+="       └─ ${wrapped_desc}"$'\n'
            fi
        done

        # Add footer hint
        content+=$'\n'"  Space: toggle, Enter: confirm"

        {
            echo "$title"
            echo "$content"
        } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH
    }

    # Colorize checkbox menu output
    _colorize_checkbox_menu() {
        while IFS= read -r line; do
            # Top/bottom border
            if [[ "$line" =~ ^\+[-+]+\+$ ]]; then
                echo "${CLR_GRAY}${line}${CLR_RESET}"
            # Content line with | borders
            elif [[ "$line" =~ ^(\|)(.*)\|$ ]]; then
                local content="${BASH_REMATCH[2]}"
                # Cursor indicator - orange
                content="${content//> /${CLR_ORANGE}› ${CLR_RESET}}"
                # Checked checkbox - orange (matching radio menu style)
                content="${content//\[x\]/${CLR_ORANGE}[●]${CLR_RESET}}"
                # Unchecked checkbox - gray
                content="${content//\[ \]/${CLR_GRAY}[○]${CLR_RESET}}"
                # Footer hint - gray
                if [[ "$content" == *"Space:"* ]]; then
                    content="${CLR_GRAY}${content}${CLR_RESET}"
                fi
                echo "${CLR_GRAY}|${CLR_RESET}${content}${CLR_GRAY}|${CLR_RESET}"
            else
                echo "$line"
            fi
        done
    }

    # Hide cursor
    tput civis

    # Calculate box height
    box_lines=$(_draw_checkbox_menu | wc -l)

    # Draw initial menu
    _draw_checkbox_menu | _colorize_checkbox_menu

    while true; do
        # Read a single keypress
        IFS= read -rsn1 key

        # Check for escape sequence (arrow keys)
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key || true
            case "$key" in
                '[A') # Up arrow
                    ((cursor--)) || true
                    [ $cursor -lt 0 ] && cursor=$((num_options - 1))
                    ;;
                '[B') # Down arrow
                    ((cursor++)) || true
                    [ "$cursor" -ge "$num_options" ] && cursor=0
                    ;;
            esac
        elif [[ "$key" == " " ]]; then
            # Space pressed - toggle selection
            if [[ "${selected_states[cursor]}" == "1" ]]; then
                selected_states[cursor]=0
            else
                selected_states[cursor]=1
            fi
        elif [[ "$key" == "" ]]; then
            # Enter pressed - confirm selection
            break
        fi

        # Move cursor up to redraw menu
        tput cuu "$box_lines"

        # Clear lines and redraw
        for ((i=0; i<box_lines; i++)); do
            printf "\033[2K\n"
        done
        tput cuu "$box_lines"

        # Draw the menu with colors
        _draw_checkbox_menu | _colorize_checkbox_menu
    done

    # Show cursor again
    tput cnorm

    # Clear the menu box
    tput cuu "$box_lines"
    for ((i=0; i<box_lines; i++)); do
        printf "\033[2K\n"
    done
    tput cuu "$box_lines"

    # Set results array
    CHECKBOX_RESULTS=("${selected_states[@]}")
}
