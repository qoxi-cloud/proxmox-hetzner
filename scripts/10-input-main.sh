# shellcheck shell=bash
# =============================================================================
# Main input collection function
# =============================================================================

# Main entry point for input collection.
# Detects network, collects inputs interactively, and calculates derived values.
# Side effects: Sets all configuration globals
get_system_inputs() {
  detect_network_interface
  collect_network_info

  get_inputs_interactive

  # Calculate derived values
  FQDN="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"

  # Calculate private network values
  if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]]; then
    PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    PRIVATE_IP="${PRIVATE_CIDR}.1"
    SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
    PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
  fi
}
