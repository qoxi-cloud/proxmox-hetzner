# shellcheck shell=bash
# =============================================================================
# Main input collection function
# =============================================================================

# Main entry point for input collection.
# Detects network, collects inputs (wizard or non-interactive mode),
# calculates derived values, and optionally saves configuration.
# get_system_inputs collects and sets configuration globals by detecting the active network interface, gathering inputs (wizard or non-interactive), computing derived values (FQDN and private network fields when applicable), and optionally saving the configuration.
get_system_inputs() {
  log "get_system_inputs: starting"
  detect_network_interface
  log "get_system_inputs: detect_network_interface done"
  collect_network_info
  log "get_system_inputs: collect_network_info done, NON_INTERACTIVE=$NON_INTERACTIVE"

  if [[ $NON_INTERACTIVE == true ]]; then
    print_success "Network interface:" "${INTERFACE_NAME}"
    get_inputs_non_interactive
  else
    log "get_system_inputs: starting wizard"
    # Flush any pending terminal responses from stdin
    # shellcheck disable=SC2034
    read -rt 0.1 -n 10000 _discard </dev/tty 2>/dev/null || true
    # Reset terminal state and clear screen
    printf '\033[0m\033[?25h' >/dev/tty
    clear
    # Use the gum-based wizard for interactive mode
    get_inputs_wizard
    log "get_system_inputs: wizard done"
  fi

  # Calculate derived values (also done in wizard, but ensure they're set)
  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"

  # Calculate private network values
  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    PRIVATE_IP="${PRIVATE_CIDR}.1"
    SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
    PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
  fi

  # Save config if requested
  if [[ -n $SAVE_CONFIG ]]; then
    save_config "$SAVE_CONFIG"
  fi
}
