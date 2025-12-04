# shellcheck shell=bash
# =============================================================================
# Command line argument parsing
# =============================================================================

# Displays command-line help message with usage, options, and examples.
# Prints to stdout and exits with code 0.
show_help() {
  cat <<EOF
Proxmox VE Automated Installer for Hetzner v${VERSION}

Usage: $0 [OPTIONS]

Options:
  -h, --help              Show this help message
  -c, --config FILE       Load configuration from file
  -s, --save-config FILE  Save configuration to file after input
  --validate              Validate configuration only, do not install
  --qemu-ram MB           Set QEMU RAM in MB (default: auto, 4096-8192)
  --qemu-cores N          Set QEMU CPU cores (default: auto, max 16)
  --iso-version FILE      Use specific Proxmox ISO (e.g., proxmox-ve_8.3-1.iso)
  -v, --version           Show version

Examples:
  $0                           # Run installation
  $0 -c proxmox.conf           # Load config from file
  $0 -s proxmox.conf           # Save config to file
  $0 -c proxmox.conf --validate  # Validate config without installing
  $0 --qemu-ram 16384 --qemu-cores 8  # Custom QEMU resources
  $0 --iso-version proxmox-ve_8.2-1.iso  # Use specific Proxmox version

EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -h | --help)
      show_help
      ;;
    -v | --version)
      echo "Proxmox Installer v${VERSION}"
      exit 0
      ;;
    -c | --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -s | --save-config)
      SAVE_CONFIG="$2"
      shift 2
      ;;
    --validate)
      VALIDATE_ONLY=true
      shift
      ;;
    --qemu-ram)
      if [[ -z $2 || $2 =~ ^- ]]; then
        echo -e "${CLR_RED}Error: --qemu-ram requires a value in MB${CLR_RESET}"
        exit 1
      fi
      if ! [[ $2 =~ ^[0-9]+$ ]] || [[ $2 -lt 2048 ]]; then
        echo -e "${CLR_RED}Error: --qemu-ram must be a number >= 2048 MB${CLR_RESET}"
        exit 1
      fi
      if [[ $2 -gt 131072 ]]; then
        echo -e "${CLR_RED}Error: --qemu-ram must be <= 131072 MB (128 GB)${CLR_RESET}"
        exit 1
      fi
      QEMU_RAM_OVERRIDE="$2"
      shift 2
      ;;
    --qemu-cores)
      if [[ -z $2 || $2 =~ ^- ]]; then
        echo -e "${CLR_RED}Error: --qemu-cores requires a value${CLR_RESET}"
        exit 1
      fi
      if ! [[ $2 =~ ^[0-9]+$ ]] || [[ $2 -lt 1 ]]; then
        echo -e "${CLR_RED}Error: --qemu-cores must be a positive number${CLR_RESET}"
        exit 1
      fi
      if [[ $2 -gt 256 ]]; then
        echo -e "${CLR_RED}Error: --qemu-cores must be <= 256${CLR_RESET}"
        exit 1
      fi
      QEMU_CORES_OVERRIDE="$2"
      shift 2
      ;;
    --iso-version)
      if [[ -z $2 || $2 =~ ^- ]]; then
        echo -e "${CLR_RED}Error: --iso-version requires a filename${CLR_RESET}"
        exit 1
      fi
      if ! [[ $2 =~ ^proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso$ ]]; then
        echo -e "${CLR_RED}Error: --iso-version must be in format: proxmox-ve_X.Y-Z.iso${CLR_RESET}"
        exit 1
      fi
      PROXMOX_ISO_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done
