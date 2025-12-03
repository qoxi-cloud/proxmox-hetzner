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
# Returns: User input via stdout
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

    [[ -n "$default" ]] && args+=(--value "$default")
    [[ -n "$placeholder" ]] && args+=(--placeholder "$placeholder")
    [[ "$password" == "true" ]] && args+=(--password)

    gum input "${args[@]}"
}

# Prompts for selection from a list.
# Parameters:
#   $1 - Header/question text
#   $@ - Remaining args: list of options
# Returns: Selected option via stdout
# Side effects: Sets WIZ_SELECTED_INDEX global (0-based)
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
        if [[ "${options[$i]}" == "$result" ]]; then
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
# Side effects: Sets WIZ_SELECTED_INDICES array global
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
        [[ -z "$line" ]] && continue
        for i in "${!options[@]}"; do
            if [[ "${options[$i]}" == "$line" ]]; then
                WIZ_SELECTED_INDICES+=("$i")
                break
            fi
        done
    done <<< "$result"

    printf "%s" "$result"
}

# Prompts for yes/no confirmation.
# Parameters:
#   $1 - Question text
# Returns: Exit code 0=yes, 1=no
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
# Returns: Exit code of the command
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
# Side effects: Outputs styled message
wiz_msg() {
    local type="$1"
    local msg="$2"
    local color icon

    case "$type" in
        error)   color="$GUM_ERROR";   icon="✗" ;;
        warning) color="$GUM_WARNING"; icon="⚠" ;;
        success) color="$GUM_SUCCESS"; icon="✓" ;;
        info)    color="$GUM_PRIMARY"; icon="ℹ" ;;
        *)       color="$GUM_MUTED";   icon="•" ;;
    esac

    gum style --foreground "$color" "$icon $msg"
}

# =============================================================================
# Navigation handling
# =============================================================================

# Waits for navigation keypress.
# Returns: "next", "back", or "quit" via stdout
wiz_wait_nav() {
    local key
    while true; do
        IFS= read -rsn1 key
        case "$key" in
            ""|$'\n')
                echo "next"
                return
                ;;
            "b"|"B")
                echo "back"
                return
                ;;
            "q"|"Q")
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
# Returns: Exit code 0 if user confirms quit, 1 otherwise
wiz_handle_quit() {
    echo ""
    if wiz_confirm "Are you sure you want to quit?"; then
        clear
        gum style --foreground "$GUM_ERROR" "Installation cancelled."
        exit 1
    fi
    return 1
}
