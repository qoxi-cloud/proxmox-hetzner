# shellcheck shell=bash
# =============================================================================
# Non-interactive input collection
# =============================================================================

# Helper to prompt or use existing value
prompt_or_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local current_value="${!var_name}"

    if [[ "$NON_INTERACTIVE" == true ]]; then
        if [[ -n "$current_value" ]]; then
            echo "$current_value"
        else
            echo "$default"
        fi
    else
        local result
        read -e -p "$prompt" -i "${current_value:-$default}" result
        echo "$result"
    fi
}

# =============================================================================
# Input collection - Non-interactive mode
# =============================================================================

get_inputs_non_interactive() {
    # Use defaults or config values
    PVE_HOSTNAME="${PVE_HOSTNAME:-pve-qoxi-cloud}"
    DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-local}"
    TIMEZONE="${TIMEZONE:-Europe/Kyiv}"
    EMAIL="${EMAIL:-admin@qoxi.cloud}"
    BRIDGE_MODE="${BRIDGE_MODE:-internal}"
    PRIVATE_SUBNET="${PRIVATE_SUBNET:-10.0.0.0/24}"
    DEFAULT_SHELL="${DEFAULT_SHELL:-zsh}"

    # Display configuration
    print_success "Network interface: ${INTERFACE_NAME}"
    print_success "Hostname: ${PVE_HOSTNAME}"
    print_success "Domain: ${DOMAIN_SUFFIX}"
    print_success "Timezone: ${TIMEZONE}"
    print_success "Email: ${EMAIL}"
    print_success "Bridge mode: ${BRIDGE_MODE}"

    if [[ "$BRIDGE_MODE" == "internal" || "$BRIDGE_MODE" == "both" ]]; then
        print_success "Private subnet: ${PRIVATE_SUBNET}"
    fi
    print_success "Default shell: ${DEFAULT_SHELL}"

    # ZFS RAID mode
    if [[ -z "$ZFS_RAID" ]]; then
        if [[ "${DRIVE_COUNT:-0}" -ge 2 ]]; then
            ZFS_RAID="raid1"
        else
            ZFS_RAID="single"
        fi
    fi
    print_success "ZFS mode: ${ZFS_RAID}"

    # Password - generate if not provided
    if [[ -z "$NEW_ROOT_PASSWORD" ]]; then
        NEW_ROOT_PASSWORD=$(generate_password 16)
        PASSWORD_GENERATED="yes"
        print_success "Password: auto-generated (will be shown at the end)"
    else
        if ! validate_password "$NEW_ROOT_PASSWORD"; then
            if [[ ${#NEW_ROOT_PASSWORD} -lt 8 ]]; then
                print_error "Password must be at least 8 characters long."
            else
                print_error "Password contains invalid characters (Cyrillic or non-ASCII)."
            fi
            exit 1
        fi
        print_success "Password: ******** (from env)"
    fi

    # SSH Public Key
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        SSH_PUBLIC_KEY=$(get_rescue_ssh_key)
    fi
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        print_error "SSH_PUBLIC_KEY required in non-interactive mode"
        exit 1
    fi
    parse_ssh_key "$SSH_PUBLIC_KEY"
    print_success "SSH key configured (${SSH_KEY_TYPE})"

    # Proxmox repository
    PVE_REPO_TYPE="${PVE_REPO_TYPE:-no-subscription}"
    print_success "Repository: ${PVE_REPO_TYPE}"
    if [[ "$PVE_REPO_TYPE" == "enterprise" && -n "$PVE_SUBSCRIPTION_KEY" ]]; then
        print_success "Subscription key: configured"
    fi

    # SSL certificate
    SSL_TYPE="${SSL_TYPE:-self-signed}"
    if [[ "$SSL_TYPE" == "letsencrypt" ]]; then
        local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
        local expected_ip="${MAIN_IPV4_CIDR%/*}"

        validate_dns_resolution "$le_fqdn" "$expected_ip"
        local dns_result=$?

        case $dns_result in
            0)
                print_success "SSL certificate: letsencrypt (DNS verified: ${le_fqdn} → ${expected_ip})"
                ;;
            1)
                print_error "SSL certificate: letsencrypt (DNS FAILED)"
                print_error "${le_fqdn} does not resolve"
                echo ""
                print_info "Let's Encrypt requires valid DNS configuration."
                print_info "Create DNS A record: ${le_fqdn} → ${expected_ip}"
                exit 1
                ;;
            2)
                print_error "SSL certificate: letsencrypt (DNS MISMATCH)"
                print_error "${le_fqdn} resolves to ${DNS_RESOLVED_IP}, expected ${expected_ip}"
                echo ""
                print_info "Update DNS A record: ${le_fqdn} → ${expected_ip}"
                exit 1
                ;;
        esac
    else
        print_success "SSL certificate: ${SSL_TYPE}"
    fi

    # Tailscale
    INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-no}"
    if [[ "$INSTALL_TAILSCALE" == "yes" ]]; then
        TAILSCALE_SSH="${TAILSCALE_SSH:-yes}"
        TAILSCALE_WEBUI="${TAILSCALE_WEBUI:-yes}"
        TAILSCALE_DISABLE_SSH="${TAILSCALE_DISABLE_SSH:-no}"
        if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
            print_success "Tailscale will be installed (auto-connect)"
        else
            print_success "Tailscale will be installed (manual auth required)"
        fi
        print_success "Tailscale SSH: ${TAILSCALE_SSH}"
        print_success "Tailscale WebUI: ${TAILSCALE_WEBUI}"
        if [[ "$TAILSCALE_SSH" == "yes" && "$TAILSCALE_DISABLE_SSH" == "yes" ]]; then
            print_success "OpenSSH: will be disabled on first boot"
            # Enable stealth mode when OpenSSH is disabled
            STEALTH_MODE="${STEALTH_MODE:-yes}"
            if [[ "$STEALTH_MODE" == "yes" ]]; then
                print_success "Stealth firewall: enabled"
            fi
        else
            STEALTH_MODE="${STEALTH_MODE:-no}"
        fi
    else
        STEALTH_MODE="${STEALTH_MODE:-no}"
        print_success "Tailscale: skipped"
    fi
}
