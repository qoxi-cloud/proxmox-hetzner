# shellcheck shell=bash
# =============================================================================
# Gum-based wizard UI - Main flow
# =============================================================================
# Provides configuration preview and main wizard flow orchestration.

# =============================================================================
# Configuration Preview
# =============================================================================

# Displays a summary of all configuration before installation.
# _wiz_show_preview displays a colorized configuration summary (System, Network, Storage, Security, Features, and optional Tailscale) and prompts for a single-key choice; echoes "install" on Enter, "back" on B, or exits the process after confirming Quit.
_wiz_show_preview() {
  clear
  wiz_banner

  # Build summary content
  local summary=""
  summary+="${ANSI_PRIMARY}System${ANSI_RESET}"$'\n'
  summary+="  ${ANSI_MUTED}Hostname:${ANSI_RESET} ${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"$'\n'
  summary+="  ${ANSI_MUTED}Email:${ANSI_RESET} ${EMAIL}"$'\n'
  summary+="  ${ANSI_MUTED}Timezone:${ANSI_RESET} ${TIMEZONE}"$'\n'
  summary+="  ${ANSI_MUTED}Password:${ANSI_RESET} "
  if [[ $PASSWORD_GENERATED == "yes" ]]; then
    summary+="(auto-generated)"
  else
    summary+="********"
  fi
  summary+=$'\n\n'

  summary+="${ANSI_PRIMARY}Network${ANSI_RESET}"$'\n'
  summary+="  ${ANSI_MUTED}Interface:${ANSI_RESET} ${INTERFACE_NAME}"$'\n'
  summary+="  ${ANSI_MUTED}IPv4:${ANSI_RESET} ${MAIN_IPV4_CIDR:-detecting...}"$'\n'
  summary+="  ${ANSI_MUTED}Bridge:${ANSI_RESET} ${BRIDGE_MODE}"$'\n'
  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    summary+="  ${ANSI_MUTED}Private subnet:${ANSI_RESET} ${PRIVATE_SUBNET}"$'\n'
  fi
  if [[ $IPV6_MODE != "disabled" && -n $MAIN_IPV6 ]]; then
    summary+="  ${ANSI_MUTED}IPv6:${ANSI_RESET} ${MAIN_IPV6}"$'\n'
  fi
  summary+=$'\n'

  summary+="${ANSI_PRIMARY}Storage${ANSI_RESET}"$'\n'
  summary+="  ${ANSI_MUTED}Drives:${ANSI_RESET} ${DRIVE_COUNT:-1} detected"$'\n'
  summary+="  ${ANSI_MUTED}ZFS mode:${ANSI_RESET} ${ZFS_RAID:-single}"$'\n'
  summary+="  ${ANSI_MUTED}Repository:${ANSI_RESET} ${PVE_REPO_TYPE:-no-subscription}"$'\n'
  summary+=$'\n'

  summary+="${ANSI_PRIMARY}Security${ANSI_RESET}"$'\n'
  if [[ -n $SSH_PUBLIC_KEY ]]; then
    parse_ssh_key "$SSH_PUBLIC_KEY"
    summary+="  ${ANSI_MUTED}SSH key:${ANSI_RESET} ${SSH_KEY_TYPE} (${SSH_KEY_SHORT})"$'\n'
  else
    summary+="  ${ANSI_MUTED}SSH key:${ANSI_RESET} ${ANSI_WARNING}not configured${ANSI_RESET}"$'\n'
  fi
  summary+="  ${ANSI_MUTED}SSL:${ANSI_RESET} ${SSL_TYPE:-self-signed}"$'\n'
  summary+=$'\n'

  summary+="${ANSI_PRIMARY}Features${ANSI_RESET}"$'\n'
  summary+="  ${ANSI_MUTED}Shell:${ANSI_RESET} ${DEFAULT_SHELL:-zsh}"$'\n'
  summary+="  ${ANSI_MUTED}CPU governor:${ANSI_RESET} ${CPU_GOVERNOR:-performance}"$'\n'
  summary+="  ${ANSI_MUTED}vnstat:${ANSI_RESET} ${INSTALL_VNSTAT:-yes}"$'\n'
  summary+="  ${ANSI_MUTED}Auto updates:${ANSI_RESET} ${INSTALL_UNATTENDED_UPGRADES:-yes}"$'\n'
  summary+="  ${ANSI_MUTED}Audit:${ANSI_RESET} ${INSTALL_AUDITD:-no}"$'\n'

  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    summary+=$'\n'
    summary+="${ANSI_PRIMARY}Tailscale${ANSI_RESET}"$'\n'
    summary+="  ${ANSI_MUTED}Install:${ANSI_RESET} yes"$'\n'
    if [[ -n $TAILSCALE_AUTH_KEY ]]; then
      summary+="  ${ANSI_MUTED}Auth:${ANSI_RESET} auto-connect"$'\n'
    else
      summary+="  ${ANSI_MUTED}Auth:${ANSI_RESET} manual"$'\n'
    fi
    summary+="  ${ANSI_MUTED}Tailscale SSH:${ANSI_RESET} ${TAILSCALE_SSH:-yes}"$'\n'
    if [[ $TAILSCALE_DISABLE_SSH == "yes" ]]; then
      summary+="  ${ANSI_MUTED}OpenSSH:${ANSI_RESET} ${ANSI_WARNING}will be disabled${ANSI_RESET}"$'\n'
    fi
  fi

  # Build footer
  local footer=""
  footer+="${ANSI_MUTED}[B] Back${ANSI_RESET}  "
  footer+="${ANSI_ACCENT}[Enter] Install${ANSI_RESET}  "
  footer+="${ANSI_MUTED}[${ANSI_ACCENT}Q${ANSI_MUTED}] Quit${ANSI_RESET}"

  gum style \
    --border rounded \
    --border-foreground "$GUM_BORDER" \
    --width "$WIZARD_WIDTH" \
    --padding "0 1" \
    "${ANSI_PRIMARY}Configuration Summary${ANSI_RESET}" \
    "" \
    "$summary" \
    "" \
    "$footer"

  # Wait for input
  while true; do
    local key
    read -rsn1 key
    case "$key" in
      "" | $'\n')
        echo "install"
        return
        ;;
      "b" | "B")
        echo "back"
        return
        ;;
      "q" | "Q")
        if wiz_confirm "Are you sure you want to quit?"; then
          clear
          printf '%s\n' "${ANSI_ERROR}Installation cancelled.${ANSI_RESET}"
          exit 1
        fi
        ;;
    esac
  done
}

# =============================================================================
# Main Wizard Flow
# =============================================================================

# Runs the complete wizard flow.
# Side effects: Sets all configuration global variables
# get_inputs_wizard runs an interactive, step-based wizard to collect and set global installation configuration values, ending with a preview/confirm step.
# It updates WIZARD_TOTAL_STEPS, sets globals (e.g., PVE_HOSTNAME, DOMAIN_SUFFIX, PRIVATE_SUBNET) via step helpers, and computes derived values (FQDN, PRIVATE_IP, PRIVATE_IP_CIDR) when the user confirms installation.
# Returns: 0 on success (ready to install), 1 on cancel.
get_inputs_wizard() {
  local current_step=1
  local total_steps=6

  # Update wizard total steps
  WIZARD_TOTAL_STEPS=$((total_steps + 1)) # +1 for preview

  while true; do
    local result=""

    case $current_step in
      1) result=$(_wiz_step_system) ;;
      2) result=$(_wiz_step_network) ;;
      3) result=$(_wiz_step_storage) ;;
      4) result=$(_wiz_step_security) ;;
      5) result=$(_wiz_step_features) ;;
      6) result=$(_wiz_step_tailscale) ;;
      7)
        # Preview/confirm step
        result=$(_wiz_show_preview)
        if [[ $result == "install" ]]; then
          # Calculate derived values
          FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"

          # Calculate private network values
          if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
            PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
            PRIVATE_IP="${PRIVATE_CIDR}.1"
            SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
            PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
          fi

          clear
          return 0
        fi
        ;;
    esac

    case "$result" in
      "next")
        ((current_step++))
        ;;
      "back")
        ((current_step > 1)) && ((current_step--))
        ;;
      "quit")
        return 1
        ;;
    esac
  done
}
