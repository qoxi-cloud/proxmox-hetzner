# shellcheck shell=bash
# =============================================================================
# Interactive input collection
# =============================================================================

get_inputs_interactive() {
    # =========================================================================
    # SECTION 1: Text inputs
    # =========================================================================

    # Network interface
    print_warning "Use the predictable name (enp*, eno*) for bare metal, not eth0"
    local iface_prompt="Interface name (options: ${AVAILABLE_ALTNAMES}): "
    read -e -p "$iface_prompt" -i "$INTERFACE_NAME" INTERFACE_NAME
    printf "\033[A\r${CLR_GREEN}✓${CLR_RESET} ${iface_prompt}${INTERFACE_NAME}\033[K\n"

    # Hostname
    if [[ -n "$PVE_HOSTNAME" ]]; then
        print_success "Hostname: ${PVE_HOSTNAME} (from env)"
    else
        prompt_with_validation \
            "Enter your hostname (e.g., pve, proxmox): " \
            "pve-qoxi-cloud" \
            "validate_hostname" \
            "Invalid hostname. Use only letters, numbers, and hyphens (1-63 chars)." \
            "PVE_HOSTNAME"
    fi

    # Domain
    if [[ -n "$DOMAIN_SUFFIX" ]]; then
        print_success "Domain: ${DOMAIN_SUFFIX} (from env)"
    else
        local domain_prompt="Enter domain suffix: "
        read -e -p "$domain_prompt" -i "local" DOMAIN_SUFFIX
        printf "\033[A\r${CLR_GREEN}✓${CLR_RESET} ${domain_prompt}${DOMAIN_SUFFIX}\033[K\n"
    fi

    # Email
    if [[ -n "$EMAIL" ]]; then
        print_success "Email: ${EMAIL} (from env)"
    else
        prompt_with_validation \
            "Enter your email address: " \
            "admin@qoxi.cloud" \
            "validate_email" \
            "Invalid email address format." \
            "EMAIL"
    fi

    # Password
    if [[ -n "$NEW_ROOT_PASSWORD" ]]; then
        if ! validate_password "$NEW_ROOT_PASSWORD"; then
            if [[ ${#NEW_ROOT_PASSWORD} -lt 8 ]]; then
                print_error "Password must be at least 8 characters long."
            else
                print_error "Password contains invalid characters (Cyrillic or non-ASCII)."
                print_error "Only Latin letters, digits, and special characters are allowed."
            fi
            exit 1
        fi
        print_success "Password: ******** (from env)"
    else
        echo -n "Enter root password (or press Enter to auto-generate): "
        local input_password
        input_password=$(read_password "")
        # Move cursor up and clear the prompt line
        printf "\033[A\r\033[K"
        if [[ -z "$input_password" ]]; then
            NEW_ROOT_PASSWORD=$(generate_password 16)
            PASSWORD_GENERATED="yes"
            print_success "Password: auto-generated (will be shown at the end)"
        else
            while ! validate_password "$input_password"; do
                if [[ ${#input_password} -lt 8 ]]; then
                    print_error "Password must be at least 8 characters long."
                else
                    print_error "Password contains invalid characters (Cyrillic or non-ASCII)."
                fi
                input_password=$(read_password "Enter root password: ")
            done
            NEW_ROOT_PASSWORD="$input_password"
            print_success "Password: ********"
        fi
    fi

    # =========================================================================
    # SECTION 2: Interactive menus
    # =========================================================================

    # --- Proxmox ISO Version ---
    if [[ -n "$PROXMOX_ISO_VERSION" ]]; then
        print_success "Proxmox ISO: ${PROXMOX_ISO_VERSION} (from env/cli)"
    else
        # Fetch available ISO versions
        printf "%s⠋ Fetching available Proxmox versions...%s" "${CLR_YELLOW}" "${CLR_RESET}"
        local iso_list
        iso_list=$(get_available_proxmox_isos 5)
        printf "\r\e[K"

        if [[ -z "$iso_list" ]]; then
            print_warning "Could not fetch ISO list, will use latest"
            PROXMOX_ISO_VERSION=""
        else
            # Convert to array
            local -a iso_array
            local -a iso_menu_items
            local first=true
            while IFS= read -r iso; do
                iso_array+=("$iso")
                local version
                version=$(get_iso_version "$iso")
                if [[ "$first" == true ]]; then
                    iso_menu_items+=("Proxmox VE ${version}|Latest version (recommended)")
                    first=false
                else
                    iso_menu_items+=("Proxmox VE ${version}|")
                fi
            done <<< "$iso_list"

            interactive_menu \
                "Proxmox VE Version (↑/↓ select, Enter confirm)" \
                "Select which Proxmox VE version to install" \
                "${iso_menu_items[@]}"

            PROXMOX_ISO_VERSION="${iso_array[$MENU_SELECTED]}"
            local selected_version
            selected_version=$(get_iso_version "$PROXMOX_ISO_VERSION")
            if [[ $MENU_SELECTED -eq 0 ]]; then
                print_success "Proxmox VE: ${selected_version} (latest)"
            else
                print_success "Proxmox VE: ${selected_version}"
            fi
        fi
    fi

    # --- Timezone ---
    if [[ -n "$TIMEZONE" ]]; then
        print_success "Timezone: ${TIMEZONE} (from env)"
    else
        local tz_options=("Europe/Kyiv" "Europe/London" "Europe/Berlin" "America/New_York" "America/Los_Angeles" "Asia/Tokyo" "UTC" "custom")

        interactive_menu \
            "Timezone (↑/↓ select, Enter confirm)" \
            "" \
            "Europe/Kyiv|Ukraine" \
            "Europe/London|United Kingdom (GMT/BST)" \
            "Europe/Berlin|Germany, Central Europe (CET/CEST)" \
            "America/New_York|US Eastern Time (EST/EDT)" \
            "America/Los_Angeles|US Pacific Time (PST/PDT)" \
            "Asia/Tokyo|Japan Standard Time (JST)" \
            "UTC|Coordinated Universal Time" \
            "Custom|Enter timezone manually"

        if [[ $MENU_SELECTED -eq 7 ]]; then
            prompt_with_validation \
                "Enter your timezone: " \
                "Europe/Kyiv" \
                "validate_timezone" \
                "Invalid timezone. Use format like: Europe/London, America/New_York" \
                "TIMEZONE"
        else
            TIMEZONE="${tz_options[$MENU_SELECTED]}"
            print_success "Timezone: ${TIMEZONE}"
        fi
    fi

    # --- Bridge mode ---
    if [[ -n "$BRIDGE_MODE" ]]; then
        print_success "Bridge mode: ${BRIDGE_MODE} (from env)"
    else
        local bridge_options=("internal" "external" "both")
        local bridge_header="Configure network bridges for VMs and containers"$'\n'
        bridge_header+="vmbr0 = external (bridged to physical NIC)"$'\n'
        bridge_header+="vmbr1 = internal (NAT with private subnet)"

        interactive_menu \
            "Network Bridge Mode (↑/↓ select, Enter confirm)" \
            "$bridge_header" \
            "Internal only (NAT)|VMs use private IPs with NAT to internet" \
            "External only (Bridged)|VMs get IPs from your router/DHCP" \
            "Both bridges|Internal NAT + External bridged network"

        BRIDGE_MODE="${bridge_options[$MENU_SELECTED]}"
        case "$BRIDGE_MODE" in
            internal) print_success "Bridge mode: Internal NAT only (vmbr0)" ;;
            external) print_success "Bridge mode: External bridged only (vmbr0)" ;;
            both)     print_success "Bridge mode: Both (vmbr0=external, vmbr1=internal)" ;;
        esac
    fi

    # --- Private subnet ---
    if [[ "$BRIDGE_MODE" == "internal" || "$BRIDGE_MODE" == "both" ]]; then
        if [[ -n "$PRIVATE_SUBNET" ]]; then
            print_success "Private subnet: ${PRIVATE_SUBNET} (from env)"
        else
            local subnet_options=("10.0.0.0/24" "192.168.1.0/24" "172.16.0.0/24" "custom")

            interactive_menu \
                "Private Subnet (↑/↓ select, Enter confirm)" \
                "Internal network for VMs and containers" \
                "10.0.0.0/24|Class A private (recommended)" \
                "192.168.1.0/24|Class C private (common home network)" \
                "172.16.0.0/24|Class B private" \
                "Custom|Enter subnet manually"

            if [[ $MENU_SELECTED -eq 3 ]]; then
                prompt_with_validation \
                    "Enter your private subnet: " \
                    "10.0.0.0/24" \
                    "validate_subnet" \
                    "Invalid subnet. Use CIDR format like: 10.0.0.0/24" \
                    "PRIVATE_SUBNET"
            else
                PRIVATE_SUBNET="${subnet_options[$MENU_SELECTED]}"
                print_success "Private subnet: ${PRIVATE_SUBNET}"
            fi
        fi
    fi

    # --- ZFS RAID mode ---
    if [[ "${DRIVE_COUNT:-0}" -ge 2 ]]; then
        if [[ -n "$ZFS_RAID" ]]; then
            print_success "ZFS mode: ${ZFS_RAID} (from env)"
        else
            local zfs_options=("raid1" "raid0" "single")
            local zfs_labels=("RAID-1 (mirror) - Recommended" "RAID-0 (stripe) - No redundancy" "Single drive - No redundancy")

            interactive_menu \
                "ZFS Storage Mode (↑/↓ select, Enter confirm)" \
                "" \
                "${zfs_labels[0]}|Survives 1 disk failure" \
                "${zfs_labels[1]}|2x space & speed, data loss if any disk fails" \
                "${zfs_labels[2]}|Uses first drive only, ignores other drives"

            ZFS_RAID="${zfs_options[$MENU_SELECTED]}"
            print_success "ZFS mode: ${zfs_labels[$MENU_SELECTED]}"
        fi
    else
        # Single drive - no RAID options available
        if [[ -n "$ZFS_RAID" ]]; then
            print_success "ZFS mode: ${ZFS_RAID} (from env)"
        else
            ZFS_RAID="single"
            print_success "ZFS mode: single (1 drive detected)"
        fi
    fi

    # --- Default Shell ---
    if [[ -n "$DEFAULT_SHELL" ]]; then
        print_success "Default shell: ${DEFAULT_SHELL} (from env)"
    else
        local shell_options=("zsh" "bash")
        local shell_header="Select the default shell for root user."$'\n'
        shell_header+="ZSH includes autosuggestions and syntax highlighting."

        interactive_menu \
            "Default Shell (↑/↓ select, Enter confirm)" \
            "$shell_header" \
            "ZSH|Modern shell with plugins (recommended)" \
            "Bash|Default system shell"

        DEFAULT_SHELL="${shell_options[$MENU_SELECTED]}"
        print_success "Default shell: ${DEFAULT_SHELL}"
    fi

    # --- SSH Public Key ---
    if [[ -n "$SSH_PUBLIC_KEY" ]]; then
        parse_ssh_key "$SSH_PUBLIC_KEY"
        print_success "SSH key: ${SSH_KEY_TYPE} (from env)"
    else
        local DETECTED_SSH_KEY
        DETECTED_SSH_KEY=$(get_rescue_ssh_key)

        if [[ -n "$DETECTED_SSH_KEY" ]]; then
            parse_ssh_key "$DETECTED_SSH_KEY"

            local ssh_header="! Password authentication will be DISABLED"$'\n'
            ssh_header+="Detected key from Rescue System:"$'\n'
            ssh_header+="  Type:    ${SSH_KEY_TYPE}"$'\n'
            ssh_header+="  Key:     ${SSH_KEY_SHORT}"
            if [[ -n "$SSH_KEY_COMMENT" ]]; then
                ssh_header+=$'\n'"  Comment: ${SSH_KEY_COMMENT}"
            fi

            interactive_menu \
                "SSH Public Key (↑/↓ select, Enter confirm)" \
                "$ssh_header" \
                "Use detected key|Recommended - already configured in Hetzner" \
                "Enter different key|Paste your own SSH public key"

            if [[ $MENU_SELECTED -eq 0 ]]; then
                SSH_PUBLIC_KEY="$DETECTED_SSH_KEY"
                print_success "SSH key configured (${SSH_KEY_TYPE})"
            else
                SSH_PUBLIC_KEY=""
            fi
        fi

        # Manual entry if no key yet
        if [[ -z "$SSH_PUBLIC_KEY" ]]; then
            local ssh_content="! Password authentication will be DISABLED"$'\n'
            if [[ -z "$DETECTED_SSH_KEY" ]]; then
                ssh_content+=$'\n'"No SSH key detected in Rescue System."
            fi
            ssh_content+=$'\n'$'\n'"Paste your SSH public key below:"$'\n'
            ssh_content+="(Usually from ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)"

            input_box "SSH Public Key Configuration" "$ssh_content" "SSH Public Key: " ""

            while [[ -z "$INPUT_VALUE" ]] || ! validate_ssh_key "$INPUT_VALUE"; do
                if [[ -z "$INPUT_VALUE" ]]; then
                    print_error "SSH public key is required for secure access!"
                else
                    print_warning "SSH key format may be invalid. Continue anyway? (y/n): "
                    read -rsn1 confirm
                    echo ""
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        break
                    fi
                fi
                input_box "SSH Public Key Configuration" "$ssh_content" "SSH Public Key: " ""
            done

            SSH_PUBLIC_KEY="$INPUT_VALUE"
            parse_ssh_key "$SSH_PUBLIC_KEY"
            print_success "SSH key configured (${SSH_KEY_TYPE})"
        fi
    fi

    # --- Tailscale ---
    if [[ -n "$INSTALL_TAILSCALE" ]]; then
        if [[ "$INSTALL_TAILSCALE" == "yes" ]]; then
            TAILSCALE_SSH="${TAILSCALE_SSH:-yes}"
            TAILSCALE_WEBUI="${TAILSCALE_WEBUI:-yes}"
            if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
                print_success "Tailscale: yes (auto-connect, from env)"
            else
                print_success "Tailscale: yes (manual auth, from env)"
            fi
        else
            TAILSCALE_AUTH_KEY=""
            TAILSCALE_SSH="no"
            TAILSCALE_WEBUI="no"
            print_success "Tailscale: skipped (from env)"
        fi
    else
        local ts_header="Tailscale provides secure remote access to your server."$'\n'
        ts_header+="Auth key: https://login.tailscale.com/admin/settings/keys"

        interactive_menu \
            "Tailscale VPN - Optional (↑/↓ select, Enter confirm)" \
            "$ts_header" \
            "Install Tailscale|Recommended for secure remote access" \
            "Skip installation|Install Tailscale later if needed"

        if [[ $MENU_SELECTED -eq 0 ]]; then
            INSTALL_TAILSCALE="yes"
            TAILSCALE_SSH="yes"
            TAILSCALE_WEBUI="yes"
            TAILSCALE_DISABLE_SSH="no"

            if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
                local auth_content="Auth key enables automatic configuration."$'\n'
                auth_content+="Leave empty for manual auth after reboot."$'\n'
                auth_content+=$'\n'
                auth_content+="For unattended setup, use a reusable auth key"$'\n'
                auth_content+="with tags and expiry for better security."

                input_box "Tailscale Auth Key (optional)" "$auth_content" "Auth Key: " ""
                TAILSCALE_AUTH_KEY="$INPUT_VALUE"
            fi

            if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
                # Auto-enable security features when auth key is provided
                TAILSCALE_DISABLE_SSH="yes"
                STEALTH_MODE="yes"
                print_success "Tailscale will be installed (auto-connect)"
                print_success "OpenSSH will be disabled on first boot"
                print_success "Stealth firewall will be enabled (server hidden from internet)"
            else
                print_success "Tailscale will be installed (manual auth required)"
                STEALTH_MODE="no"
            fi
        else
            INSTALL_TAILSCALE="no"
            TAILSCALE_AUTH_KEY=""
            TAILSCALE_SSH="no"
            TAILSCALE_WEBUI="no"
            TAILSCALE_DISABLE_SSH="no"
            STEALTH_MODE="no"
            print_success "Tailscale installation skipped"
        fi
    fi
}
