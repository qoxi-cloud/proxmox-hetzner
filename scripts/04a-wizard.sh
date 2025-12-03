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
# Color configuration for gum (hex values from our color scheme)
# =============================================================================
# Maps our ANSI colors to hex for gum:
#   CLR_CYAN    (#00B1FF) -> Primary/accent color
#   CLR_ORANGE  (#FF8700) -> Highlight/selected
#   CLR_YELLOW  (#FFFF55) -> Warnings
#   CLR_RED     (#FF5555) -> Errors
#   CLR_GRAY    (#585858) -> Muted/borders
#   CLR_HETZNER (#D70000) -> Brand color

GUM_PRIMARY="#00B1FF"
GUM_ACCENT="#FF8700"
GUM_SUCCESS="#55FF55"
GUM_WARNING="#FFFF55"
GUM_ERROR="#FF5555"
GUM_MUTED="#585858"
GUM_BORDER="#444444"

# =============================================================================
# Banner display
# =============================================================================

# Displays the Proxmox ASCII banner using ANSI colors.
# Uses direct ANSI codes for instant display (no gum subprocess overhead).
# Side effects: Outputs styled banner to terminal
wiz_banner() {
    # ANSI color codes matching our gum colors
    local gray=$'\033[38;5;240m'
    local orange=$'\033[38;5;208m'
    local red=$'\033[38;5;160m'
    local reset=$'\033[0m'

    printf '%s\n' \
        "" \
        "${gray}    _____                                             ${reset}" \
        "${gray}   |  __ \\                                            ${reset}" \
        "${gray}   | |__) | _ __   ___  ${orange}__  __${gray}  _ __ ___    ___  ${orange}__  __${reset}" \
        "${gray}   |  ___/ | '__| / _ \\ ${orange}\\ \\/ /${gray} | '_ \` _ \\  / _ \\ ${orange}\\ \\/ /${reset}" \
        "${gray}   | |     | |   | (_) |${orange} >  <${gray}  | | | | | || (_) |${orange} >  <${reset}" \
        "${gray}   |_|     |_|    \\___/ ${orange}/_/\\_\\${gray} |_| |_| |_| \\___/ ${orange}/_/\\_\\${reset}" \
        "" \
        "${red}               Hetzner ${gray}Automated Installer${reset}" \
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
# Demo/test function
# =============================================================================

# Demonstrates wizard visuals (for testing).
# Can be run standalone: source 04a-wizard.sh && wiz_demo
wiz_demo() {
    # Demo Step 2: Network
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

    # Demo input
    echo ""
    echo "--- Demo: text input ---"
    local hostname
    hostname=$(wiz_input "Hostname:" "pve" "enter hostname")
    echo "You entered: $hostname"

    # Demo choose
    echo ""
    echo "--- Demo: single select ---"
    local tz
    tz=$(wiz_choose "Select timezone:" "Europe/Kyiv" "Europe/London" "America/New_York" "UTC")
    echo "Selected: $tz (index: $WIZ_SELECTED_INDEX)"

    # Demo multi-select
    echo ""
    echo "--- Demo: multi select ---"
    local extras
    extras=$(wiz_choose_multi "Select extras:" "vnstat" "auditd" "unattended-upgrades")
    echo "Selected: $extras"
    echo "Indices: ${WIZ_SELECTED_INDICES[*]}"

    # Demo confirm
    echo ""
    echo "--- Demo: confirm ---"
    if wiz_confirm "Proceed with demo?"; then
        wiz_msg success "Confirmed!"
    else
        wiz_msg warning "Cancelled"
    fi

    # Demo spinner
    echo ""
    echo "--- Demo: spinner ---"
    wiz_spin "Doing something..." sleep 2

    wiz_msg success "Demo complete!"
}
