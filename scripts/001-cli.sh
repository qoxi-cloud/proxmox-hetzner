# shellcheck shell=bash
# =============================================================================
# Command line argument parsing
# =============================================================================

# Displays command-line help message with usage, options, and examples.
# Prints to stdout and returns 0.
show_help() {
  cat <<EOF
Qoxi Automated Installer v${VERSION}

Usage: $0 [OPTIONS]

Options:
  -h, --help              Show this help message
  --qemu-ram MB           Set QEMU RAM in MB (default: auto, 4096-8192)
  --qemu-cores N          Set QEMU CPU cores (default: auto, max 16)
  --iso-version FILE      Use specific Proxmox ISO (e.g., proxmox-ve_8.3-1.iso)
  -v, --version           Show version

Examples:
  $0                           # Interactive installation
  $0 --qemu-ram 16384 --qemu-cores 8  # Custom QEMU resources
  $0 --iso-version proxmox-ve_8.2-1.iso  # Use specific Proxmox version

EOF
}

# Parses command-line arguments and sets global variables.
# Uses return codes instead of exit for testability.
# Parameters: $@ - command line arguments
# Returns: 0 on success, 1 on error, 2 for help/version (early exit)
# Sets: QEMU_RAM_OVERRIDE, QEMU_CORES_OVERRIDE, PROXMOX_ISO_VERSION
parse_cli_args() {
  # Reset variables for clean parsing
  QEMU_RAM_OVERRIDE=""
  QEMU_CORES_OVERRIDE=""
  PROXMOX_ISO_VERSION=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help)
        show_help
        return 2
        ;;
      -v | --version)
        printf '%s\n' "Proxmox Installer v${VERSION}"
        return 2
        ;;
      --qemu-ram)
        if [[ -z ${2:-} || ${2:-} =~ ^- ]]; then
          printf '%s\n' "${CLR_RED}Error: --qemu-ram requires a value in MB${CLR_RESET}"
          return 1
        fi
        if ! [[ $2 =~ ^[0-9]+$ ]] || [[ $2 -lt 2048 ]]; then
          printf '%s\n' "${CLR_RED}Error: --qemu-ram must be a number >= 2048 MB${CLR_RESET}"
          return 1
        fi
        if [[ $2 -gt 131072 ]]; then
          printf '%s\n' "${CLR_RED}Error: --qemu-ram must be <= 131072 MB (128 GB)${CLR_RESET}"
          return 1
        fi
        QEMU_RAM_OVERRIDE="$2"
        shift 2
        ;;
      --qemu-cores)
        if [[ -z ${2:-} || ${2:-} =~ ^- ]]; then
          printf '%s\n' "${CLR_RED}Error: --qemu-cores requires a value${CLR_RESET}"
          return 1
        fi
        if ! [[ $2 =~ ^[0-9]+$ ]] || [[ $2 -lt 1 ]]; then
          printf '%s\n' "${CLR_RED}Error: --qemu-cores must be a positive number${CLR_RESET}"
          return 1
        fi
        if [[ $2 -gt 256 ]]; then
          printf '%s\n' "${CLR_RED}Error: --qemu-cores must be <= 256${CLR_RESET}"
          return 1
        fi
        QEMU_CORES_OVERRIDE="$2"
        shift 2
        ;;
      --iso-version)
        if [[ -z ${2:-} || ${2:-} =~ ^- ]]; then
          printf '%s\n' "${CLR_RED}Error: --iso-version requires a filename${CLR_RESET}"
          return 1
        fi
        if ! [[ $2 =~ ^proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso$ ]]; then
          printf '%s\n' "${CLR_RED}Error: --iso-version must be in format: proxmox-ve_X.Y-Z.iso${CLR_RESET}"
          return 1
        fi
        PROXMOX_ISO_VERSION="$2"
        shift 2
        ;;
      *)
        printf '%s\n' "Unknown option: $1"
        printf '%s\n' "Use --help for usage information"
        return 1
        ;;
    esac
  done
  return 0
}

# Parse CLI args at source time (main script execution)
# Return code 2 means help/version was shown - exit cleanly
# shellcheck disable=SC2317
if [[ ${BASH_SOURCE[0]} == "$0" ]] || [[ ${_CLI_PARSE_ON_SOURCE:-true} == "true" ]]; then
  parse_cli_args "$@"
  _cli_ret=$?
  if [[ $_cli_ret -eq 2 ]]; then
    exit 0
  elif [[ $_cli_ret -ne 0 ]]; then
    exit 1
  fi
fi
