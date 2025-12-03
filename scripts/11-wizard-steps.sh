# shellcheck shell=bash
# =============================================================================
# Gum-based wizard UI - Step implementations
# =============================================================================
# Provides wizard step implementations for each configuration category:
# System, Network, Storage, Security, Features, Tailscale.

# =============================================================================
# Wizard Step Options
# =============================================================================

# Timezone options for the wizard
WIZ_TIMEZONES=(
    "Europe/Kyiv"
    "Europe/London"
    "Europe/Berlin"
    "America/New_York"
    "America/Los_Angeles"
    "Asia/Tokyo"
    "UTC"
)

# Bridge mode options
WIZ_BRIDGE_MODES=("internal" "external" "both")
WIZ_BRIDGE_LABELS=("Internal NAT" "External (bridged)" "Both")

# Private subnet options
WIZ_SUBNETS=("10.0.0.0/24" "192.168.1.0/24" "172.16.0.0/24")

# IPv6 mode options
WIZ_IPV6_MODES=("auto" "manual" "disabled")
WIZ_IPV6_LABELS=("Auto-detect" "Manual" "Disabled")

# ZFS RAID options
WIZ_ZFS_MODES=("raid1" "raid0" "single")
WIZ_ZFS_LABELS=("RAID-1 (mirror)" "RAID-0 (stripe)" "Single drive")

# Repository options
WIZ_REPO_TYPES=("no-subscription" "enterprise" "test")
WIZ_REPO_LABELS=("No-Subscription" "Enterprise" "Test")

# SSL options
WIZ_SSL_TYPES=("self-signed" "letsencrypt")
WIZ_SSL_LABELS=("Self-signed" "Let's Encrypt")

# CPU governor options
WIZ_GOVERNORS=("performance" "ondemand" "powersave" "schedutil" "conservative")

# =============================================================================
# Step 1: System Configuration
# _wiz_step_system collects and persists core system settings (hostname, domain, email, root password, timezone) using an interactive wizard step.
# If the root password is left empty it generates one and sets PASSWORD_GENERATED="yes"; the function echoes the interaction result (e.g., "next", "back").
_wiz_step_system() {
    _wiz_clear_fields
    _wiz_add_field "Hostname" "input" "${PVE_HOSTNAME:-pve}" "validate_hostname"
    _wiz_add_field "Domain" "input" "${DOMAIN_SUFFIX:-local}"
    _wiz_add_field "Email" "input" "${EMAIL:-admin@example.com}" "validate_email"
    _wiz_add_field "Password" "password" ""
    _wiz_add_field "Timezone" "choose" "$(IFS='|'; echo "${WIZ_TIMEZONES[*]}")"

    # Pre-fill values if already set
    [[ -n "$PVE_HOSTNAME" ]] && WIZ_FIELD_VALUES[0]="$PVE_HOSTNAME"
    [[ -n "$DOMAIN_SUFFIX" ]] && WIZ_FIELD_VALUES[1]="$DOMAIN_SUFFIX"
    [[ -n "$EMAIL" ]] && WIZ_FIELD_VALUES[2]="$EMAIL"
    [[ -n "$NEW_ROOT_PASSWORD" ]] && WIZ_FIELD_VALUES[3]="$NEW_ROOT_PASSWORD"
    [[ -n "$TIMEZONE" ]] && WIZ_FIELD_VALUES[4]="$TIMEZONE"

    local result
    result=$(wiz_step_interactive 1 "System")

    if [[ "$result" == "next" ]]; then
        PVE_HOSTNAME="${WIZ_FIELD_VALUES[0]}"
        DOMAIN_SUFFIX="${WIZ_FIELD_VALUES[1]}"
        EMAIL="${WIZ_FIELD_VALUES[2]}"
        NEW_ROOT_PASSWORD="${WIZ_FIELD_VALUES[3]}"
        TIMEZONE="${WIZ_FIELD_VALUES[4]}"

        # Generate password if empty
        if [[ -z "$NEW_ROOT_PASSWORD" ]]; then
            NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
            PASSWORD_GENERATED="yes"
        fi
    fi

    echo "$result"
}

# =============================================================================
# Step 2: Network Configuration
# _wiz_step_network builds and presents the Network wizard step, handling interface, bridge mode, private subnet, and IPv6 choices.
# It maps between human-readable labels and internal mode codes, updates IPv6-related variables when IPv6 is disabled or defaulted, and echoes the step result string.
_wiz_step_network() {
    _wiz_clear_fields

    # Build bridge mode options string
    local bridge_opts=""
    for i in "${!WIZ_BRIDGE_LABELS[@]}"; do
        [[ -n "$bridge_opts" ]] && bridge_opts+="|"
        bridge_opts+="${WIZ_BRIDGE_LABELS[$i]}"
    done

    # Build subnet options string
    local subnet_opts=""
    for s in "${WIZ_SUBNETS[@]}"; do
        [[ -n "$subnet_opts" ]] && subnet_opts+="|"
        subnet_opts+="$s"
    done

    # Build IPv6 mode options
    local ipv6_opts=""
    for i in "${!WIZ_IPV6_LABELS[@]}"; do
        [[ -n "$ipv6_opts" ]] && ipv6_opts+="|"
        ipv6_opts+="${WIZ_IPV6_LABELS[$i]}"
    done

    _wiz_add_field "Interface" "input" "${INTERFACE_NAME:-eth0}"
    _wiz_add_field "Bridge mode" "choose" "$bridge_opts"
    _wiz_add_field "Private subnet" "choose" "$subnet_opts"
    _wiz_add_field "IPv6" "choose" "$ipv6_opts"

    # Pre-fill values
    [[ -n "$INTERFACE_NAME" ]] && WIZ_FIELD_VALUES[0]="$INTERFACE_NAME"
    if [[ -n "$BRIDGE_MODE" ]]; then
        for i in "${!WIZ_BRIDGE_MODES[@]}"; do
            [[ "${WIZ_BRIDGE_MODES[$i]}" == "$BRIDGE_MODE" ]] && WIZ_FIELD_VALUES[1]="${WIZ_BRIDGE_LABELS[$i]}"
        done
    fi
    if [[ -n "$PRIVATE_SUBNET" ]]; then
        WIZ_FIELD_VALUES[2]="$PRIVATE_SUBNET"
    fi
    if [[ -n "$IPV6_MODE" ]]; then
        for i in "${!WIZ_IPV6_MODES[@]}"; do
            [[ "${WIZ_IPV6_MODES[$i]}" == "$IPV6_MODE" ]] && WIZ_FIELD_VALUES[3]="${WIZ_IPV6_LABELS[$i]}"
        done
    fi

    local result
    result=$(wiz_step_interactive 2 "Network")

    if [[ "$result" == "next" ]]; then
        INTERFACE_NAME="${WIZ_FIELD_VALUES[0]}"

        # Convert bridge label back to mode
        local bridge_label="${WIZ_FIELD_VALUES[1]}"
        for i in "${!WIZ_BRIDGE_LABELS[@]}"; do
            [[ "${WIZ_BRIDGE_LABELS[$i]}" == "$bridge_label" ]] && BRIDGE_MODE="${WIZ_BRIDGE_MODES[$i]}"
        done

        PRIVATE_SUBNET="${WIZ_FIELD_VALUES[2]}"

        # Convert IPv6 label back to mode
        local ipv6_label="${WIZ_FIELD_VALUES[3]}"
        for i in "${!WIZ_IPV6_LABELS[@]}"; do
            [[ "${WIZ_IPV6_LABELS[$i]}" == "$ipv6_label" ]] && IPV6_MODE="${WIZ_IPV6_MODES[$i]}"
        done

        # Apply IPv6 settings
        if [[ "$IPV6_MODE" == "disabled" ]]; then
            MAIN_IPV6=""
            IPV6_GATEWAY=""
            FIRST_IPV6_CIDR=""
        else
            IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
        fi
    fi

    echo "$result"
}

# =============================================================================
# Step 3: Storage Configuration
# _wiz_step_storage collects storage configuration (ZFS mode, repository, Proxmox version) and applies the selected values to the environment.
# 
# Prefills fields from ZFS_RAID, PVE_REPO_TYPE, and PROXMOX_ISO_VERSION when available, presents a step to the user, and
# when the user proceeds updates:
# - ZFS_RAID to the chosen ZFS mode (or "single" if DRIVE_COUNT < 2),
# - PVE_REPO_TYPE to the chosen repository type,
# - PROXMOX_ISO_VERSION when a value other than "latest" is provided.
# 
# Echoes the interaction result string (e.g., "next" or other flow outcomes).
_wiz_step_storage() {
    _wiz_clear_fields

    # Build ZFS options based on drive count
    local zfs_opts=""
    if [[ "${DRIVE_COUNT:-0}" -ge 2 ]]; then
        for i in "${!WIZ_ZFS_LABELS[@]}"; do
            [[ -n "$zfs_opts" ]] && zfs_opts+="|"
            zfs_opts+="${WIZ_ZFS_LABELS[$i]}"
        done
    else
        zfs_opts="Single drive"
    fi

    # Build repo options
    local repo_opts=""
    for i in "${!WIZ_REPO_LABELS[@]}"; do
        [[ -n "$repo_opts" ]] && repo_opts+="|"
        repo_opts+="${WIZ_REPO_LABELS[$i]}"
    done

    _wiz_add_field "ZFS mode" "choose" "$zfs_opts"
    _wiz_add_field "Repository" "choose" "$repo_opts"
    _wiz_add_field "Proxmox version" "input" "${PROXMOX_ISO_VERSION:-latest}"

    # Pre-fill values
    if [[ -n "$ZFS_RAID" ]]; then
        for i in "${!WIZ_ZFS_MODES[@]}"; do
            [[ "${WIZ_ZFS_MODES[$i]}" == "$ZFS_RAID" ]] && WIZ_FIELD_VALUES[0]="${WIZ_ZFS_LABELS[$i]}"
        done
    fi
    if [[ -n "$PVE_REPO_TYPE" ]]; then
        for i in "${!WIZ_REPO_TYPES[@]}"; do
            [[ "${WIZ_REPO_TYPES[$i]}" == "$PVE_REPO_TYPE" ]] && WIZ_FIELD_VALUES[1]="${WIZ_REPO_LABELS[$i]}"
        done
    fi
    [[ -n "$PROXMOX_ISO_VERSION" ]] && WIZ_FIELD_VALUES[2]="$PROXMOX_ISO_VERSION"

    local result
    result=$(wiz_step_interactive 3 "Storage")

    if [[ "$result" == "next" ]]; then
        # Convert ZFS label back to mode
        local zfs_label="${WIZ_FIELD_VALUES[0]}"
        if [[ "${DRIVE_COUNT:-0}" -ge 2 ]]; then
            for i in "${!WIZ_ZFS_LABELS[@]}"; do
                [[ "${WIZ_ZFS_LABELS[$i]}" == "$zfs_label" ]] && ZFS_RAID="${WIZ_ZFS_MODES[$i]}"
            done
        else
            ZFS_RAID="single"
        fi

        # Convert repo label back to type
        local repo_label="${WIZ_FIELD_VALUES[1]}"
        for i in "${!WIZ_REPO_LABELS[@]}"; do
            [[ "${WIZ_REPO_LABELS[$i]}" == "$repo_label" ]] && PVE_REPO_TYPE="${WIZ_REPO_TYPES[$i]}"
        done

        local pve_version="${WIZ_FIELD_VALUES[2]}"
        [[ "$pve_version" != "latest" ]] && PROXMOX_ISO_VERSION="$pve_version"
    fi

    echo "$result"
}

# =============================================================================
# Step 4: Security Configuration
# _wiz_step_security Presents the Security step fields (SSH key and SSL certificate) for the interactive wizard and persists the chosen values.
# 
# When a detected SSH public key is available it pre-fills the SSH field and stores the raw key as a default; when the user proceeds the chosen SSH key is written to SSH_PUBLIC_KEY and the selected SSL label is mapped back to SSL_TYPE.
# 
# Echoes the step navigation result string (for example `next` when the user proceeds).
_wiz_step_security() {
    _wiz_clear_fields

    # Build SSL options
    local ssl_opts=""
    for i in "${!WIZ_SSL_LABELS[@]}"; do
        [[ -n "$ssl_opts" ]] && ssl_opts+="|"
        ssl_opts+="${WIZ_SSL_LABELS[$i]}"
    done

    # Get detected SSH key
    local detected_key=""
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        detected_key=$(get_rescue_ssh_key 2>/dev/null || true)
    else
        detected_key="$SSH_PUBLIC_KEY"
    fi

    _wiz_add_field "SSH key" "input" "" "validate_ssh_key"
    _wiz_add_field "SSL certificate" "choose" "$ssl_opts"

    # Pre-fill values
    if [[ -n "$detected_key" ]]; then
        parse_ssh_key "$detected_key"
        WIZ_FIELD_VALUES[0]="${SSH_KEY_TYPE:-ssh-key} (${SSH_KEY_SHORT:-detected})"
        WIZ_FIELD_DEFAULTS[0]="$detected_key"
    fi
    if [[ -n "$SSL_TYPE" ]]; then
        for i in "${!WIZ_SSL_TYPES[@]}"; do
            [[ "${WIZ_SSL_TYPES[$i]}" == "$SSL_TYPE" ]] && WIZ_FIELD_VALUES[1]="${WIZ_SSL_LABELS[$i]}"
        done
    fi

    local result
    result=$(wiz_step_interactive 4 "Security")

    if [[ "$result" == "next" ]]; then
        # Handle SSH key
        local ssh_value="${WIZ_FIELD_VALUES[0]}"
        if [[ "$ssh_value" == *"(detected)"* || "$ssh_value" == *"ssh-"* ]]; then
            SSH_PUBLIC_KEY="${WIZ_FIELD_DEFAULTS[0]:-$detected_key}"
        else
            SSH_PUBLIC_KEY="$ssh_value"
        fi

        # Convert SSL label back to type
        local ssl_label="${WIZ_FIELD_VALUES[1]}"
        for i in "${!WIZ_SSL_LABELS[@]}"; do
            [[ "${WIZ_SSL_LABELS[$i]}" == "$ssl_label" ]] && SSL_TYPE="${WIZ_SSL_TYPES[$i]}"
        done
    fi

    echo "$result"
}

# =============================================================================
# Step 5: Features Configuration
# _wiz_step_features builds and displays the "Features" wizard step, prefilling feature-related fields, running the interactive prompt, and persisting chosen settings.
# It defines fields for default shell, CPU governor, bandwidth monitor, auto-updates, and audit logging; pre-fills them from environment defaults; invokes the interactive step; if the user advances, saves selections into DEFAULT_SHELL, CPU_GOVERNOR, INSTALL_VNSTAT, INSTALL_UNATTENDED_UPGRADES, and INSTALL_AUDITD, and echoes the step result.
_wiz_step_features() {
    _wiz_clear_fields

    # Build governor options
    local gov_opts=""
    for g in "${WIZ_GOVERNORS[@]}"; do
        [[ -n "$gov_opts" ]] && gov_opts+="|"
        gov_opts+="$g"
    done

    _wiz_add_field "Default shell" "choose" "zsh|bash"
    _wiz_add_field "CPU governor" "choose" "$gov_opts"
    _wiz_add_field "Bandwidth monitor" "choose" "yes|no"
    _wiz_add_field "Auto updates" "choose" "yes|no"
    _wiz_add_field "Audit logging" "choose" "no|yes"

    # Pre-fill values
    WIZ_FIELD_VALUES[0]="${DEFAULT_SHELL:-zsh}"
    WIZ_FIELD_VALUES[1]="${CPU_GOVERNOR:-performance}"
    WIZ_FIELD_VALUES[2]="${INSTALL_VNSTAT:-yes}"
    WIZ_FIELD_VALUES[3]="${INSTALL_UNATTENDED_UPGRADES:-yes}"
    WIZ_FIELD_VALUES[4]="${INSTALL_AUDITD:-no}"

    local result
    result=$(wiz_step_interactive 5 "Features")

    if [[ "$result" == "next" ]]; then
        DEFAULT_SHELL="${WIZ_FIELD_VALUES[0]}"
        CPU_GOVERNOR="${WIZ_FIELD_VALUES[1]}"
        INSTALL_VNSTAT="${WIZ_FIELD_VALUES[2]}"
        INSTALL_UNATTENDED_UPGRADES="${WIZ_FIELD_VALUES[3]}"
        INSTALL_AUDITD="${WIZ_FIELD_VALUES[4]}"
    fi

    echo "$result"
}

# =============================================================================
# Step 6: Tailscale Configuration
# _wiz_step_tailscale configures Tailscale installation and related SSH/web UI options via an interactive wizard step.
# It pre-fills fields from environment variables, persists INSTALL_TAILSCALE, TAILSCALE_AUTH_KEY, TAILSCALE_SSH, TAILSCALE_WEBUI, TAILSCALE_DISABLE_SSH and STEALTH_MODE based on the user's choices, and echoes the interaction result.
_wiz_step_tailscale() {
    _wiz_clear_fields

    _wiz_add_field "Install Tailscale" "choose" "yes|no"
    _wiz_add_field "Auth key" "input" ""
    _wiz_add_field "Tailscale SSH" "choose" "yes|no"
    _wiz_add_field "Disable OpenSSH" "choose" "no|yes"

    # Pre-fill values
    WIZ_FIELD_VALUES[0]="${INSTALL_TAILSCALE:-no}"
    [[ -n "$TAILSCALE_AUTH_KEY" ]] && WIZ_FIELD_VALUES[1]="$TAILSCALE_AUTH_KEY"
    WIZ_FIELD_VALUES[2]="${TAILSCALE_SSH:-yes}"
    WIZ_FIELD_VALUES[3]="${TAILSCALE_DISABLE_SSH:-no}"

    local result
    result=$(wiz_step_interactive 6 "Tailscale VPN")

    if [[ "$result" == "next" ]]; then
        INSTALL_TAILSCALE="${WIZ_FIELD_VALUES[0]}"

        if [[ "$INSTALL_TAILSCALE" == "yes" ]]; then
            TAILSCALE_AUTH_KEY="${WIZ_FIELD_VALUES[1]}"
            TAILSCALE_SSH="${WIZ_FIELD_VALUES[2]}"
            TAILSCALE_WEBUI="yes"
            TAILSCALE_DISABLE_SSH="${WIZ_FIELD_VALUES[3]}"

            # Enable stealth mode if OpenSSH disabled
            if [[ "$TAILSCALE_DISABLE_SSH" == "yes" ]]; then
                STEALTH_MODE="yes"
            else
                STEALTH_MODE="no"
            fi
        else
            TAILSCALE_AUTH_KEY=""
            TAILSCALE_SSH="no"
            TAILSCALE_WEBUI="no"
            TAILSCALE_DISABLE_SSH="no"
            STEALTH_MODE="no"
        fi
    fi

    echo "$result"
}