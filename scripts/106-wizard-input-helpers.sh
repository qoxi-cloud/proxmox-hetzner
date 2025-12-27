# shellcheck shell=bash
# Configuration Wizard - Input Helpers
# Reusable input patterns for validation and filtering

# Validated input helper

# Input with validation loop. $1=var, $2=validate_func, $3=error_msg, $@=gum args
_wiz_input_validated() {
  local var_name="$1"
  local validate_func="$2"
  local error_msg="$3"
  shift 3

  while true; do
    _wiz_start_edit
    _show_input_footer

    local value
    value=$(_wiz_input "$@")

    # Empty means cancelled
    [[ -z $value ]] && return 1

    if "$validate_func" "$value"; then
      declare -g "$var_name=$value"
      return 0
    fi

    show_validation_error "$error_msg"
  done
}

# Filter select helper

# Filter list and set variable. $1=var, $2=prompt, $3=data, $4=height (optional)
_wiz_filter_select() {
  local var_name="$1"
  local prompt="$2"
  local data="$3"
  local height="${4:-6}"

  _wiz_start_edit
  _show_input_footer "filter" "$height"

  local selected
  if ! selected=$(printf '%s' "$data" | _wiz_filter --prompt "$prompt"); then
    return 1
  fi

  declare -g "$var_name=$selected"
}
