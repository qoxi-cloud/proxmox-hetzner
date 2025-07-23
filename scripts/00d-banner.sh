# shellcheck shell=bash
# =============================================================================
# Cursor management - ensure cursor is always visible on exit
# =============================================================================
cleanup_cursor() {
    tput cnorm 2>/dev/null || true
}
trap cleanup_cursor EXIT INT TERM

clear

# =============================================================================
# ASCII Banner
# =============================================================================
echo -e "${CLR_CYAN}"
cat << 'BANNER'
         ____
        |  _ \ _ __ _____  ___ __ ___   _____  __
        | |_) | '__/ _ \ \/ / '_ ` _ \ / _ \ \/ /
        |  __/| | | (_) >  <| | | | | | (_) >  <
        |_|   |_|  \___/_/\_\_| |_| |_|\___/_/\_\

            Hetzner Automated Installer
BANNER
echo -e "${CLR_RESET}"
echo -e "${CLR_YELLOW}Version: ${VERSION}${CLR_RESET}"
echo -e "${CLR_YELLOW}Log file: ${LOG_FILE}${CLR_RESET}"
if [[ -n "$CONFIG_FILE" ]]; then
    echo -e "${CLR_YELLOW}Config: ${CONFIG_FILE}${CLR_RESET}"
fi
if [[ "$NON_INTERACTIVE" == true ]]; then
    echo -e "${CLR_YELLOW}Mode: Non-interactive${CLR_RESET}"
fi
if [[ "$TEST_MODE" == true ]]; then
    echo -e "${CLR_YELLOW}Mode: Test (TCG emulation, no KVM)${CLR_RESET}"
fi
echo ""
