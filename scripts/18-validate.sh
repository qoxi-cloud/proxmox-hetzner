# shellcheck shell=bash
# =============================================================================
# Post-installation validation
# =============================================================================

# Validation result counters (global for use in summary)
VALIDATION_PASSED=0
VALIDATION_FAILED=0
VALIDATION_WARNINGS=0

# Store validation results for summary (global array)
declare -a VALIDATION_RESULTS=()

# Internal: adds validation result to global arrays.
# Parameters:
#   $1 - Status (pass/fail/warn)
#   $2 - Check name
#   $3 - Details (optional)
_add_validation_result() {
    local status="$1"
    local check_name="$2"
    local details="${3:-}"

    case "$status" in
        pass)
            VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
            VALIDATION_RESULTS+=("[OK]|${check_name}|${details}")
            ;;
        fail)
            VALIDATION_FAILED=$((VALIDATION_FAILED + 1))
            VALIDATION_RESULTS+=("[ERROR]|${check_name}|${details}")
            ;;
        warn)
            VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
            VALIDATION_RESULTS+=("[WARN]|${check_name}|${details}")
            ;;
    esac
}

# Internal: validates SSH configuration (service, keys, auth settings).
_validate_ssh() {
    # Check SSH service is running
    local ssh_status
    ssh_status=$(remote_exec "systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null" 2>/dev/null)
    if [[ "$ssh_status" == "active" ]]; then
        _add_validation_result "pass" "SSH service" "running"
    else
        _add_validation_result "fail" "SSH service" "not running"
    fi

    # Check SSH key is deployed
    local key_check
    key_check=$(remote_exec "test -f /root/.ssh/authorized_keys && grep -c 'ssh-' /root/.ssh/authorized_keys 2>/dev/null || echo 0" 2>/dev/null)
    if [[ "$key_check" -gt 0 ]]; then
        _add_validation_result "pass" "SSH public key" "deployed"
    else
        _add_validation_result "fail" "SSH public key" "not found"
    fi

    # Check password authentication is disabled
    local pass_auth
    pass_auth=$(remote_exec "grep -E '^PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
    if [[ "$pass_auth" == "no" ]]; then
        _add_validation_result "pass" "Password auth" "DISABLED"
    else
        _add_validation_result "warn" "Password auth" "enabled"
    fi
}

# Internal: validates ZFS pool health and ARC configuration.
_validate_zfs() {
    # Check rpool health
    local pool_health
    pool_health=$(remote_exec "zpool status rpool 2>/dev/null | grep 'state:' | awk '{print \$2}'" 2>/dev/null)
    if [[ "$pool_health" == "ONLINE" ]]; then
        _add_validation_result "pass" "ZFS rpool" "ONLINE"
    elif [[ -n "$pool_health" ]]; then
        _add_validation_result "warn" "ZFS rpool" "$pool_health"
    else
        _add_validation_result "fail" "ZFS rpool" "not found"
    fi

    # Check ZFS ARC limits are configured
    local arc_max
    arc_max=$(remote_exec "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null" 2>/dev/null)
    if [[ -n "$arc_max" && "$arc_max" -gt 0 ]]; then
        local arc_max_gb
        arc_max_gb=$(echo "scale=1; $arc_max / 1073741824" | bc 2>/dev/null || echo "N/A")
        _add_validation_result "pass" "ZFS ARC limit" "${arc_max_gb}GB"
    else
        _add_validation_result "warn" "ZFS ARC limit" "not set"
    fi
}

# Internal: validates network connectivity (IPv4, DNS, IPv6).
_validate_network() {
    # Check IPv4 connectivity (ping gateway)
    local ipv4_ping
    ipv4_ping=$(remote_exec "ping -c 1 -W 2 ${MAIN_IPV4_GW} >/dev/null 2>&1 && echo ok || echo fail" 2>/dev/null)
    if [[ "$ipv4_ping" == "ok" ]]; then
        _add_validation_result "pass" "IPv4 gateway" "reachable"
    else
        _add_validation_result "fail" "IPv4 gateway" "unreachable"
    fi

    # Check DNS resolution
    local dns_check
    dns_check=$(remote_exec "host -W 2 google.com >/dev/null 2>&1 && echo ok || echo fail" 2>/dev/null)
    if [[ "$dns_check" == "ok" ]]; then
        _add_validation_result "pass" "DNS resolution" "working"
    else
        _add_validation_result "warn" "DNS resolution" "failed"
    fi

    # Check IPv6 if configured
    if [[ "${IPV6_MODE:-disabled}" != "disabled" && -n "${MAIN_IPV6:-}" ]]; then
        local ipv6_addr
        ipv6_addr=$(remote_exec "ip -6 addr show scope global 2>/dev/null | grep -c 'inet6'" 2>/dev/null)
        if [[ "$ipv6_addr" -gt 0 ]]; then
            _add_validation_result "pass" "IPv6 address" "configured"
        else
            _add_validation_result "warn" "IPv6 address" "not found"
        fi
    fi
}

# Internal: validates essential Proxmox services.
_validate_services() {
    # List of critical services to check
    local services=("pve-cluster" "pvedaemon" "pveproxy" "pvestatd")
    local all_running=true

    for svc in "${services[@]}"; do
        local svc_status
        svc_status=$(remote_exec "systemctl is-active $svc 2>/dev/null" 2>/dev/null)
        if [[ "$svc_status" != "active" ]]; then
            all_running=false
            _add_validation_result "fail" "$svc" "not running"
        fi
    done

    if [[ "$all_running" == "true" ]]; then
        _add_validation_result "pass" "Proxmox services" "all running"
    fi

    # Check chrony/NTP
    local ntp_status
    ntp_status=$(remote_exec "systemctl is-active chrony 2>/dev/null" 2>/dev/null)
    if [[ "$ntp_status" == "active" ]]; then
        _add_validation_result "pass" "NTP sync" "chrony running"
    else
        _add_validation_result "warn" "NTP sync" "not running"
    fi
}

# Internal: validates Proxmox Web UI and API.
_validate_proxmox() {
    # Check Proxmox web interface is responding
    local web_check
    web_check=$(remote_exec "curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8006/ 2>/dev/null" 2>/dev/null)
    if [[ "$web_check" == "200" || "$web_check" == "301" || "$web_check" == "302" ]]; then
        _add_validation_result "pass" "Web UI (8006)" "responding"
    else
        _add_validation_result "fail" "Web UI (8006)" "not responding"
    fi

    # Check pvesh is working
    local pvesh_check
    pvesh_check=$(remote_exec "pvesh get /version --output-format json 2>/dev/null | jq -r '.version' 2>/dev/null" 2>/dev/null)
    if [[ -n "$pvesh_check" && "$pvesh_check" != "null" ]]; then
        _add_validation_result "pass" "Proxmox API" "v${pvesh_check}"
    else
        _add_validation_result "warn" "Proxmox API" "check failed"
    fi
}

# Internal: validates SSL certificate presence and validity.
_validate_ssl() {
    # Check certificate exists and get expiry
    local cert_info
    cert_info=$(remote_exec "openssl x509 -enddate -noout -in /etc/pve/local/pve-ssl.pem 2>/dev/null | cut -d= -f2" 2>/dev/null)
    if [[ -n "$cert_info" ]]; then
        # Shorten the date format
        local short_date
        short_date=$(echo "$cert_info" | awk '{print $1, $2, $4}')
        _add_validation_result "pass" "SSL certificate" "valid until $short_date"
    else
        _add_validation_result "fail" "SSL certificate" "missing"
    fi
}

# Runs all post-installation validation checks.
# Side effects: Sets VALIDATION_PASSED/FAILED/WARNINGS and VALIDATION_RESULTS globals
validate_installation() {
    log "Starting post-installation validation..."

    # Reset counters
    VALIDATION_PASSED=0
    VALIDATION_FAILED=0
    VALIDATION_WARNINGS=0
    VALIDATION_RESULTS=()

    # Create temp file for results (to pass data from subshell)
    local results_file
    results_file=$(mktemp)
    trap 'rm -f "$results_file"' RETURN

    # Run validation in background, write results to temp file
    (
        _validate_ssh
        _validate_zfs
        _validate_network
        _validate_services
        _validate_proxmox
        _validate_ssl

        # Write results to temp file
        {
            echo "VALIDATION_PASSED=$VALIDATION_PASSED"
            echo "VALIDATION_FAILED=$VALIDATION_FAILED"
            echo "VALIDATION_WARNINGS=$VALIDATION_WARNINGS"
            for result in "${VALIDATION_RESULTS[@]}"; do
                echo "RESULT:$result"
            done
        } >> "$results_file"
    ) 2>/dev/null &
    show_progress $! "Validating installation" "Validation complete"

    # Read results from temp file
    if [[ -f "$results_file" ]]; then
        while IFS= read -r line; do
            case "$line" in
                VALIDATION_PASSED=*)
                    VALIDATION_PASSED="${line#VALIDATION_PASSED=}"
                    ;;
                VALIDATION_FAILED=*)
                    VALIDATION_FAILED="${line#VALIDATION_FAILED=}"
                    ;;
                VALIDATION_WARNINGS=*)
                    VALIDATION_WARNINGS="${line#VALIDATION_WARNINGS=}"
                    ;;
                RESULT:*)
                    VALIDATION_RESULTS+=("${line#RESULT:}")
                    ;;
            esac
        done < "$results_file"
    fi

    # Log results
    log "Validation complete: ${VALIDATION_PASSED} passed, ${VALIDATION_WARNINGS} warnings, ${VALIDATION_FAILED} failed"
}
