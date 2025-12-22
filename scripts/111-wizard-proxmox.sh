# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - Proxmox Settings Editors
# iso_version, repository
# =============================================================================

# Edits Proxmox ISO version via searchable list.
# Fetches available ISOs (last 5) and updates PROXMOX_ISO_VERSION global.
_edit_iso_version() {
  _wiz_start_edit

  _wiz_description \
    " Proxmox VE version to install:" \
    "" \
    "  Latest version recommended for new installations." \
    ""

  # Get available ISO versions (last 5, uses cached data from prefetch)
  local iso_list
  iso_list=$(get_available_proxmox_isos 5)

  if [[ -z $iso_list ]]; then
    _wiz_hide_cursor
    _wiz_error "Failed to fetch ISO list"
    sleep 2
    return
  fi

  # 1 header + 5 items for gum choose
  _show_input_footer "filter" 6

  local selected
  if ! selected=$(printf '%s\n' "$iso_list" | _wiz_choose --header="Proxmox Version:"); then
    return
  fi

  PROXMOX_ISO_VERSION="$selected"
}

# Edits Proxmox package repository type.
# Prompts for subscription key if enterprise repo selected.
# Updates PVE_REPO_TYPE and PVE_SUBSCRIPTION_KEY globals.
_edit_repository() {
  _wiz_start_edit

  _wiz_description \
    " Proxmox VE package repository:" \
    "" \
    "  {{cyan:No-subscription}}: Free updates, community tested" \
    "  {{cyan:Enterprise}}:      Stable updates, requires license" \
    "  {{cyan:Test}}:            Latest builds, may be unstable" \
    ""

  # 1 header + 3 items for gum choose
  _show_input_footer "filter" 4

  local selected
  if ! selected=$(printf '%s\n' "$WIZ_REPO_TYPES" | _wiz_choose --header="Repository:"); then
    return
  fi

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
    _wiz_input_screen "Enter Proxmox subscription key (optional)"

    local sub_key
    sub_key=$(
      _wiz_input \
        --placeholder "pve2c-..." \
        --value "$PVE_SUBSCRIPTION_KEY" \
        --prompt "Subscription Key: "
    )

    PVE_SUBSCRIPTION_KEY="$sub_key"
  else
    # Clear subscription key if not enterprise
    PVE_SUBSCRIPTION_KEY=""
  fi
}
