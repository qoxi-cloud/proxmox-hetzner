# shellcheck shell=bash
# =============================================================================
# Gum-based wizard UI for interactive installation
# =============================================================================
# Provides step-by-step wizard interface with progress tracking,
# navigation (Back/Next/Quit), and visual feedback using charmbracelet/gum.
#
# Example visual:
# ┌─────────────────────────────────────────────────────────┐
# │ Step 2/6: Network                                       │
# │ [████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] │
# │                                                         │
# │ ✓ Interface: enp0s31f6                                  │
# │ ✓ Bridge: Internal NAT (vmbr0)                          │
# │ ✓ Private subnet: 10.0.0.0/24                           │
# │ ✓ IPv6: 2a01:4f8::1 (auto)                              │
# │                                                         │
# │ [B] Back  [Enter] Next  [Q] Quit                        │
# └─────────────────────────────────────────────────────────┘

# Wizard configuration
WIZARD_WIDTH=60
WIZARD_TOTAL_STEPS=6

# =============================================================================
# Color configuration
# =============================================================================
# Hex colors for gum commands (gum uses hex format)
# ANSI codes for direct terminal output (instant, no subprocess)
#
# Color mapping from project scheme:
#   CLR_CYAN    -> Primary (UI elements)
#   CLR_ORANGE  -> Accent (highlights, selected items)
#   CLR_YELLOW  -> Warnings
#   CLR_RED     -> Errors
#   CLR_GRAY    -> Muted text, borders
#   CLR_HETZNER -> Hetzner brand red

# Hex colors for gum
# shellcheck disable=SC2034
GUM_PRIMARY="#00B1FF"    # Cyan - primary UI color
GUM_ACCENT="#FF8700"     # Orange - highlights/selected
GUM_SUCCESS="#55FF55"    # Green - success messages
GUM_WARNING="#FFFF55"    # Yellow - warnings
GUM_ERROR="#FF5555"      # Red - errors
GUM_MUTED="#585858"      # Gray - muted text
GUM_BORDER="#444444"     # Dark gray - borders
GUM_HETZNER="#D70000"    # Hetzner brand red

# ANSI escape codes for direct terminal output (instant rendering)
# shellcheck disable=SC2034
ANSI_PRIMARY=$'\033[38;2;0;177;255m'   # #00B1FF
ANSI_ACCENT=$'\033[38;5;208m'          # #FF8700 (256-color)
ANSI_SUCCESS=$'\033[38;2;85;255;85m'   # #55FF55
ANSI_WARNING=$'\033[38;2;255;255;85m'  # #FFFF55
ANSI_ERROR=$'\033[38;2;255;85;85m'     # #FF5555
ANSI_MUTED=$'\033[38;5;240m'           # #585858 (256-color)
ANSI_HETZNER=$'\033[38;5;160m'         # #D70000 (256-color)
ANSI_RESET=$'\033[0m'

# =============================================================================
# Banner display
# =============================================================================

# Displays the Proxmox ASCII banner using ANSI colors.
# Uses direct ANSI codes for instant display (no gum subprocess overhead).
# Side effects: Outputs styled banner to terminal
wiz_banner() {
    printf '%s\n' \
        "" \
        "${ANSI_MUTED}    _____                                             ${ANSI_RESET}" \
        "${ANSI_MUTED}   |  __ \\                                            ${ANSI_RESET}" \
        "${ANSI_MUTED}   | |__) | _ __   ___  ${ANSI_ACCENT}__  __${ANSI_MUTED}  _ __ ___    ___  ${ANSI_ACCENT}__  __${ANSI_RESET}" \
        "${ANSI_MUTED}   |  ___/ | '__| / _ \\ ${ANSI_ACCENT}\\ \\/ /${ANSI_MUTED} | '_ \` _ \\  / _ \\ ${ANSI_ACCENT}\\ \\/ /${ANSI_RESET}" \
        "${ANSI_MUTED}   | |     | |   | (_) |${ANSI_ACCENT} >  <${ANSI_MUTED}  | | | | | || (_) |${ANSI_ACCENT} >  <${ANSI_RESET}" \
        "${ANSI_MUTED}   |_|     |_|    \\___/ ${ANSI_ACCENT}/_/\\_\\${ANSI_MUTED} |_| |_| |_| \\___/ ${ANSI_ACCENT}/_/\\_\\${ANSI_RESET}" \
        "" \
        "${ANSI_HETZNER}               Hetzner ${ANSI_MUTED}Automated Installer${ANSI_RESET}" \
        ""
}

# =============================================================================
# Core wizard display functions
# =============================================================================

# Generates ASCII progress bar.
# Parameters:
#   $1 - Current step (1-based)
#   $2 - Total steps
#   $3 - Bar width (characters)
# Returns: Progress bar string via stdout
_wiz_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"

    local filled=$((width * current / total))
    local empty=$((width - filled))

    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done

    printf "%s" "$bar"
}

# Displays a completed field with checkmark.
# Parameters:
#   $1 - Label text
#   $2 - Value text
# Returns: Formatted line via stdout
_wiz_field() {
    local label="$1"
    local value="$2"

    printf "%s %s %s" \
        "$(gum style --foreground "$GUM_SUCCESS" "✓")" \
        "$(gum style --foreground "$GUM_MUTED" "${label}:")" \
        "$(gum style --foreground "$GUM_PRIMARY" "$value")"
}

# Displays a pending field with empty circle.
# Parameters:
#   $1 - Label text
# Returns: Formatted line via stdout
_wiz_field_pending() {
    local label="$1"

    printf "%s %s %s" \
        "$(gum style --foreground "$GUM_MUTED" "○")" \
        "$(gum style --foreground "$GUM_MUTED" "${label}:")" \
        "$(gum style --foreground "$GUM_MUTED" "...")"
}

# Displays the wizard step box with header, content, and footer.
# Parameters:
#   $1 - Step number (1-based)
#   $2 - Step title
#   $3 - Content (multiline, newline-separated fields)
#   $4 - Show back button (optional, default: true)
# Side effects: Clears screen, outputs styled box
wiz_box() {
    local step="$1"
    local title="$2"
    local content="$3"
    local show_back="${4:-true}"

    # Build header with step indicator and progress bar
    local header
    header="$(gum style --foreground "$GUM_PRIMARY" --bold "Step ${step}/${WIZARD_TOTAL_STEPS}: ${title}")"

    local progress
    progress="$(gum style --foreground "$GUM_MUTED" "$(_wiz_progress_bar "$step" "$WIZARD_TOTAL_STEPS" 53)")"

    # Build footer navigation hints
    local footer=""
    if [[ "$show_back" == "true" && "$step" -gt 1 ]]; then
        footer+="$(gum style --foreground "$GUM_MUTED" "[B] Back")  "
    fi
    footer+="$(gum style --foreground "$GUM_ACCENT" "[Enter] Next")  "
    footer+="$(gum style --foreground "$GUM_MUTED" "[Q] Quit")"

    # Clear screen, show banner, and draw box
    clear
    wiz_banner

    gum style \
        --border rounded \
        --border-foreground "$GUM_BORDER" \
        --width "$WIZARD_WIDTH" \
        --padding "0 1" \
        "$header" \
        "$progress" \
        "" \
        "$content" \
        "" \
        "$footer"
}

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

# =============================================================================
# Content building helpers
# =============================================================================

# Builds wizard content from field array.
# Parameters:
#   $@ - Array of "label|value" or "label|" (pending) strings
# Returns: Formatted content via stdout
wiz_build_content() {
    local content=""
    for field in "$@"; do
        local label="${field%%|*}"
        local value="${field#*|}"

        if [[ -n "$value" ]]; then
            content+="$(_wiz_field "$label" "$value")"$'\n'
        else
            content+="$(_wiz_field_pending "$label")"$'\n'
        fi
    done
    # Remove trailing newline
    printf "%s" "${content%$'\n'}"
}

# Builds section header.
# Parameters:
#   $1 - Section title
# Returns: Styled header via stdout
wiz_section() {
    local title="$1"
    gum style --foreground "$GUM_PRIMARY" --bold "$title"
}

# =============================================================================
# Interactive step with inline editing
# =============================================================================

# Field definition arrays for current step
declare -a WIZ_FIELD_LABELS=()
declare -a WIZ_FIELD_VALUES=()
declare -a WIZ_FIELD_TYPES=()      # "input", "password", "choose", "multi"
declare -a WIZ_FIELD_OPTIONS=()    # For choose/multi: "opt1|opt2|opt3"
declare -a WIZ_FIELD_DEFAULTS=()
declare -a WIZ_FIELD_VALIDATORS=() # Validator function names
WIZ_CURRENT_FIELD=0

# Clears field arrays for a new step.
_wiz_clear_fields() {
    WIZ_FIELD_LABELS=()
    WIZ_FIELD_VALUES=()
    WIZ_FIELD_TYPES=()
    WIZ_FIELD_OPTIONS=()
    WIZ_FIELD_DEFAULTS=()
    WIZ_FIELD_VALIDATORS=()
    WIZ_CURRENT_FIELD=0
}

# Adds a field definition to the current step.
# Parameters:
#   $1 - Label
#   $2 - Type: "input", "password", "choose", "multi"
#   $3 - Default value or options (for choose: "opt1|opt2|opt3")
#   $4 - Validator function name (optional)
_wiz_add_field() {
    local label="$1"
    local type="$2"
    local default_or_options="$3"
    local validator="${4:-}"

    WIZ_FIELD_LABELS+=("$label")
    WIZ_FIELD_VALUES+=("")
    WIZ_FIELD_TYPES+=("$type")

    if [[ "$type" == "choose" || "$type" == "multi" ]]; then
        WIZ_FIELD_OPTIONS+=("$default_or_options")
        WIZ_FIELD_DEFAULTS+=("")
    else
        WIZ_FIELD_OPTIONS+=("")
        WIZ_FIELD_DEFAULTS+=("$default_or_options")
    fi

    WIZ_FIELD_VALIDATORS+=("$validator")
}

# Builds content showing fields with current/cursor indicator.
# Parameters:
#   $1 - Current field index (for cursor), -1 for no cursor
#   $2 - Edit mode field index, -1 for no edit mode
#   $3 - Current edit buffer (for edit mode)
# Returns: Formatted content via stdout
_wiz_build_fields_content() {
    local cursor_idx="${1:--1}"
    local edit_idx="${2:--1}"
    local edit_buffer="${3:-}"
    local content=""
    local i

    for i in "${!WIZ_FIELD_LABELS[@]}"; do
        local label="${WIZ_FIELD_LABELS[$i]}"
        local value="${WIZ_FIELD_VALUES[$i]}"
        local type="${WIZ_FIELD_TYPES[$i]}"

        # Determine display value
        local display_value="$value"
        if [[ "$type" == "password" && -n "$value" ]]; then
            display_value="********"
        fi

        # Build field line
        if [[ $i -eq $edit_idx ]]; then
            # Edit mode - show input field with cursor
            content+="${ANSI_ACCENT}› ${ANSI_RESET}"
            content+="${ANSI_PRIMARY}${label}: ${ANSI_RESET}"
            if [[ "$type" == "password" ]]; then
                # Show asterisks for password
                local masked=""
                for ((j=0; j<${#edit_buffer}; j++)); do masked+="*"; done
                content+="${ANSI_SUCCESS}${masked}${ANSI_ACCENT}▌${ANSI_RESET}"
            else
                content+="${ANSI_SUCCESS}${edit_buffer}${ANSI_ACCENT}▌${ANSI_RESET}"
            fi
        elif [[ $i -eq $cursor_idx ]]; then
            # Current field - show cursor
            if [[ -n "$value" ]]; then
                content+="${ANSI_ACCENT}› ${ANSI_RESET}"
                content+="${ANSI_MUTED}${label}: ${ANSI_RESET}"
                content+="${ANSI_PRIMARY}${display_value}${ANSI_RESET}"
            else
                content+="${ANSI_ACCENT}› ${ANSI_RESET}"
                content+="${ANSI_ACCENT}${label}: ${ANSI_RESET}"
                content+="${ANSI_MUTED}...${ANSI_RESET}"
            fi
        else
            # Not current field
            if [[ -n "$value" ]]; then
                content+="${ANSI_SUCCESS}✓ ${ANSI_RESET}"
                content+="${ANSI_MUTED}${label}: ${ANSI_RESET}"
                content+="${ANSI_PRIMARY}${display_value}${ANSI_RESET}"
            else
                content+="${ANSI_MUTED}○ ${ANSI_RESET}"
                content+="${ANSI_MUTED}${label}: ${ANSI_RESET}"
                content+="${ANSI_MUTED}...${ANSI_RESET}"
            fi
        fi
        content+=$'\n'
    done

    # Remove trailing newline
    printf "%s" "${content%$'\n'}"
}

# Draws the wizard box with current state.
# Parameters:
#   $1 - Step number
#   $2 - Step title
#   $3 - Content (field lines)
#   $4 - Footer text
#   $5 - "true" to clear screen, "false" to just move cursor home
_wiz_draw_box() {
    local step="$1"
    local title="$2"
    local content="$3"
    local footer="$4"
    local do_clear="$5"

    # Hide cursor during redraw
    printf '\033[?25l'

    if [[ "$do_clear" == "true" ]]; then
        clear
    else
        printf '\033[H'
    fi
    wiz_banner

    local header
    header="${ANSI_PRIMARY}Step ${step}/${WIZARD_TOTAL_STEPS}: ${title}${ANSI_RESET}"

    local progress
    progress="${ANSI_MUTED}$(_wiz_progress_bar "$step" "$WIZARD_TOTAL_STEPS" 53)${ANSI_RESET}"

    gum style \
        --border rounded \
        --border-foreground "$GUM_BORDER" \
        --width "$WIZARD_WIDTH" \
        --padding "0 1" \
        "$header" \
        "$progress" \
        "" \
        "$content" \
        "" \
        "$footer"

    # Clear to end of screen
    printf '\033[J\033[?25h'
}

# Displays the wizard box with editable fields and handles input.
# Parameters:
#   $1 - Step number
#   $2 - Step title
# Returns: "next", "back", or "quit"
# Side effects: Populates WIZ_FIELD_VALUES array
wiz_step_interactive() {
    local step="$1"
    local title="$2"
    local num_fields=${#WIZ_FIELD_LABELS[@]}
    local show_back="true"
    [[ "$step" -eq 1 ]] && show_back="false"

    # Find first empty field to start with
    WIZ_CURRENT_FIELD=0
    for i in "${!WIZ_FIELD_VALUES[@]}"; do
        if [[ -z "${WIZ_FIELD_VALUES[$i]}" ]]; then
            WIZ_CURRENT_FIELD=$i
            break
        fi
    done

    # Edit mode state
    local edit_mode=false
    local edit_buffer=""
    local first_draw=true

    while true; do
        # Build footer based on state
        local footer=""
        local all_filled=true
        for val in "${WIZ_FIELD_VALUES[@]}"; do
            [[ -z "$val" ]] && all_filled=false && break
        done

        if [[ "$edit_mode" == "true" ]]; then
            footer+="${ANSI_ACCENT}[Enter] Save  ${ANSI_RESET}"
            footer+="${ANSI_MUTED}[Esc] Cancel${ANSI_RESET}"
        else
            if [[ "$show_back" == "true" ]]; then
                footer+="${ANSI_MUTED}[B] Back  ${ANSI_RESET}"
            fi
            footer+="${ANSI_ACCENT}[↑/↓] Navigate  ${ANSI_RESET}"
            footer+="${ANSI_ACCENT}[Enter] Edit  ${ANSI_RESET}"
            if [[ "$all_filled" == "true" ]]; then
                footer+="${ANSI_ACCENT}[N] Next  ${ANSI_RESET}"
            fi
            footer+="${ANSI_ACCENT}[Q] Quit${ANSI_RESET}"
        fi

        # Build content
        local content
        if [[ "$edit_mode" == "true" ]]; then
            content=$(_wiz_build_fields_content "-1" "$WIZ_CURRENT_FIELD" "$edit_buffer")
        else
            content=$(_wiz_build_fields_content "$WIZ_CURRENT_FIELD" "-1" "")
        fi

        # Draw
        _wiz_draw_box "$step" "$title" "$content" "$footer" "$first_draw"
        first_draw=false

        # Wait for keypress
        local key
        read -rsn1 key

        if [[ "$edit_mode" == "true" ]]; then
            # Edit mode key handling
            case "$key" in
                $'\e')
                    # Escape - cancel edit
                    edit_mode=false
                    edit_buffer=""
                    ;;
                ""|$'\n')
                    # Enter - save value
                    local validator="${WIZ_FIELD_VALIDATORS[$WIZ_CURRENT_FIELD]}"
                    if [[ -n "$validator" && -n "$edit_buffer" ]]; then
                        if ! "$validator" "$edit_buffer" 2>/dev/null; then
                            # Invalid - flash and continue editing
                            continue
                        fi
                    fi
                    WIZ_FIELD_VALUES[WIZ_CURRENT_FIELD]="$edit_buffer"
                    edit_mode=false
                    edit_buffer=""
                    # Move to next empty field
                    for ((i = WIZ_CURRENT_FIELD + 1; i < num_fields; i++)); do
                        if [[ -z "${WIZ_FIELD_VALUES[$i]}" ]]; then
                            WIZ_CURRENT_FIELD=$i
                            break
                        fi
                    done
                    ;;
                $'\x7f'|$'\b')
                    # Backspace - delete last char
                    if [[ -n "$edit_buffer" ]]; then
                        edit_buffer="${edit_buffer%?}"
                    fi
                    ;;
                *)
                    # Regular character - append to buffer
                    if [[ "$key" =~ ^[[:print:]]$ ]]; then
                        edit_buffer+="$key"
                    fi
                    ;;
            esac
        else
            # Navigation mode key handling
            case "$key" in
                $'\e')
                    # Escape sequence (arrows)
                    read -rsn2 -t1 key 2>/dev/null || read -rsn2 key
                    case "$key" in
                        '[A') ((WIZ_CURRENT_FIELD > 0)) && ((WIZ_CURRENT_FIELD--)) ;;
                        '[B') ((WIZ_CURRENT_FIELD < num_fields - 1)) && ((WIZ_CURRENT_FIELD++)) ;;
                    esac
                    ;;
                ""|$'\n')
                    # Enter - start editing
                    local field_type="${WIZ_FIELD_TYPES[$WIZ_CURRENT_FIELD]}"
                    if [[ "$field_type" == "choose" || "$field_type" == "multi" ]]; then
                        # For choose/multi, use gum choose
                        _wiz_edit_field_select "$WIZ_CURRENT_FIELD"
                        first_draw=true
                    else
                        # For input/password, use inline edit
                        edit_mode=true
                        edit_buffer="${WIZ_FIELD_VALUES[$WIZ_CURRENT_FIELD]:-${WIZ_FIELD_DEFAULTS[$WIZ_CURRENT_FIELD]}}"
                    fi
                    ;;
                "j") ((WIZ_CURRENT_FIELD < num_fields - 1)) && ((WIZ_CURRENT_FIELD++)) ;;
                "k") ((WIZ_CURRENT_FIELD > 0)) && ((WIZ_CURRENT_FIELD--)) ;;
                "n"|"N")
                    if [[ "$all_filled" == "true" ]]; then
                        echo "next"
                        return
                    fi
                    ;;
                "b"|"B")
                    if [[ "$show_back" == "true" ]]; then
                        echo "back"
                        return
                    fi
                    ;;
                "q"|"Q")
                    if wiz_confirm "Are you sure you want to quit?"; then
                        clear
                        printf '%s\n' "${ANSI_ERROR}Installation cancelled.${ANSI_RESET}"
                        exit 1
                    fi
                    first_draw=true
                    ;;
            esac
        fi
    done
}

# Handles select field editing (choose/multi) using gum.
# Parameters:
#   $1 - Field index
_wiz_edit_field_select() {
    local idx="$1"
    local label="${WIZ_FIELD_LABELS[$idx]}"
    local type="${WIZ_FIELD_TYPES[$idx]}"
    local field_options="${WIZ_FIELD_OPTIONS[$idx]}"
    local -a opts
    local new_value=""

    IFS='|' read -ra opts <<< "$field_options"

    echo ""
    if [[ "$type" == "choose" ]]; then
        new_value=$(wiz_choose "Select ${label}:" "${opts[@]}")
    else
        new_value=$(wiz_choose_multi "Select ${label}:" "${opts[@]}")
    fi

    if [[ -n "$new_value" ]]; then
        WIZ_FIELD_VALUES[idx]="$new_value"
        # Move to next empty field
        local num_fields=${#WIZ_FIELD_LABELS[@]}
        for ((i = idx + 1; i < num_fields; i++)); do
            if [[ -z "${WIZ_FIELD_VALUES[$i]}" ]]; then
                WIZ_CURRENT_FIELD=$i
                return
            fi
        done
    fi
}


# =============================================================================
# Demo/test function
# =============================================================================

# Demonstrates wizard visuals (for testing).
# Can be run standalone: source 04a-wizard.sh && wiz_demo
wiz_demo() {
    # Demo Step 2: Network (static display)
    local content
    content=$(wiz_build_content \
        "Interface|enp0s31f6" \
        "Bridge|Internal NAT (vmbr0)" \
        "Private subnet|10.0.0.0/24" \
        "IPv6|2a01:4f8::1 (auto)")

    wiz_box 2 "Network" "$content"

    echo ""
    echo "--- Demo: waiting for navigation ---"
    local nav
    nav=$(wiz_wait_nav)
    echo "Navigation: $nav"

    # Demo interactive step
    echo ""
    echo "--- Demo: interactive step ---"
    _wiz_clear_fields
    _wiz_add_field "Hostname" "input" "pve"
    _wiz_add_field "Domain" "input" "local"
    _wiz_add_field "Email" "input" "admin@example.com"
    _wiz_add_field "Password" "password" ""
    _wiz_add_field "Timezone" "choose" "Europe/Kyiv|Europe/London|America/New_York|UTC"

    local result
    result=$(wiz_step_interactive 1 "System")
    echo "Step result: $result"
    echo "Values:"
    for i in "${!WIZ_FIELD_LABELS[@]}"; do
        local display="${WIZ_FIELD_VALUES[$i]}"
        [[ "${WIZ_FIELD_TYPES[$i]}" == "password" ]] && display="********"
        echo "  ${WIZ_FIELD_LABELS[$i]}: $display"
    done

    wiz_msg success "Demo complete!"
}
