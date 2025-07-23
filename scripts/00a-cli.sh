# shellcheck shell=bash
# =============================================================================
# Command line argument parsing
# =============================================================================
show_help() {
    cat << EOF
Proxmox VE Automated Installer for Hetzner v${VERSION}

Usage: $0 [OPTIONS]

Options:
  -h, --help              Show this help message
  -c, --config FILE       Load configuration from file
  -s, --save-config FILE  Save configuration to file after input
  -n, --non-interactive   Run without prompts (requires --config)
  -t, --test              Test mode (use TCG emulation, no KVM required)
  -v, --version           Show version

Examples:
  $0                           # Interactive installation
  $0 -s proxmox.conf           # Interactive, save config for later
  $0 -c proxmox.conf           # Load config, prompt for missing values
  $0 -c proxmox.conf -n        # Fully automated installation

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--version)
            echo "Proxmox Installer v${VERSION}"
            exit 0
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -s|--save-config)
            SAVE_CONFIG="$2"
            shift 2
            ;;
        -n|--non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        -t|--test)
            TEST_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate non-interactive mode requires config
if [[ "$NON_INTERACTIVE" == true && -z "$CONFIG_FILE" ]]; then
    echo -e "${CLR_RED}Error: --non-interactive requires --config FILE${CLR_RESET}"
    exit 1
fi
