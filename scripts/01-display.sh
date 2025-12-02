# shellcheck shell=bash
# =============================================================================
# Display utilities
# =============================================================================

# Display a boxed section with title using 'boxes'
# Usage: display_box "title" "content"
display_box() {
    local title="$1"
    local content="$2"
    local box_style="${3:-stone}"

    echo -e "${CLR_GRAY}"
    {
        echo "$title"
        echo ""
        echo "$content"
    } | boxes -d "$box_style" -p a1
    echo -e "${CLR_RESET}"
}

# Display system info table using boxes and column
# Takes associative array-like pairs: "label|value|status"
# status: ok=green, warn=yellow, error=red
display_info_table() {
    local title="$1"
    shift
    local items=("$@")

    local content=""
    for item in "${items[@]}"; do
        local label="${item%%|*}"
        local rest="${item#*|}"
        local value="${rest%%|*}"
        local status="${rest#*|}"

        case "$status" in
            ok)    content+="[OK]     $label: $value"$'\n' ;;
            warn)  content+="[WARN]   $label: $value"$'\n' ;;
            error) content+="[ERROR]  $label: $value"$'\n' ;;
            *)     content+="         $label: $value"$'\n' ;;
        esac
    done

    # Remove trailing newline and display
    content="${content%$'\n'}"

    echo ""
    {
        echo "=== $title ==="
        echo ""
        echo "$content"
    } | boxes -d stone -p a1
    echo ""
}

# Colorize the output of boxes (post-process)
# Adds cyan frame and colors for [OK], [WARN], [ERROR]
colorize_status() {
    while IFS= read -r line; do
        # Top/bottom border
        if [[ "$line" =~ ^\+[-+]+\+$ ]]; then
            echo "${CLR_GRAY}${line}${CLR_RESET}"
        # Content line with | borders
        elif [[ "$line" =~ ^(\|)(.*)\|$ ]]; then
            local content="${BASH_REMATCH[2]}"
            # Color status markers
            content="${content//\[OK\]/${CLR_CYAN}[OK]${CLR_RESET}}"
            content="${content//\[WARN\]/${CLR_YELLOW}[WARN]${CLR_RESET}}"
            content="${content//\[ERROR\]/${CLR_RED}[ERROR]${CLR_RESET}}"
            echo "${CLR_GRAY}|${CLR_RESET}${content}${CLR_GRAY}|${CLR_RESET}"
        else
            echo "$line"
        fi
    done
}

# Print success message with checkmark
# Usage: print_success "label: value" or print_success "label" "value"
# When 2 args provided, value is highlighted in cyan
print_success() {
    if [[ $# -eq 2 ]]; then
        echo -e "${CLR_CYAN}✓${CLR_RESET} $1 ${CLR_CYAN}$2${CLR_RESET}"
    else
        echo -e "${CLR_CYAN}✓${CLR_RESET} $1"
    fi
}

# Print error message with cross
print_error() {
    echo -e "${CLR_RED}✗${CLR_RESET} $1"
}

# Print warning message
# Usage: print_warning "message" [nested] OR print_warning "label" "value"
# When 2 args provided and second is not "true", value is highlighted in cyan
# If nested=true, adds indent before the warning icon
print_warning() {
    local message="$1"
    local second="${2:-false}"
    local indent=""

    # Check if second argument is a value (not "true" for nested)
    if [[ $# -eq 2 && "$second" != "true" ]]; then
        # Two-argument format: label and value
        echo -e "${CLR_YELLOW}⚠️${CLR_RESET} $message ${CLR_CYAN}$second${CLR_RESET}"
    else
        # Original format: message with optional nested indent
        if [[ "$second" == "true" ]]; then
            indent="  "
        fi
        echo -e "${indent}${CLR_YELLOW}⚠️${CLR_RESET} $message"
    fi
}

# print_info prints an informational message prefixed with a cyan info symbol.
print_info() {
    echo -e "${CLR_CYAN}ℹ${CLR_RESET} $1"
}