#!/usr/bin/env bash
# Qoxi - Proxmox VE Automated Installer for Dedicated Servers
# Note: NOT using set -e because it interferes with trap EXIT handler
# All error handling is done explicitly with exit 1
cd /root || exit 1

# Ensure UTF-8 locale for proper Unicode display
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Colors for terminal output
readonly CLR_RED=$'\033[1;31m'
readonly CLR_CYAN=$'\033[38;2;0;177;255m'
readonly CLR_YELLOW=$'\033[1;33m'
readonly CLR_ORANGE=$'\033[38;5;208m'
readonly CLR_GRAY=$'\033[38;5;240m'
readonly CLR_GOLD=$'\033[38;5;179m'
readonly CLR_RESET=$'\033[m'

# Hex colors for gum (terminal UI toolkit)
readonly HEX_RED="#ff0000"
readonly HEX_CYAN="#00b1ff"
readonly HEX_YELLOW="#ffff00"
readonly HEX_ORANGE="#ff8700"
readonly HEX_GRAY="#585858"
readonly HEX_WHITE="#ffffff"
readonly HEX_NONE="7"

# Version (MAJOR only - MINOR.PATCH added by CI from git tags/commits)
readonly VERSION="2"

# Terminal width for centering (wizard UI, headers, etc.)
readonly TERM_WIDTH=80

# Banner dimensions
readonly BANNER_WIDTH=51
