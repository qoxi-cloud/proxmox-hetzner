# shellcheck shell=bash
# System status display

# Displays system status summary in formatted table.
# Only shows table if there are errors, then exits.
# If all checks pass, silently proceeds to wizard.
show_system_status() {
  detect_drives
  detect_disk_roles

  local no_drives=0
  if [[ $DRIVE_COUNT -eq 0 ]]; then
    no_drives=1
  fi

  # Check for errors first
  local has_errors=false
  if [[ $PREFLIGHT_ERRORS -gt 0 || $no_drives -eq 1 ]]; then
    has_errors=true
  fi

  # If no errors, go straight to wizard
  if [[ $has_errors == false ]]; then
    _wiz_start_edit
    return 0
  fi

  # Build table data with colored status markers
  local table_data
  table_data=",,
Status,Item,Value
"

  # Helper to format status with color using gum style
  format_status() {
    local status="$1"
    case "$status" in
      ok) gum style --foreground "$HEX_CYAN" "[OK]" ;;
      warn) gum style --foreground "$HEX_YELLOW" "[WARN]" ;;
      error) gum style --foreground "$HEX_RED" "[ERROR]" ;;
    esac
  }

  # Helper to add row
  add_row() {
    local status="$1"
    local label="$2"
    local value="$3"
    local status_text
    status_text=$(format_status "$status")
    table_data+="${status_text},${label},${value}
"
  }

  add_row "$PREFLIGHT_ROOT_STATUS" "Root Access" "$PREFLIGHT_ROOT"
  add_row "$PREFLIGHT_NET_STATUS" "Internet" "$PREFLIGHT_NET"
  add_row "$PREFLIGHT_DISK_STATUS" "Temp Space" "$PREFLIGHT_DISK"
  add_row "$PREFLIGHT_RAM_STATUS" "RAM" "$PREFLIGHT_RAM"
  add_row "$PREFLIGHT_CPU_STATUS" "CPU" "$PREFLIGHT_CPU"
  add_row "$PREFLIGHT_KVM_STATUS" "KVM" "$PREFLIGHT_KVM"

  # Add storage rows
  if [[ $no_drives -eq 1 ]]; then
    local error_status
    error_status=$(format_status "error")
    table_data+="${error_status},No drives detected!,
"
  else
    for i in "${!DRIVE_NAMES[@]}"; do
      local ok_status
      ok_status=$(format_status "ok")
      table_data+="${ok_status},${DRIVE_NAMES[$i]},${DRIVE_SIZES[$i]}  ${DRIVE_MODELS[$i]:0:25}
"
    done
  fi

  # Remove trailing newline
  table_data="${table_data%$'\n'}"

  # Display table using gum table
  printf '%s\n' "$table_data" | gum table \
    --print \
    --border "none" \
    --cell.foreground "$HEX_GRAY" \
    --header.foreground "$HEX_ORANGE"

  printf '\n'
  print_error "System requirements not met. Please fix the issues above."
  printf '\n'
  log "ERROR: Pre-flight checks failed"
  exit 1
}
