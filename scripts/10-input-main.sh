# shellcheck shell=bash
# =============================================================================
# Main input collection function
# =============================================================================

get_system_inputs() {
    detect_network_interface
    collect_network_info

    if [[ "$NON_INTERACTIVE" == true ]]; then
        print_success "Network interface: ${INTERFACE_NAME}"
        get_inputs_non_interactive
    else
        get_inputs_interactive
    fi

    # Calculate derived values
    FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"

    # Calculate private network values
    if [[ "$BRIDGE_MODE" == "internal" || "$BRIDGE_MODE" == "both" ]]; then
        PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
        PRIVATE_IP="${PRIVATE_CIDR}.1"
        SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
        PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
    fi

    # Save config if requested
    if [[ -n "$SAVE_CONFIG" ]]; then
        save_config "$SAVE_CONFIG"
    fi
}
