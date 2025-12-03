# shellcheck shell=bash
# =============================================================================
# Gum-based wizard UI - Core components
# =============================================================================
# Provides color configuration, banner display, and core display functions
# for the step-by-step wizard interface.

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
# wiz_banner outputs a colored ASCII banner for the Hetzner Automated Installer to stdout using ANSI escape sequences.
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
# _wiz_progress_bar generates a horizontal progress bar reflecting `current` out of `total` using the specified `width` and writes it to stdout.
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
# _wiz_field prints a completed field line with a green checkmark, a muted label, and a primary-colored value.
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
# _wiz_field_pending outputs a pending field line to stdout showing a muted hollow circle, the given label followed by a colon, and an ellipsis.
# label is the text used as the field label.
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
# wiz_box renders a complete wizard step box with header, progress bar, content, and navigation footer.
# It clears the screen, displays the banner, and outputs a bordered, styled box using gum.
# Arguments:
#   step        - current step number (used for header and progress bar)
#   title       - title text shown in the header
#   content     - preformatted content block (may be multiline)
#   show_back   - optional; "true" to include a Back hint when step > 1 (defaults to "true")
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

# Draws the wizard box with current state.
# Parameters:
#   $1 - Step number
#   $2 - Step title
#   $3 - Content (field lines)
#   $4 - Footer text
# _wiz_draw_box redraws the wizard UI box with header, progress bar, content, and footer using gum styling and updates the terminal (optionally clearing the screen).
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

# =============================================================================
# Content building helpers
# =============================================================================

# Builds wizard content from field array.
# Parameters:
#   $@ - Array of "label|value" or "label|" (pending) strings
# wiz_build_content builds a formatted content block from fields provided as "label|value" (completed) or "label|" (pending).
# It converts each "label|value" into a completed field line and each "label|" into a pending field line, then concatenates them.
# The assembled content is written to stdout without a trailing newline.
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
# wiz_section produces a bold, primary-colored section title using gum and writes it to stdout.
wiz_section() {
    local title="$1"
    gum style --foreground "$GUM_PRIMARY" --bold "$title"
}