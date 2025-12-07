# shellcheck shell=bash
# =============================================================================
# Banner display
# Note: cursor cleanup is handled by cleanup_and_error_handler in 00-init.sh
# =============================================================================

# Display main ASCII banner
# Usage: show_banner
show_banner() {
  echo -e "${CLR_GRAY}    _____                                              ${CLR_RESET}"
  echo -e "${CLR_GRAY}   |  __ \\                                             ${CLR_RESET}"
  echo -e "${CLR_GRAY}   | |__) | _ __   ___  ${CLR_ORANGE}__  __${CLR_GRAY}  _ __ ___    ___  ${CLR_ORANGE}__  __${CLR_RESET}"
  echo -e "${CLR_GRAY}   |  ___/ | '__| / _ \\ ${CLR_ORANGE}\\ \\/ /${CLR_GRAY} | '_ \` _ \\  / _ \\ ${CLR_ORANGE}\\ \\/ /${CLR_RESET}"
  echo -e "${CLR_GRAY}   | |     | |   | (_) |${CLR_ORANGE} >  <${CLR_GRAY}  | | | | | || (_) |${CLR_ORANGE} >  <${CLR_RESET}"
  echo -e "${CLR_GRAY}   |_|     |_|    \\___/ ${CLR_ORANGE}/_/\\_\\${CLR_GRAY} |_| |_| |_| \\___/ ${CLR_ORANGE}/_/\\_\\${CLR_RESET}"
  echo -e ""
  echo -e "${CLR_HETZNER}               Hetzner ${CLR_GRAY}Automated Installer${CLR_RESET}"
  echo ""
}

# =============================================================================
# Show banner on startup
# =============================================================================
clear
show_banner
