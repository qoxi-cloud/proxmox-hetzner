# shellcheck shell=bash
# =============================================================================
# Gum-based wizard UI - Field management
# =============================================================================
# Provides field definition arrays, interactive step handling,
# and inline editing functionality.

# =============================================================================
# Interactive step with inline editing
# =============================================================================

# Field definition arrays for current step
declare -a WIZ_FIELD_LABELS=()
declare -a WIZ_FIELD_VALUES=()
declare -a WIZ_FIELD_TYPES=()   # "input", "password", "choose", "multi"
declare -a WIZ_FIELD_OPTIONS=() # For choose/multi: "opt1|opt2|opt3"
declare -a WIZ_FIELD_DEFAULTS=()
declare -a WIZ_FIELD_VALIDATORS=() # Validator function names
WIZ_CURRENT_FIELD=0

# _wiz_clear_fields clears all per-step field definition arrays and resets WIZ_CURRENT_FIELD to 0.
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
# _wiz_add_field adds a field definition to the current wizard step by appending the label, an empty value placeholder, the field type, options or default (depending on type), and an optional validator to the corresponding WIZ_* arrays.
_wiz_add_field() {
  local label="$1"
  local type="$2"
  local default_or_options="$3"
  local validator="${4:-}"

  WIZ_FIELD_LABELS+=("$label")
  WIZ_FIELD_VALUES+=("")
  WIZ_FIELD_TYPES+=("$type")

  if [[ $type == "choose" || $type == "multi" ]]; then
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
# _wiz_build_fields_content builds a textual representation of all wizard fields for display and prints it to stdout.
# It accepts three positional arguments: the current cursor index (first arg, -1 for no cursor), the edit-mode field index (second arg, -1 for no edit), and the current edit buffer contents (third arg).
# Each field is rendered as a single line with visual indicators: edit-mode shows a right-arrow, the label, and an inline input with a caret; the current field shows a cursor and either its value or an ellipsis; completed fields show a checkmark and their value; empty fields show a hollow circle and an ellipsis.
# Password-type fields are masked in display (asterisks), and when editing a password the edit buffer is shown as asterisks.
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
    if [[ $type == "password" && -n $value ]]; then
      display_value="********"
    fi

    # Build field line
    if [[ $i -eq $edit_idx ]]; then
      # Edit mode - show input field with cursor
      content+="${ANSI_ACCENT}› ${ANSI_RESET}"
      content+="${ANSI_PRIMARY}${label}: ${ANSI_RESET}"
      if [[ $type == "password" ]]; then
        # Show asterisks for password
        local masked=""
        for ((j = 0; j < ${#edit_buffer}; j++)); do masked+="*"; done
        content+="${ANSI_SUCCESS}${masked}${ANSI_ACCENT}▌${ANSI_RESET}"
      else
        content+="${ANSI_SUCCESS}${edit_buffer}${ANSI_ACCENT}▌${ANSI_RESET}"
      fi
    elif [[ $i -eq $cursor_idx ]]; then
      # Current field - show cursor
      if [[ -n $value ]]; then
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
      if [[ -n $value ]]; then
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

# Handles select field editing (choose/multi) using gum.
# Parameters:
# _wiz_edit_field_select presents a selection UI for a choose/multi field, stores the chosen value in WIZ_FIELD_VALUES, and advances WIZ_CURRENT_FIELD to the next empty field when applicable.
_wiz_edit_field_select() {
  local idx="$1"
  local label="${WIZ_FIELD_LABELS[$idx]}"
  local type="${WIZ_FIELD_TYPES[$idx]}"
  local field_options="${WIZ_FIELD_OPTIONS[$idx]}"
  local -a opts
  local new_value=""

  IFS='|' read -ra opts <<<"$field_options"

  echo ""
  if [[ $type == "choose" ]]; then
    new_value=$(wiz_choose "Select ${label}:" "${opts[@]}")
  else
    new_value=$(wiz_choose_multi "Select ${label}:" "${opts[@]}")
  fi

  if [[ -n $new_value ]]; then
    WIZ_FIELD_VALUES[idx]="$new_value"
    # Move to next empty field
    local num_fields=${#WIZ_FIELD_LABELS[@]}
    for ((i = idx + 1; i < num_fields; i++)); do
      if [[ -z ${WIZ_FIELD_VALUES[$i]} ]]; then
        WIZ_CURRENT_FIELD=$i
        return
      fi
    done
  fi
}

# Displays the wizard box with editable fields and handles input.
# Parameters:
#   $1 - Step number
#   $2 - Step title
# Returns: "next", "back", or "quit"
#wiz_step_interactive runs an interactive wizard step for the given step number and title, presenting WIZ_FIELD_LABELS, handling navigation, inline editing and choose/multi prompts, applying per-field validators, populating the WIZ_FIELD_VALUES array, and emitting "next" or "back" to indicate flow.
wiz_step_interactive() {
  local step="$1"
  local title="$2"
  local num_fields=${#WIZ_FIELD_LABELS[@]}
  local show_back="true"
  [[ $step -eq 1 ]] && show_back="false"

  # Find first empty field to start with
  WIZ_CURRENT_FIELD=0
  for i in "${!WIZ_FIELD_VALUES[@]}"; do
    if [[ -z ${WIZ_FIELD_VALUES[$i]} ]]; then
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
      [[ -z $val ]] && all_filled=false && break
    done

    if [[ $edit_mode == "true" ]]; then
      footer+="${ANSI_ACCENT}[Enter] Save${ANSI_RESET}  "
      footer+="${ANSI_MUTED}[Esc] Cancel${ANSI_RESET}"
    else
      if [[ $show_back == "true" ]]; then
        footer+="${ANSI_MUTED}[B] Back${ANSI_RESET}  "
      fi
      footer+="${ANSI_MUTED}[${ANSI_ACCENT}↑/↓${ANSI_MUTED}] Navigate${ANSI_RESET}  "
      footer+="${ANSI_ACCENT}[Enter] Edit${ANSI_RESET}  "
      if [[ $all_filled == "true" ]]; then
        footer+="${ANSI_ACCENT}[N] Next${ANSI_RESET}  "
      fi
      footer+="${ANSI_MUTED}[${ANSI_ACCENT}Q${ANSI_MUTED}] Quit${ANSI_RESET}"
    fi

    # Build content
    local content
    if [[ $edit_mode == "true" ]]; then
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

    if [[ $edit_mode == "true" ]]; then
      # Edit mode key handling
      case "$key" in
        $'\e')
          # Escape - cancel edit
          edit_mode=false
          edit_buffer=""
          ;;
        "" | $'\n')
          # Enter - save value
          local validator="${WIZ_FIELD_VALIDATORS[$WIZ_CURRENT_FIELD]}"
          if [[ -n $validator && -n $edit_buffer ]]; then
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
            if [[ -z ${WIZ_FIELD_VALUES[$i]} ]]; then
              WIZ_CURRENT_FIELD=$i
              break
            fi
          done
          ;;
        $'\x7f' | $'\b')
          # Backspace - delete last char
          if [[ -n $edit_buffer ]]; then
            edit_buffer="${edit_buffer%?}"
          fi
          ;;
        *)
          # Regular character - append to buffer
          if [[ $key =~ ^[[:print:]]$ ]]; then
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
        "" | $'\n')
          # Enter - start editing
          local field_type="${WIZ_FIELD_TYPES[$WIZ_CURRENT_FIELD]}"
          if [[ $field_type == "choose" || $field_type == "multi" ]]; then
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
        "n" | "N")
          if [[ $all_filled == "true" ]]; then
            echo "next"
            return
          fi
          ;;
        "b" | "B")
          if [[ $show_back == "true" ]]; then
            echo "back"
            return
          fi
          ;;
        "q" | "Q")
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
