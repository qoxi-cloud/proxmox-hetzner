# shellcheck shell=bash
# =============================================================================
# System checks and hardware detection
# =============================================================================

# Collect system info with progress indicator
collect_system_info() {
    local errors=0
    local checks=7
    local current=0
    local i=0

    # Progress update helper
    update_progress() {
        current=$((current + 1))
        local pct=$((current * 100 / checks))
        local filled=$((pct / 5))
        local empty=$((20 - filled))
        printf "\r${CLR_YELLOW}${SPINNER_CHARS:i++%${#SPINNER_CHARS}:1} Checking system... [${CLR_GREEN}"
        printf '█%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null || true
        printf "${CLR_RESET}${CLR_BLUE}"
        printf '░%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null || true
        printf "${CLR_RESET}${CLR_YELLOW}] %3d%%${CLR_RESET}" "$pct"
    }

    # Install display utilities (boxes for tables, column for alignment)
    update_progress
    local need_install=false
    command -v boxes &> /dev/null || need_install=true
    command -v column &> /dev/null || need_install=true
    if $need_install; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -qq -y boxes bsdmainutils > /dev/null 2>&1
    fi

    # Check if running as root
    update_progress
    if [[ $EUID -ne 0 ]]; then
        PREFLIGHT_ROOT="✗ Not root"
        PREFLIGHT_ROOT_STATUS="error"
        errors=$((errors + 1))
    else
        PREFLIGHT_ROOT="Running as root"
        PREFLIGHT_ROOT_STATUS="ok"
    fi
    sleep 0.1

    # Check internet connectivity
    update_progress
    if ping -c 1 -W 3 1.1.1.1 > /dev/null 2>&1; then
        PREFLIGHT_NET="Available"
        PREFLIGHT_NET_STATUS="ok"
    else
        PREFLIGHT_NET="No connection"
        PREFLIGHT_NET_STATUS="error"
        errors=$((errors + 1))
    fi

    # Check available disk space (need at least 3GB in /root for ISO)
    update_progress
    local free_space_mb min_space_mb
    free_space_mb=$(df -m /root | awk 'NR==2 {print $4}')
    min_space_mb=3000
    if [[ $free_space_mb -ge $min_space_mb ]]; then
        PREFLIGHT_DISK="${free_space_mb} MB"
        PREFLIGHT_DISK_STATUS="ok"
    else
        PREFLIGHT_DISK="${free_space_mb} MB (need ${min_space_mb}MB+)"
        PREFLIGHT_DISK_STATUS="error"
        errors=$((errors + 1))
    fi
    sleep 0.1

    # Check RAM (need at least 4GB)
    update_progress
    local total_ram_mb min_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    min_ram_mb=4000
    if [[ $total_ram_mb -ge $min_ram_mb ]]; then
        PREFLIGHT_RAM="${total_ram_mb} MB"
        PREFLIGHT_RAM_STATUS="ok"
    else
        PREFLIGHT_RAM="${total_ram_mb} MB (need ${min_ram_mb}MB+)"
        PREFLIGHT_RAM_STATUS="error"
        errors=$((errors + 1))
    fi
    sleep 0.1

    # Check CPU cores
    update_progress
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -ge 2 ]]; then
        PREFLIGHT_CPU="${cpu_cores} cores"
        PREFLIGHT_CPU_STATUS="ok"
    else
        PREFLIGHT_CPU="${cpu_cores} core(s)"
        PREFLIGHT_CPU_STATUS="warn"
    fi
    sleep 0.1

    # Check if KVM is available
    update_progress
    if [[ -e /dev/kvm ]]; then
        PREFLIGHT_KVM="Available"
        PREFLIGHT_KVM_STATUS="ok"
    else
        PREFLIGHT_KVM="Not available"
        PREFLIGHT_KVM_STATUS="error"
        errors=$((errors + 1))
    fi
    sleep 0.1

    # Clear progress line
    printf "\r\033[K"

    PREFLIGHT_ERRORS=$errors
}

# Detect drives (NVMe preferred, falls back to any disk)
detect_drives() {
    # Find all NVMe drives (excluding partitions)
    mapfile -t DRIVES < <(lsblk -d -n -o NAME,TYPE | grep nvme | grep disk | awk '{print "/dev/"$1}' | sort)
    DRIVE_COUNT=${#DRIVES[@]}

    # Fall back to any available disk if no NVMe found (for budget servers)
    if [[ $DRIVE_COUNT -eq 0 ]]; then
        # Find any disk (sda, vda, etc.) excluding loop devices
        mapfile -t DRIVES < <(lsblk -d -n -o NAME,TYPE | grep disk | grep -v loop | awk '{print "/dev/"$1}' | sort)
        DRIVE_COUNT=${#DRIVES[@]}
    fi

    # Collect drive info
    DRIVE_NAMES=()
    DRIVE_SIZES=()
    DRIVE_MODELS=()

    for drive in "${DRIVES[@]}"; do
        local name size model
        name=$(basename "$drive")
        size=$(lsblk -d -n -o SIZE "$drive" | xargs)
        model=$(lsblk -d -n -o MODEL "$drive" 2>/dev/null | xargs || echo "Disk")
        DRIVE_NAMES+=("$name")
        DRIVE_SIZES+=("$size")
        DRIVE_MODELS+=("$model")
    done

    # Set default RAID mode if not already set
    if [[ -z "$ZFS_RAID" ]]; then
        if [[ $DRIVE_COUNT -lt 2 ]]; then
            ZFS_RAID="single"
        else
            ZFS_RAID="raid1"
        fi
    fi

}

# Display system status
show_system_status() {
    detect_drives

    local no_drives=0
    if [[ $DRIVE_COUNT -eq 0 ]]; then
        no_drives=1
    fi

    # Build system info rows
    local sys_rows=""

    # Helper to add row
    add_row() {
        local status="$1"
        local label="$2"
        local value="$3"
        case "$status" in
            ok)    sys_rows+="[OK]|${label}|${value}"$'\n' ;;
            warn)  sys_rows+="[WARN]|${label}|${value}"$'\n' ;;
            error) sys_rows+="[ERROR]|${label}|${value}"$'\n' ;;
        esac
    }

    add_row "$PREFLIGHT_ROOT_STATUS" "Root Access" "$PREFLIGHT_ROOT"
    add_row "$PREFLIGHT_NET_STATUS" "Internet" "$PREFLIGHT_NET"
    add_row "$PREFLIGHT_DISK_STATUS" "Temp Space" "$PREFLIGHT_DISK"
    add_row "$PREFLIGHT_RAM_STATUS" "RAM" "$PREFLIGHT_RAM"
    add_row "$PREFLIGHT_CPU_STATUS" "CPU" "$PREFLIGHT_CPU"
    add_row "$PREFLIGHT_KVM_STATUS" "KVM" "$PREFLIGHT_KVM"

    # Remove trailing newline
    sys_rows="${sys_rows%$'\n'}"

    # Build storage rows
    local storage_rows=""
    if [[ $no_drives -eq 1 ]]; then
        storage_rows="[ERROR]|No drives detected!|"
    else
        for i in "${!DRIVE_NAMES[@]}"; do
            storage_rows+="[OK]|${DRIVE_NAMES[$i]}|${DRIVE_SIZES[$i]}  ${DRIVE_MODELS[$i]:0:25}"
            if [[ $i -lt $((${#DRIVE_NAMES[@]} - 1)) ]]; then
                storage_rows+=$'\n'
            fi
        done
    fi

    # Display with boxes and colorize
    # Inner width = MENU_BOX_WIDTH - 4 (borders) - 2 (padding) = 54
    local inner_width=$((MENU_BOX_WIDTH - 6))
    {
        echo "SYSTEM INFORMATION"
        {
            echo "$sys_rows"
            echo "|--- Storage ---|"
            echo "$storage_rows"
        } | column -t -s '|' | while IFS= read -r line; do
            printf "%-${inner_width}s\n" "$line"
        done
    } | boxes -d stone -p a1 -s $MENU_BOX_WIDTH | colorize_status
    echo ""

    # Check for errors
    if [[ $PREFLIGHT_ERRORS -gt 0 ]]; then
        print_error "Pre-flight checks failed with $PREFLIGHT_ERRORS error(s). Exiting."
        exit 1
    fi

    if [[ $no_drives -eq 1 ]]; then
        print_error "No drives detected! Exiting."
        exit 1
    fi

    print_success "All checks passed!"
    echo ""
}
