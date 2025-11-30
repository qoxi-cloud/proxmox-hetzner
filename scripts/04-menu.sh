# shellcheck shell=bash
# =============================================================================
# Interactive menu selection
# =============================================================================
# Usage: interactive_menu "Title" "header_content" "label1|desc1" "label2|desc2" ...
# Sets: MENU_SELECTED (0-based index of selected option)
# Fixed width: 60 characters for consistent appearance

MENU_BOX_WIDTH=60

interactive_menu() {
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

        # Add header content if provided
        if [[ -n "$header" ]]; then
            content+="$header"$'\n'
            content+=""$'\n'
        fi

        # Add options
        for i in "${!labels[@]}"; do
            if [ $i -eq $selected ]; then
                content+="[*] ${labels[$i]}"$'\n'
                [[ -n "${descriptions[$i]}" ]] && content+="    └─ ${descriptions[$i]}"$'\n'
            else
                content+="[ ] ${labels[$i]}"$'\n'
                [[ -n "${descriptions[$i]}" ]] && content+="    └─ ${descriptions[$i]}"$'\n'
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
    # - Box frame in blue, [●] selected (green), [○] unselected (blue)
    # - Lines with "! " are warnings (yellow)
    _colorize_menu() {
        sed -e $'s/\\[\\*\\]/\033[1;32m[●]\033[1;34m/g' \
            -e $'s/\\[ \\]/\033[1;34m[○]\033[1;34m/g' \
            -e $'s/^\\(+[-+]*+\\)$/\033[1;34m\\1\033[m/g' \
            -e $'s/^|/\033[1;34m|/g' \
            -e $'s/|$/|\033[m/g' \
            -e $'s/! /\033[1;33m! /g' \
            -e $'s/  - /\033[1;33m  - /g'
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

# Display an input box and prompt for value
# Usage: input_box "title" "content" "prompt" "default" -> result in INPUT_VALUE
input_box() {
    local title="$1"
    local content="$2"
    local prompt="$3"
    local default="$4"

    local box_lines
    box_lines=$({
        echo "$title"
        echo "$content"
    } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH | wc -l)

    {
        echo "$title"
        echo "$content"
    } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH

    read -e -p "$prompt" -i "$default" INPUT_VALUE

    # Clear the input box
    tput cuu $((box_lines + 1))
    for ((i=0; i<box_lines+1; i++)); do
        printf "\033[2K\n"
    done
    tput cuu $((box_lines + 1))
}
