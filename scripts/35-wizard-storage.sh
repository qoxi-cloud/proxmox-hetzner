# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Storage Settings Editors
# zfs_mode
# =============================================================================

_edit_zfs_mode() {
  clear
  show_banner
  echo ""

  # Start with base ZFS modes, add more based on drive count
  local options="$WIZ_ZFS_MODES"
  if [[ ${DRIVE_COUNT:-0} -ge 3 ]]; then
    options+="\nraid5"
  fi
  if [[ ${DRIVE_COUNT:-0} -ge 4 ]]; then
    options+="\nraid10"
  fi

  # Count options (2-4 items depending on drives) + 1 header
  local item_count=3
  [[ ${DRIVE_COUNT:-0} -ge 3 ]] && item_count=4
  [[ ${DRIVE_COUNT:-0} -ge 4 ]] && item_count=5
  _show_input_footer "filter" "$item_count"

  local selected
  selected=$(echo -e "$options" | gum choose \
    --header="ZFS mode:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && ZFS_RAID="$selected"
}
