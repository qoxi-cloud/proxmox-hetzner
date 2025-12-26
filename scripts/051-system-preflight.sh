# shellcheck shell=bash
# System preflight checks (root, internet, disk, RAM, CPU, KVM)

# Check root access. Sets PREFLIGHT_ROOT*.
_check_root_access() {
  if [[ $EUID -ne 0 ]]; then
    PREFLIGHT_ROOT="✗ Not root"
    PREFLIGHT_ROOT_STATUS="error"
    return 1
  else
    PREFLIGHT_ROOT="Running as root"
    PREFLIGHT_ROOT_STATUS="ok"
    return 0
  fi
}

# Check internet connectivity. Sets PREFLIGHT_NET*.
_check_internet() {
  if ping -c 1 -W 3 "$DNS_PRIMARY" >/dev/null 2>&1; then
    PREFLIGHT_NET="Available"
    PREFLIGHT_NET_STATUS="ok"
    return 0
  else
    PREFLIGHT_NET="No connection"
    PREFLIGHT_NET_STATUS="error"
    return 1
  fi
}

# Check disk space. Sets PREFLIGHT_DISK*.
_check_disk_space() {
  if validate_disk_space "/root" "$MIN_DISK_SPACE_MB"; then
    PREFLIGHT_DISK="${DISK_SPACE_MB} MB"
    PREFLIGHT_DISK_STATUS="ok"
    return 0
  else
    PREFLIGHT_DISK="${DISK_SPACE_MB:-0} MB (need ${MIN_DISK_SPACE_MB}MB+)"
    PREFLIGHT_DISK_STATUS="error"
    return 1
  fi
}

# Check RAM. Sets PREFLIGHT_RAM*.
_check_ram() {
  local total_ram_mb
  total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
  if [[ $total_ram_mb -ge $MIN_RAM_MB ]]; then
    PREFLIGHT_RAM="${total_ram_mb} MB"
    PREFLIGHT_RAM_STATUS="ok"
    return 0
  else
    PREFLIGHT_RAM="${total_ram_mb} MB (need ${MIN_RAM_MB}MB+)"
    PREFLIGHT_RAM_STATUS="error"
    return 1
  fi
}

# Check CPU cores. Sets PREFLIGHT_CPU*.
_check_cpu() {
  local cpu_cores
  cpu_cores=$(nproc)
  if [[ $cpu_cores -ge 2 ]]; then
    PREFLIGHT_CPU="${cpu_cores} cores"
    PREFLIGHT_CPU_STATUS="ok"
  else
    PREFLIGHT_CPU="${cpu_cores} core(s)"
    PREFLIGHT_CPU_STATUS="warn"
  fi
}

# Check KVM, load modules if needed. Sets PREFLIGHT_KVM*.
_check_kvm() {
  if [[ ! -e /dev/kvm ]]; then
    modprobe kvm 2>/dev/null || true

    if grep -q "Intel" /proc/cpuinfo 2>/dev/null; then
      modprobe kvm_intel 2>/dev/null || true
    elif grep -q "AMD" /proc/cpuinfo 2>/dev/null; then
      modprobe kvm_amd 2>/dev/null || true
    else
      modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || true
    fi
    sleep 0.5
  fi

  if [[ -e /dev/kvm ]]; then
    PREFLIGHT_KVM="Available"
    PREFLIGHT_KVM_STATUS="ok"
    return 0
  else
    PREFLIGHT_KVM="Not available"
    PREFLIGHT_KVM_STATUS="error"
    return 1
  fi
}

# Run all preflight checks. Sets PREFLIGHT_* variables.
_run_preflight_checks() {
  local errors=0

  _check_root_access || ((errors++))
  _check_internet || ((errors++))
  _check_disk_space || ((errors++))
  _check_ram || ((errors++))
  _check_cpu
  _check_kvm || ((errors++))

  PREFLIGHT_ERRORS=$errors
}

# Main collection function

# Collect system info and run preflight checks
collect_system_info() {
  # Install required tools
  _install_required_packages

  # Run preflight checks
  _run_preflight_checks

  # Detect network interface
  _detect_default_interface
  _detect_predictable_name
  _detect_available_interfaces

  # Collect IP information
  _detect_ipv4
  _detect_ipv6_and_mac

  # Load dynamic data for wizard
  _load_wizard_data
}
