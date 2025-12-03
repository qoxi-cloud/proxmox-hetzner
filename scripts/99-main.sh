# shellcheck shell=bash
# =============================================================================
# Finish and reboot
# =============================================================================

# Truncates string with ellipsis in the middle.
# Parameters:
#   $1 - String to truncate
#   $2 - Maximum length (default: 25)
# Returns: Truncated string via stdout
truncate_middle() {
  local str="$1"
  local max_len="${2:-25}"
  local len=${#str}

  if [[ $len -le $max_len ]]; then
    echo "$str"
    return
  fi

  # Keep more chars at start, less at end
  local keep_start=$(((max_len - 3) * 2 / 3))
  local keep_end=$((max_len - 3 - keep_start))

  echo "${str:0:keep_start}...${str: -$keep_end}"
}

# Displays installation summary and prompts for system reboot.
# Shows validation results, configuration details, and access methods.
reboot_to_main_os() {
  local inner_width=$((MENU_BOX_WIDTH - 6))

  # Build summary content
  local summary=""

  # Calculate duration
  local end_time total_seconds duration
  end_time=$(date +%s)
  total_seconds=$((end_time - INSTALL_START_TIME))
  duration=$(format_duration $total_seconds)

  summary+="[OK]|Installation time|${duration}"$'\n'

  # Add validation results if available
  if [[ ${#VALIDATION_RESULTS[@]} -gt 0 ]]; then
    summary+="|--- System Checks ---|"$'\n'
    for result in "${VALIDATION_RESULTS[@]}"; do
      summary+="${result}"$'\n'
    done
  fi

  summary+="|--- Configuration ---|"$'\n'
  summary+="[OK]|CPU governor|${CPU_GOVERNOR:-performance}"$'\n'
  summary+="[OK]|Kernel params|optimized"$'\n'
  summary+="[OK]|nf_conntrack|optimized"$'\n'
  summary+="[OK]|Security updates|unattended"$'\n'
  summary+="[OK]|Monitoring tools|btop, iotop, ncdu..."$'\n'

  # Repository info
  case "${PVE_REPO_TYPE:-no-subscription}" in
    enterprise)
      summary+="[OK]|Repository|enterprise"$'\n'
      if [[ -n $PVE_SUBSCRIPTION_KEY ]]; then
        summary+="[OK]|Subscription|registered"$'\n'
      else
        summary+="[WARN]|Subscription|key not provided"$'\n'
      fi
      ;;
    test)
      summary+="[WARN]|Repository|test (unstable)"$'\n'
      ;;
    *)
      summary+="[OK]|Repository|no-subscription"$'\n'
      ;;
  esac

  # SSL certificate info (only if not in validation results)
  if [[ $SSL_TYPE == "letsencrypt" ]]; then
    summary+="[OK]|SSL auto-renewal|enabled"$'\n'
  fi

  # Tailscale status
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    summary+="[OK]|Tailscale VPN|installed"$'\n'
    if [[ -z $TAILSCALE_AUTH_KEY ]]; then
      summary+="[WARN]|Tailscale|needs auth after reboot"$'\n'
    fi
  else
    # Fail2Ban is installed when Tailscale is not used
    if [[ $FAIL2BAN_INSTALLED == "yes" ]]; then
      summary+="[OK]|Fail2Ban|SSH + Proxmox protected"$'\n'
    fi
  fi

  # Auditd status
  if [[ $AUDITD_INSTALLED == "yes" ]]; then
    summary+="[OK]|Audit logging|auditd enabled"$'\n'
  fi

  summary+="|--- Access ---|"$'\n'

  # Show generated password if applicable
  if [[ $PASSWORD_GENERATED == "yes" ]]; then
    summary+="[WARN]|Root password|${NEW_ROOT_PASSWORD}"$'\n'
  fi

  # Show access methods based on stealth mode and OpenSSH status
  if [[ $STEALTH_MODE == "yes" ]]; then
    # Stealth mode: only Tailscale access shown
    summary+="[WARN]|Public IP|BLOCKED (stealth mode)"$'\n'
    if [[ $TAILSCALE_DISABLE_SSH == "yes" ]]; then
      summary+="[WARN]|OpenSSH|DISABLED after first boot"
    fi
    if [[ $INSTALL_TAILSCALE == "yes" && -n $TAILSCALE_AUTH_KEY && $TAILSCALE_IP != "pending" && $TAILSCALE_IP != "not authenticated" ]]; then
      summary+=$'\n'"[OK]|Tailscale SSH|root@${TAILSCALE_IP}"
      if [[ -n $TAILSCALE_HOSTNAME ]]; then
        summary+=$'\n'"[OK]|Tailscale Web|$(truncate_middle "$TAILSCALE_HOSTNAME" 25)"
      else
        summary+=$'\n'"[OK]|Tailscale Web|${TAILSCALE_IP}:8006"
      fi
    fi
  else
    # Normal mode: public IP access
    summary+="[OK]|Web UI|https://${MAIN_IPV4_CIDR%/*}:8006"$'\n'
    summary+="[OK]|SSH|root@${MAIN_IPV4_CIDR%/*}"
    if [[ $INSTALL_TAILSCALE == "yes" && -n $TAILSCALE_AUTH_KEY && $TAILSCALE_IP != "pending" && $TAILSCALE_IP != "not authenticated" ]]; then
      summary+=$'\n'"[OK]|Tailscale SSH|root@${TAILSCALE_IP}"
      if [[ -n $TAILSCALE_HOSTNAME ]]; then
        summary+=$'\n'"[OK]|Tailscale Web|$(truncate_middle "$TAILSCALE_HOSTNAME" 25)"
      else
        summary+=$'\n'"[OK]|Tailscale Web|${TAILSCALE_IP}:8006"
      fi
    fi
  fi

  # Add validation summary at the end if there were issues
  if [[ $VALIDATION_FAILED -gt 0 || $VALIDATION_WARNINGS -gt 0 ]]; then
    summary+=$'\n'"|--- Validation ---|"$'\n'
    summary+="[OK]|Checks passed|${VALIDATION_PASSED}"$'\n'
    if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
      summary+="[WARN]|Warnings|${VALIDATION_WARNINGS}"$'\n'
    fi
    if [[ $VALIDATION_FAILED -gt 0 ]]; then
      summary+="[ERROR]|Failed|${VALIDATION_FAILED}"$'\n'
    fi
  fi

  # Show summarizing progress bar
  echo ""
  show_timed_progress "Summarizing..." 5

  # Clear screen and show main banner (without version info)
  clear
  show_banner --no-info

  # Display with boxes
  {
    echo "INSTALLATION SUMMARY"
    echo "$summary" | column -t -s '|' | while IFS= read -r line; do
      printf "%-${inner_width}s\n" "$line"
    done
  } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH | colorize_status
  echo ""

  # Show warning if validation failed
  if [[ $VALIDATION_FAILED -gt 0 ]]; then
    print_warning "Some validation checks failed. Review the summary above."
    echo ""
  fi

  # Show Tailscale auth instructions if needed
  if [[ $INSTALL_TAILSCALE == "yes" && -z $TAILSCALE_AUTH_KEY ]]; then
    print_warning "Tailscale needs authentication after reboot:"
    echo "    tailscale up --ssh"
    echo "    tailscale serve --bg --https=443 https://127.0.0.1:8006"
    echo ""
  fi

  # Ask user to reboot the system
  read -r -e -p "Do you want to reboot the system? (y/n): " -i "y" REBOOT
  if [[ $REBOOT == "y" ]]; then
    print_info "Rebooting the system..."
    if ! reboot; then
      log "ERROR: Failed to reboot - system may require manual restart"
      print_error "Failed to reboot the system"
      exit 1
    fi
  else
    print_info "Exiting..."
    exit 0
  fi
}

# =============================================================================
# Main execution flow
# =============================================================================

log "=========================================="
log "Proxmox VE Automated Installer v${VERSION}"
log "=========================================="
log "TEST_MODE=$TEST_MODE"
log "NON_INTERACTIVE=$NON_INTERACTIVE"
log "CONFIG_FILE=$CONFIG_FILE"
log "VALIDATE_ONLY=$VALIDATE_ONLY"
log "DRY_RUN=$DRY_RUN"
log "QEMU_RAM_OVERRIDE=$QEMU_RAM_OVERRIDE"
log "QEMU_CORES_OVERRIDE=$QEMU_CORES_OVERRIDE"
log "PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
log "SSL_TYPE=${SSL_TYPE:-self-signed}"

# Collect system info and display status
log "Step: collect_system_info"
collect_system_info
log "Step: show_system_status"
show_system_status
log "Step: get_system_inputs"
get_system_inputs

# Show configuration preview for interactive mode
if [[ $NON_INTERACTIVE != true ]]; then
  log "Step: show_configuration_review"
  show_configuration_review

  echo ""
  show_timed_progress "Configuring..." 5

  # Clear screen and show banner
  clear
  show_banner --no-info
fi

# If validate-only mode, show summary and exit
if [[ $VALIDATE_ONLY == true ]]; then
  log "Validate-only mode: showing configuration summary"
  echo ""
  echo -e "${CLR_CYAN}✓ Configuration validated successfully${CLR_RESET}"
  echo ""
  echo "Configuration Summary:"
  echo "  Hostname:     $HOSTNAME"
  echo "  FQDN:         $FQDN"
  echo "  Email:        $EMAIL"
  echo "  Timezone:     $TIMEZONE"
  echo "  IPv4:         $MAIN_IPV4_CIDR"
  echo "  Gateway:      $MAIN_IPV4_GW"
  echo "  Interface:    $INTERFACE_NAME"
  echo "  ZFS Mode:     $ZFS_RAID_MODE"
  echo "  Drives:       ${DRIVES[*]}"
  echo "  Bridge Mode:  $BRIDGE_MODE"
  if [[ $BRIDGE_MODE != "external" ]]; then
    echo "  Private Net:  $PRIVATE_SUBNET"
  fi
  echo "  Tailscale:    $INSTALL_TAILSCALE"
  echo "  Auditd:       ${INSTALL_AUDITD:-no}"
  echo "  Repository:   ${PVE_REPO_TYPE:-no-subscription}"
  echo "  SSL:          ${SSL_TYPE:-self-signed}"
  if [[ -n $PROXMOX_ISO_VERSION ]]; then
    echo "  Proxmox ISO:  ${PROXMOX_ISO_VERSION}"
  else
    echo "  Proxmox ISO:  latest"
  fi
  if [[ -n $QEMU_RAM_OVERRIDE ]]; then
    echo "  QEMU RAM:     ${QEMU_RAM_OVERRIDE}MB (override)"
  fi
  if [[ -n $QEMU_CORES_OVERRIDE ]]; then
    echo "  QEMU Cores:   ${QEMU_CORES_OVERRIDE} (override)"
  fi
  echo ""
  echo -e "${CLR_GRAY}Run without --validate to start installation${CLR_RESET}"
  exit 0
fi

# Dry-run mode: simulate installation without actual changes
if [[ $DRY_RUN == true ]]; then
  log "DRY-RUN MODE: Simulating installation"
  echo ""
  echo -e "${CLR_GRAY}═══════════════════════════════════════════════════════════${CLR_RESET}"
  echo -e "${CLR_GRAY}                    DRY-RUN MODE                            ${CLR_RESET}"
  echo -e "${CLR_GRAY}═══════════════════════════════════════════════════════════${CLR_RESET}"
  echo ""
  echo -e "${CLR_YELLOW}The following steps would be performed:${CLR_RESET}"
  echo ""

  # Simulate prepare_packages
  echo -e "${CLR_CYAN}[1/7]${CLR_RESET} prepare_packages"
  echo "      - Add Proxmox repository to apt sources"
  echo "      - Download Proxmox GPG key"
  echo "      - Update package lists"
  echo "      - Install: proxmox-auto-install-assistant xorriso ovmf wget sshpass"
  echo ""

  # Simulate download_proxmox_iso
  echo -e "${CLR_CYAN}[2/7]${CLR_RESET} download_proxmox_iso"
  if [[ -n $PROXMOX_ISO_VERSION ]]; then
    echo "      - Download ISO: ${PROXMOX_ISO_VERSION}"
  else
    echo "      - Download latest Proxmox VE ISO"
  fi
  echo "      - Verify SHA256 checksum"
  echo ""

  # Simulate make_answer_toml
  echo -e "${CLR_CYAN}[3/7]${CLR_RESET} make_answer_toml"
  echo "      - Generate answer.toml with:"
  echo "        FQDN:     $FQDN"
  echo "        Email:    $EMAIL"
  echo "        Timezone: $TIMEZONE"
  echo "        ZFS RAID: ${ZFS_RAID:-raid1}"
  echo ""

  # Simulate make_autoinstall_iso
  echo -e "${CLR_CYAN}[4/7]${CLR_RESET} make_autoinstall_iso"
  echo "      - Create pve-autoinstall.iso with embedded answer.toml"
  echo ""

  # Simulate install_proxmox
  echo -e "${CLR_CYAN}[5/7]${CLR_RESET} install_proxmox"
  echo "      - Release drives: ${DRIVES[*]}"
  echo "      - Start QEMU with:"
  dry_run_cores=$(($(nproc) / 2))
  [[ $dry_run_cores -lt $MIN_CPU_CORES ]] && dry_run_cores=$MIN_CPU_CORES
  [[ $dry_run_cores -gt $MAX_QEMU_CORES ]] && dry_run_cores=$MAX_QEMU_CORES
  dry_run_ram=$DEFAULT_QEMU_RAM
  [[ -n $QEMU_RAM_OVERRIDE ]] && dry_run_ram=$QEMU_RAM_OVERRIDE
  [[ -n $QEMU_CORES_OVERRIDE ]] && dry_run_cores=$QEMU_CORES_OVERRIDE
  echo "        vCPUs: ${dry_run_cores}"
  echo "        RAM:   ${dry_run_ram}MB"
  echo "      - Boot from autoinstall ISO"
  echo "      - Install Proxmox to drives"
  echo ""

  # Simulate boot_proxmox_with_port_forwarding
  echo -e "${CLR_CYAN}[6/7]${CLR_RESET} boot_proxmox_with_port_forwarding"
  echo "      - Boot installed system in QEMU"
  echo "      - Forward SSH port 5555 -> 22"
  echo "      - Wait for SSH to be ready"
  echo ""

  # Simulate configure_proxmox_via_ssh
  echo -e "${CLR_CYAN}[7/7]${CLR_RESET} configure_proxmox_via_ssh"
  echo "      - Configure network interfaces (bridge mode: $BRIDGE_MODE)"
  echo "      - Configure ZFS ARC limits"
  echo "      - Install system utilities: ${SYSTEM_UTILITIES}"
  echo "      - Configure shell: ${DEFAULT_SHELL:-zsh}"
  echo "      - Configure repository: ${PVE_REPO_TYPE:-no-subscription}"
  echo "      - Configure SSL: ${SSL_TYPE:-self-signed}"
  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    echo "      - Install and configure Tailscale VPN"
    [[ $STEALTH_MODE == "yes" ]] && echo "      - Enable stealth mode (block public IP)"
  else
    echo "      - Install Fail2Ban (SSH + Proxmox API brute-force protection)"
  fi
  if [[ $INSTALL_AUDITD == "yes" ]]; then
    echo "      - Install and configure auditd (audit logging)"
  fi
  echo "      - Harden SSH configuration"
  echo "      - Deploy SSH public key"
  echo ""

  echo -e "${CLR_GRAY}═══════════════════════════════════════════════════════════${CLR_RESET}"
  echo ""
  echo -e "${CLR_CYAN}Configuration Summary:${CLR_RESET}"
  echo "  Hostname:     $HOSTNAME"
  echo "  FQDN:         $FQDN"
  echo "  Email:        $EMAIL"
  echo "  Timezone:     $TIMEZONE"
  echo "  IPv4:         $MAIN_IPV4_CIDR"
  echo "  Gateway:      $MAIN_IPV4_GW"
  echo "  Interface:    $INTERFACE_NAME"
  echo "  ZFS Mode:     ${ZFS_RAID_MODE:-auto}"
  echo "  Drives:       ${DRIVES[*]}"
  echo "  Bridge Mode:  $BRIDGE_MODE"
  if [[ $BRIDGE_MODE != "external" ]]; then
    echo "  Private Net:  $PRIVATE_SUBNET"
  fi
  echo "  Tailscale:    ${INSTALL_TAILSCALE:-no}"
  echo "  Auditd:       ${INSTALL_AUDITD:-no}"
  echo "  Repository:   ${PVE_REPO_TYPE:-no-subscription}"
  echo "  SSL:          ${SSL_TYPE:-self-signed}"
  echo ""
  echo -e "${CLR_GRAY}═══════════════════════════════════════════════════════════${CLR_RESET}"
  echo ""
  echo -e "${CLR_CYAN}✓ Dry-run completed successfully${CLR_RESET}"
  echo -e "${CLR_YELLOW}Run without --dry-run to perform actual installation${CLR_RESET}"
  echo ""

  # Mark as completed (prevents error handler)
  INSTALL_COMPLETED=true
  exit 0
fi

log "Step: prepare_packages"
prepare_packages
log "Step: download_proxmox_iso"
download_proxmox_iso
log "Step: make_answer_toml"
make_answer_toml
log "Step: make_autoinstall_iso"
make_autoinstall_iso
log "Step: install_proxmox"
install_proxmox

# Boot and configure via SSH
log "Step: boot_proxmox_with_port_forwarding"
boot_proxmox_with_port_forwarding || {
  log "ERROR: Failed to boot Proxmox with port forwarding"
  exit 1
}

# Configure Proxmox via SSH
log "Step: configure_proxmox_via_ssh"
configure_proxmox_via_ssh

# Mark installation as completed (disables error handler message)
INSTALL_COMPLETED=true

# Reboot to the main OS
log "Step: reboot_to_main_os"
reboot_to_main_os
