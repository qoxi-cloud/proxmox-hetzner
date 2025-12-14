#!/usr/bin/env bash
# =============================================================================
# Demo: Live installation logs with logo and auto-scroll
# =============================================================================

set -euo pipefail

# Colors
CLR_CYAN=$'\033[38;2;0;177;255m'
CLR_GRAY=$'\033[38;5;240m'
CLR_RESET=$'\033[m'

HEX_CYAN="#00b1ff"

# Get terminal dimensions
TERM_HEIGHT=$(tput lines)

# Logo height (number of lines)
LOGO_HEIGHT=8

# Calculate available space for logs
LOG_AREA_HEIGHT=$((TERM_HEIGHT - LOGO_HEIGHT - 2))

# Array to store log lines
declare -a LOG_LINES=()
LOG_COUNT=0

# Show logo at top (only once at start)
show_logo() {
	gum style \
		--border double \
		--border-foreground "$HEX_CYAN" \
		--padding "1 2" \
		--margin "0" \
		--width 70 \
		--align center \
		"Proxmox VE Automated Installer" \
		"" \
		"Live Installation Progress"
	echo ""
}

# Save cursor position after logo
save_cursor_position() {
	printf '\033[s'
}

# Restore cursor to saved position
restore_cursor_position() {
	printf '\033[u'
	printf '\033[J'
}

# Add log entry
add_log() {
	local message="$1"
	LOG_LINES+=("$message")
	((LOG_COUNT++))
	render_logs
}

# Render all logs (with auto-scroll, no flicker)
render_logs() {
	restore_cursor_position
	local start_line=0
	if ((LOG_COUNT > LOG_AREA_HEIGHT)); then
		start_line=$((LOG_COUNT - LOG_AREA_HEIGHT))
	fi
	for ((i = start_line; i < LOG_COUNT; i++)); do
		echo "${LOG_LINES[$i]}"
	done
}

# Start task (shows working ellipsis ...)
start_task() {
	local message="$1"
	add_log "$message..."
	TASK_INDEX=$((LOG_COUNT - 1))
}

# Complete task with checkmark
complete_task() {
	local task_index="$1"
	local message="$2"
	LOG_LINES[task_index]="$message ${CLR_CYAN}✓${CLR_RESET}"
	render_logs
}

# Simulate installation process
run_installation() {
	add_log "${CLR_CYAN}▼ System Preparation${CLR_RESET}"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Checking system requirements"
	local task_index=$TASK_INDEX
	sleep 0.5
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}RAM: 32GB available"
	sleep 0.2
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Disk: 2TB available"
	sleep 0.2
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}CPU: 8 cores available"
	sleep 0.2
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Checking requirements"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Detecting hardware"
	task_index=$TASK_INDEX
	sleep 0.6
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Network interface: eth0${CLR_RESET}"
	sleep 0.2
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Disk: /dev/sda (2TB NVMe)${CLR_RESET}"
	sleep 0.2
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Detecting hardware"
	sleep 0.3

	start_task "  ${CLR_GRAY}└─${CLR_RESET} Configuring QEMU VM"
	task_index=$TASK_INDEX
	sleep 0.5
	add_log "  ${CLR_GRAY} ${CLR_RESET}   ${CLR_GRAY}RAM: 8192 MB${CLR_RESET}"
	sleep 0.2
	add_log "  ${CLR_GRAY} ${CLR_RESET}   ${CLR_GRAY}CPU: 4 cores${CLR_RESET}"
	sleep 0.2
	complete_task "$task_index" "  ${CLR_GRAY}└─${CLR_RESET} Configuring QEMU"
	sleep 0.4
	add_log ""

	add_log "${CLR_CYAN}▼ ISO Management${CLR_RESET}"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Downloading Proxmox ISO"
	task_index=$TASK_INDEX
	for i in {10..100..10}; do
		sleep 0.2
		add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Progress: $i%${CLR_RESET}"
	done
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Downloading ISO"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Verifying checksum"
	task_index=$TASK_INDEX
	sleep 0.8
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}SHA256: OK${CLR_RESET}"
	sleep 0.2
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Verifying checksum"
	sleep 0.3

	start_task "  ${CLR_GRAY}└─${CLR_RESET} Preparing autoinstall configuration"
	task_index=$TASK_INDEX
	sleep 0.6
	add_log "  ${CLR_GRAY} ${CLR_RESET}   ${CLR_GRAY}Hostname: pve.example.com${CLR_RESET}"
	sleep 0.2
	add_log "  ${CLR_GRAY} ${CLR_RESET}   ${CLR_GRAY}Network: 10.0.0.0/24${CLR_RESET}"
	sleep 0.2
	add_log "  ${CLR_GRAY} ${CLR_RESET}   ${CLR_GRAY}ZFS RAID: raid1${CLR_RESET}"
	sleep 0.2
	complete_task "$task_index" "  ${CLR_GRAY}└─${CLR_RESET} Preparing autoinstall"
	sleep 0.4
	add_log ""

	add_log "${CLR_CYAN}▼ Installation${CLR_RESET}"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Booting installer"
	task_index=$TASK_INDEX
	sleep 1.2
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}QEMU started (PID: 12345)${CLR_RESET}"
	sleep 0.3
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Booting installer"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Installing base system"
	task_index=$TASK_INDEX
	sleep 0.5
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Partitioning disks${CLR_RESET}"
	sleep 0.8
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Creating ZFS pool${CLR_RESET}"
	sleep 0.8
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Installing packages${CLR_RESET}"
	sleep 1.2
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Installing base system"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Configuring bootloader"
	task_index=$TASK_INDEX
	sleep 0.9
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Installing GRUB${CLR_RESET}"
	sleep 0.5
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Configuring bootloader"
	sleep 0.3

	start_task "  ${CLR_GRAY}└─${CLR_RESET} Finishing installation"
	task_index=$TASK_INDEX
	sleep 0.5
	complete_task "$task_index" "  ${CLR_GRAY}└─${CLR_RESET} Finishing installation"
	sleep 0.5
	add_log ""

	add_log "${CLR_CYAN}▼ Configuration${CLR_RESET}"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Configuring network"
	task_index=$TASK_INDEX
	sleep 0.4
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Creating bridge vmbr0${CLR_RESET}"
	sleep 0.3
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Setting up NAT${CLR_RESET}"
	sleep 0.3
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Configuring network"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Installing packages"
	task_index=$TASK_INDEX
	sleep 0.5
	local packages=("btop" "iotop" "ncdu" "tmux" "pigz" "smartmontools" "jq" "bat" "fastfetch")
	for pkg in "${packages[@]}"; do
		sleep 0.2
		add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Installing $pkg${CLR_RESET}"
	done
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Installing packages"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Setting up firewall"
	task_index=$TASK_INDEX
	sleep 0.4
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Configuring fail2ban${CLR_RESET}"
	sleep 0.4
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Setting up iptables rules${CLR_RESET}"
	sleep 0.4
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Setting up firewall"
	sleep 0.3

	start_task "  ${CLR_GRAY}└─${CLR_RESET} Enabling services"
	task_index=$TASK_INDEX
	sleep 0.4
	add_log "  ${CLR_GRAY} ${CLR_RESET}   ${CLR_GRAY}Starting pve-cluster${CLR_RESET}"
	sleep 0.3
	add_log "  ${CLR_GRAY} ${CLR_RESET}   ${CLR_GRAY}Starting pveproxy${CLR_RESET}"
	sleep 0.3
	complete_task "$task_index" "  ${CLR_GRAY}└─${CLR_RESET} Enabling services"
	sleep 0.5
	add_log ""

	add_log "${CLR_CYAN}▼ Finalization${CLR_RESET}"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Deploying SSH hardening"
	task_index=$TASK_INDEX
	sleep 0.3
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Disabling password authentication${CLR_RESET}"
	sleep 0.3
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Installing SSH key${CLR_RESET}"
	sleep 0.3
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Deploying SSH hardening"
	sleep 0.3

	start_task "  ${CLR_GRAY}├─${CLR_RESET} Validating installation"
	task_index=$TASK_INDEX
	sleep 0.4
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Checking services: ${CLR_CYAN}OK${CLR_RESET}"
	sleep 0.3
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Checking network: ${CLR_CYAN}OK${CLR_RESET}"
	sleep 0.3
	add_log "  ${CLR_GRAY}│${CLR_RESET}   ${CLR_GRAY}Checking storage: ${CLR_CYAN}OK${CLR_RESET}"
	sleep 0.3
	complete_task "$task_index" "  ${CLR_GRAY}├─${CLR_RESET} Validating installation"
	sleep 0.3

	start_task "  ${CLR_GRAY}└─${CLR_RESET} Powering off VM"
	task_index=$TASK_INDEX
	sleep 0.5
	complete_task "$task_index" "  ${CLR_GRAY}└─${CLR_RESET} Powering off VM"
	sleep 0.5
	add_log ""

	add_log "${CLR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLR_RESET}"
	add_log "${CLR_CYAN}✓ Installation completed successfully!${CLR_RESET}"
	add_log "${CLR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLR_RESET}"
	add_log ""
	add_log "${CLR_CYAN}System is ready to boot!${CLR_RESET}"
	add_log ""
}

main() {
	if ! command -v gum &>/dev/null; then
		echo -e "${CLR_RED}Error: gum is not installed${CLR_RESET}"
		exit 1
	fi

	clear
	show_logo
	save_cursor_position
	tput civis

	trap 'tput cnorm' EXIT

	run_installation

	tput cnorm
	echo ""
	read -n 1 -s -r -p "Press any key to exit..."
	clear
}

main
