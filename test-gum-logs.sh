#!/usr/bin/env bash
# =============================================================================
# Test script for gum-based installation logging
# Demonstrates different approaches to show installation progress
# =============================================================================

set -euo pipefail

# Colors
CLR_CYAN=$'\033[38;2;0;177;255m'
CLR_GREEN=$'\033[38;2;0;255;0m'
CLR_YELLOW=$'\033[1;33m'
CLR_RED=$'\033[1;31m'
CLR_GRAY=$'\033[38;5;240m'
CLR_RESET=$'\033[m'

HEX_CYAN="#00b1ff"
HEX_GREEN="#00ff00"
HEX_YELLOW="#ffff00"
# shellcheck disable=SC2034
HEX_RED="#ff0000"
# shellcheck disable=SC2034
HEX_GRAY="#585858"

# =============================================================================
# Demo 1: Simple step-by-step logging with gum style
# =============================================================================
demo_simple_logging() {
	echo ""
	gum style \
		--border double \
		--border-foreground "$HEX_CYAN" \
		--padding "1 2" \
		--width 60 \
		"Demo 1: Simple Step-by-Step Logging"
	echo ""

	# Simulate installation steps
	steps=(
		"Downloading Proxmox ISO"
		"Verifying checksum"
		"Creating QEMU VM"
		"Installing system"
		"Configuring network"
		"Installing packages"
		"Setting up firewall"
	)

	for step in "${steps[@]}"; do
		# Show step in progress
		echo -n "${CLR_CYAN}▶${CLR_RESET} $step... "
		sleep 0.5

		# Simulate work
		sleep 1

		# Show completion
		echo -e "\r${CLR_GREEN}✓${CLR_RESET} $step"
	done

	echo ""
	gum style \
		--foreground "$HEX_GREEN" \
		--bold \
		"✓ All steps completed!"
	echo ""
}

# =============================================================================
# Demo 2: Using gum spin for long-running operations
# =============================================================================
demo_gum_spin() {
	echo ""
	gum style \
		--border double \
		--border-foreground "$HEX_CYAN" \
		--padding "1 2" \
		--width 60 \
		"Demo 2: Gum Spin for Long Operations"
	echo ""

	# Simulate downloading ISO
	# shellcheck disable=SC2016
	gum spin \
		--spinner dot \
		--title "Downloading Proxmox ISO..." \
		--show-output \
		-- bash -c 'for i in {1..50}; do echo "Progress: $i%"; sleep 0.05; done'

	echo -e "${CLR_GREEN}✓${CLR_RESET} Download completed"
	echo ""

	# Simulate package installation
	# shellcheck disable=SC2016
	gum spin \
		--spinner line \
		--title "Installing packages..." \
		--show-output \
		-- bash -c 'for pkg in btop iotop ncdu tmux jq bat; do echo "Installing $pkg..."; sleep 0.3; done'

	echo -e "${CLR_GREEN}✓${CLR_RESET} Packages installed"
	echo ""
}

# =============================================================================
# Demo 3: Progress tracking with percentage
# =============================================================================
demo_progress_tracking() {
	echo ""
	gum style \
		--border double \
		--border-foreground "$HEX_CYAN" \
		--padding "1 2" \
		--width 60 \
		"Demo 3: Progress Tracking with Percentage"
	echo ""

	steps=(
		"Initializing system"
		"Configuring repositories"
		"Updating package lists"
		"Installing system utilities"
		"Configuring services"
		"Setting up security"
		"Finalizing configuration"
	)

	total=${#steps[@]}

	for i in "${!steps[@]}"; do
		current=$((i + 1))
		percent=$((current * 100 / total))

		# Show progress bar using gum style
		bar_width=40
		filled=$((bar_width * current / total))
		empty=$((bar_width - filled))

		bar=$(printf "%${filled}s" | tr ' ' '█')
		bar+=$(printf "%${empty}s" | tr ' ' '░')

		# Clear line and show progress
		echo -ne "\r\033[K"
		echo -ne "${CLR_CYAN}[$bar]${CLR_RESET} "
		echo -ne "${CLR_YELLOW}${percent}%${CLR_RESET} "
		echo -ne "${steps[$i]}..."

		# Simulate work
		sleep 0.8

		# Show completion for current step
		echo -ne "\r\033[K"
		echo -ne "${CLR_CYAN}[$bar]${CLR_RESET} "
		echo -ne "${CLR_GREEN}${percent}%${CLR_RESET} "
		echo -e "${CLR_GREEN}✓${CLR_RESET} ${steps[$i]}"
	done

	echo ""
	gum style \
		--foreground "$HEX_GREEN" \
		--bold \
		"✓ Installation completed successfully!"
	echo ""
}

# =============================================================================
# Demo 4: Live log streaming with gum pager
# =============================================================================
demo_live_logs() {
	echo ""
	gum style \
		--border double \
		--border-foreground "$HEX_CYAN" \
		--padding "1 2" \
		--width 60 \
		"Demo 4: Live Log Streaming"
	echo ""

	# Create temporary log file
	logfile=$(mktemp)

	# Simulate installation process writing to log
	{
		echo "[$(date '+%H:%M:%S')] Starting installation process"
		sleep 0.3
		echo "[$(date '+%H:%M:%S')] Checking system requirements"
		echo "  - RAM: 32GB available ✓"
		echo "  - Disk: 2TB available ✓"
		echo "  - CPU: 8 cores available ✓"
		sleep 0.5
		echo "[$(date '+%H:%M:%S')] Downloading Proxmox ISO"
		for i in {10..100..10}; do
			echo "  Progress: $i%"
			sleep 0.2
		done
		echo "[$(date '+%H:%M:%S')] Download completed"
		sleep 0.3
		echo "[$(date '+%H:%M:%S')] Verifying checksum"
		echo "  SHA256: OK ✓"
		sleep 0.3
		echo "[$(date '+%H:%M:%S')] Creating QEMU virtual machine"
		sleep 0.5
		echo "[$(date '+%H:%M:%S')] Starting installation"
		sleep 0.8
		echo "[$(date '+%H:%M:%S')] Installation completed successfully"
	} >"$logfile" &

	local pid=$!

	# Show log with tail -f style
	echo -e "${CLR_CYAN}Installation Log:${CLR_RESET}"
	echo "─────────────────────────────────────────────────────────"

	tail -f "$logfile" &
	local tail_pid=$!

	# Wait for installation to complete
	wait $pid 2>/dev/null || true

	# Give tail time to show final lines
	sleep 1

	# Stop tail
	kill $tail_pid 2>/dev/null || true
	wait $tail_pid 2>/dev/null || true

	echo "─────────────────────────────────────────────────────────"
	echo ""

	# Cleanup
	rm -f "$logfile"

	gum style \
		--foreground "$HEX_GREEN" \
		--bold \
		"✓ Log streaming completed"
	echo ""
}

# =============================================================================
# Demo 5: Grouped step logging with collapsible sections
# =============================================================================
demo_grouped_steps() {
	echo ""
	gum style \
		--border double \
		--border-foreground "$HEX_CYAN" \
		--padding "1 2" \
		--width 60 \
		"Demo 5: Grouped Step Logging"
	echo ""

	# Group 1: System Preparation
	gum style --foreground "$HEX_CYAN" --bold "▼ System Preparation"
	echo "  ${CLR_GRAY}├─${CLR_RESET} Checking requirements... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.3
	echo "  ${CLR_GRAY}├─${CLR_RESET} Detecting hardware... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.3
	echo "  ${CLR_GRAY}└─${CLR_RESET} Configuring QEMU... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.3
	echo ""

	# Group 2: ISO Management
	gum style --foreground "$HEX_CYAN" --bold "▼ ISO Management"
	echo "  ${CLR_GRAY}├─${CLR_RESET} Downloading ISO... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.5
	echo "  ${CLR_GRAY}├─${CLR_RESET} Verifying checksum... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.3
	echo "  ${CLR_GRAY}└─${CLR_RESET} Preparing autoinstall... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.3
	echo ""

	# Group 3: Installation
	gum style --foreground "$HEX_CYAN" --bold "▼ Installation"
	echo "  ${CLR_GRAY}├─${CLR_RESET} Booting installer... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.4
	echo "  ${CLR_GRAY}├─${CLR_RESET} Installing base system... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.8
	echo "  ${CLR_GRAY}├─${CLR_RESET} Configuring bootloader... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.4
	echo "  ${CLR_GRAY}└─${CLR_RESET} Finishing installation... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.3
	echo ""

	# Group 4: Configuration
	gum style --foreground "$HEX_CYAN" --bold "▼ Configuration"
	echo "  ${CLR_GRAY}├─${CLR_RESET} Configuring network... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.4
	echo "  ${CLR_GRAY}├─${CLR_RESET} Installing packages... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.6
	echo "  ${CLR_GRAY}├─${CLR_RESET} Setting up firewall... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.4
	echo "  ${CLR_GRAY}└─${CLR_RESET} Enabling services... ${CLR_GREEN}✓${CLR_RESET}"
	sleep 0.3
	echo ""

	gum style \
		--foreground "$HEX_GREEN" \
		--bold \
		"✓ All groups completed successfully!"
	echo ""
}

# =============================================================================
# Demo 6: Error handling and warnings
# =============================================================================
demo_error_handling() {
	echo ""
	gum style \
		--border double \
		--border-foreground "$HEX_CYAN" \
		--padding "1 2" \
		--width 60 \
		"Demo 6: Error Handling and Warnings"
	echo ""

	# Success
	echo -e "${CLR_GREEN}✓${CLR_RESET} System check passed"
	sleep 0.3

	# Warning
	echo -e "${CLR_YELLOW}⚠${CLR_RESET} Low memory detected (8GB available, 16GB recommended)"
	sleep 0.3

	# Info
	echo -e "${CLR_CYAN}ℹ${CLR_RESET} Using default network configuration"
	sleep 0.3

	# Success
	echo -e "${CLR_GREEN}✓${CLR_RESET} Network configured"
	sleep 0.3

	# Warning with details
	echo -e "${CLR_YELLOW}⚠${CLR_RESET} Some packages failed to install:"
	echo "    ${CLR_GRAY}-${CLR_RESET} package-foo (not available in repository)"
	echo "    ${CLR_GRAY}-${CLR_RESET} package-bar (dependency conflict)"
	sleep 0.5

	# Error simulation
	echo -e "${CLR_RED}✗${CLR_RESET} Failed to connect to remote server"
	sleep 0.3
	echo -e "${CLR_YELLOW}↻${CLR_RESET} Retrying connection (attempt 1/3)..."
	sleep 0.8
	echo -e "${CLR_YELLOW}↻${CLR_RESET} Retrying connection (attempt 2/3)..."
	sleep 0.8
	echo -e "${CLR_GREEN}✓${CLR_RESET} Connection successful"
	sleep 0.3

	echo ""
	gum style \
		--foreground "$HEX_YELLOW" \
		--bold \
		"⚠ Installation completed with warnings"
	echo ""
}

# =============================================================================
# Main menu
# =============================================================================
main() {
	clear

	gum style \
		--border double \
		--border-foreground "$HEX_CYAN" \
		--padding "1 2" \
		--margin "1" \
		--width 60 \
		--align center \
		"Gum Installation Logging Demo" \
		"" \
		"Interactive demonstration of different logging approaches"

	while true; do
		echo ""
		choice=$(gum choose \
			"1. Simple Step-by-Step Logging" \
			"2. Gum Spin for Long Operations" \
			"3. Progress Tracking with Percentage" \
			"4. Live Log Streaming" \
			"5. Grouped Step Logging" \
			"6. Error Handling and Warnings" \
			"7. Run All Demos" \
			"8. Exit" \
			--header="Select a demo:" \
			--header.foreground "$HEX_CYAN" \
			--cursor.foreground "$HEX_CYAN" \
			--selected.foreground "$HEX_GREEN")

		case "$choice" in
		"1. Simple Step-by-Step Logging")
			clear
			demo_simple_logging
			read -n 1 -s -r -p "Press any key to continue..."
			clear
			;;
		"2. Gum Spin for Long Operations")
			clear
			demo_gum_spin
			read -n 1 -s -r -p "Press any key to continue..."
			clear
			;;
		"3. Progress Tracking with Percentage")
			clear
			demo_progress_tracking
			read -n 1 -s -r -p "Press any key to continue..."
			clear
			;;
		"4. Live Log Streaming")
			clear
			demo_live_logs
			read -n 1 -s -r -p "Press any key to continue..."
			clear
			;;
		"5. Grouped Step Logging")
			clear
			demo_grouped_steps
			read -n 1 -s -r -p "Press any key to continue..."
			clear
			;;
		"6. Error Handling and Warnings")
			clear
			demo_error_handling
			read -n 1 -s -r -p "Press any key to continue..."
			clear
			;;
		"7. Run All Demos")
			clear
			demo_simple_logging
			sleep 2
			demo_gum_spin
			sleep 2
			demo_progress_tracking
			sleep 2
			demo_live_logs
			sleep 2
			demo_grouped_steps
			sleep 2
			demo_error_handling
			read -n 1 -s -r -p "Press any key to continue..."
			clear
			;;
		"8. Exit")
			clear
			gum style \
				--foreground "$HEX_GREEN" \
				--bold \
				"Thanks for watching! 👋"
			echo ""
			exit 0
			;;
		esac
	done
}

# Check if gum is installed
if ! command -v gum &>/dev/null; then
	echo -e "${CLR_RED}Error: gum is not installed${CLR_RESET}"
	echo ""
	echo "Install gum:"
	echo "  macOS:   brew install gum"
	echo "  Linux:   See https://github.com/charmbracelet/gum#installation"
	exit 1
fi

main
