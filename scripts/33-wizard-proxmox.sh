# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Proxmox Settings Editors
# iso_version, repository
# =============================================================================

_edit_iso_version() {
  _wiz_start_edit

  # Get available ISO versions (last 5, uses cached data from prefetch)
  local iso_list
  iso_list=$(get_available_proxmox_isos 5)

  if [[ -z $iso_list ]]; then
    gum style --foreground "$HEX_RED" "Failed to fetch ISO list"
    sleep 2
    return
  fi

  # 1 header + 5 items for gum choose
  _show_input_footer "filter" 6

  local selected
  selected=$(echo "$iso_list" | gum choose \
    --header="Proxmox Version:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  [[ -n $selected ]] && PROXMOX_ISO_VERSION="$selected"
}

_edit_repository() {
  _wiz_start_edit

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  local selected
  selected=$(echo "$WIZ_REPO_TYPES" | gum choose \
    --header="Repository:" \
    --header.foreground "$HEX_CYAN" \
    --cursor "${CLR_ORANGE}›${CLR_RESET} " \
    --cursor.foreground "$HEX_NONE" \
    --selected.foreground "$HEX_WHITE" \
    --no-show-help)

  if [[ -n $selected ]]; then
    # Map display names to internal values
    local repo_type=""
    case "$selected" in
      "No-subscription (free)") repo_type="no-subscription" ;;
      "Enterprise") repo_type="enterprise" ;;
      "Test/Development") repo_type="test" ;;
    esac

    PVE_REPO_TYPE="$repo_type"

    # If enterprise selected, optionally ask for subscription key
    if [[ $repo_type == "enterprise" ]]; then
      _wiz_start_edit
      gum style --foreground "$HEX_GRAY" "Enter Proxmox subscription key (optional)"
      echo ""
      _show_input_footer

      local sub_key
      sub_key=$(gum input \
        --placeholder "pve2c-..." \
        --value "$PVE_SUBSCRIPTION_KEY" \
        --prompt "Subscription Key: " \
        --prompt.foreground "$HEX_CYAN" \
        --cursor.foreground "$HEX_ORANGE" \
        --width 60 \
        --no-show-help)

      PVE_SUBSCRIPTION_KEY="$sub_key"
    else
      # Clear subscription key if not enterprise
      PVE_SUBSCRIPTION_KEY=""
    fi
  fi
}
