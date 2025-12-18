# shellcheck shell=bash
# =============================================================================
# Configuration Wizard - UI Rendering Helpers
# =============================================================================

# =============================================================================
# Key reading helper
# =============================================================================

# Read a single key press (handles arrow keys as escape sequences)
# Returns: Key name in WIZ_KEY variable
_wiz_read_key() {
	local key
	IFS= read -rsn1 key

	# Handle escape sequences (arrow keys)
	if [[ $key == $'\x1b' ]]; then
		read -rsn2 -t 0.1 key
		case "$key" in
		'[A') WIZ_KEY="up" ;;
		'[B') WIZ_KEY="down" ;;
		'[C') WIZ_KEY="right" ;;
		'[D') WIZ_KEY="left" ;;
		*) WIZ_KEY="esc" ;;
		esac
	elif [[ $key == "" ]]; then
		WIZ_KEY="enter"
	elif [[ $key == "q" || $key == "Q" ]]; then
		WIZ_KEY="quit"
	elif [[ $key == "s" || $key == "S" ]]; then
		WIZ_KEY="start"
	else
		WIZ_KEY="$key"
	fi
}

# =============================================================================
# UI rendering helpers
# =============================================================================

# Hide/show cursor
_wiz_hide_cursor() { printf '\033[?25l'; }
_wiz_show_cursor() { printf '\033[?25h'; }

# Blank line helper
_wiz_blank_line() { echo ""; }

# Text styling helpers
_wiz_error() { gum style --foreground "$HEX_RED" "$@"; }
_wiz_warn() { gum style --foreground "$HEX_YELLOW" "$@"; }
_wiz_info() { gum style --foreground "$HEX_CYAN" "$@"; }
_wiz_dim() { gum style --foreground "$HEX_GRAY" "$@"; }

# Displays a description block for menu screens.
# Outputs all lines at once to avoid line-by-line rendering.
# Supports {{cyan:text}} syntax for inline highlighting.
# Usage: _wiz_description "Line 1" "Line 2" "" "Line 4 with {{cyan:highlight}}"
_wiz_description() {
	local output=""
	for line in "$@"; do
		# Replace {{cyan:text}} with actual color codes
		line="${line//\{\{cyan:/${CLR_CYAN}}"
		line="${line//\}\}/${CLR_GRAY}}"
		output+="${CLR_GRAY}${line}${CLR_RESET}\n"
	done
	printf '%b' "$output"
}

# Gum component wrappers with consistent styling
_wiz_confirm() {
	gum confirm "$@" \
		--prompt.foreground "$HEX_ORANGE" \
		--selected.background "$HEX_ORANGE"
}

_wiz_choose() {
	gum choose \
		--header.foreground "$HEX_CYAN" \
		--cursor "${CLR_ORANGE}›${CLR_RESET} " \
		--cursor.foreground "$HEX_NONE" \
		--selected.foreground "$HEX_WHITE" \
		--no-show-help \
		"$@"
}

_wiz_input() {
	gum input \
		--prompt.foreground "$HEX_CYAN" \
		--cursor.foreground "$HEX_ORANGE" \
		--no-show-help \
		"$@"
}

# Clear screen in alternate buffer (faster than clear)
_wiz_clear() {
	printf '\033[H\033[J'
}

# Clear screen and show banner (common pattern in editors)
_wiz_start_edit() {
	_wiz_clear
	show_banner
	_wiz_blank_line
}

# Show input screen with optional description
# Usage: _wiz_input_screen "Description line 1" "Description line 2" ...
_wiz_input_screen() {
	_wiz_start_edit
	# Show description lines if provided
	for line in "$@"; do
		_wiz_dim "$line"
	done
	[[ $# -gt 0 ]] && echo ""
	_show_input_footer
}

# Format value for display - shows placeholder if empty
# Parameters:
#   $1 - value to display
#   $2 - placeholder text (default: "→ set value")
_wiz_fmt() {
	local value="$1"
	local placeholder="${2:-→ set value}"
	if [[ -n $value ]]; then
		echo "$value"
	else
		echo "${CLR_GRAY}${placeholder}${CLR_RESET}"
	fi
}

# Menu item indices (for mapping selection to edit functions)
# These track which items are selectable fields vs section headers
_WIZ_FIELD_COUNT=0
_WIZ_FIELD_MAP=()

# Render the main menu with current selection highlighted
# Parameters:
#   $1 - Current selection index (0-based, only counts selectable fields)
_wiz_render_menu() {
	local selection="$1"
	local output=""
	local banner_output

	# Capture banner output
	banner_output=$(show_banner)

	# Start building full screen output with blank line before banner
	output="\n${banner_output}\n\n"

	# Build display values
	local pass_display=""
	if [[ -n $NEW_ROOT_PASSWORD ]]; then
		pass_display="********"
	fi

	local ipv6_display=""
	if [[ -n $IPV6_MODE ]]; then
		case "$IPV6_MODE" in
		auto)
			ipv6_display="Auto"
			if [[ -n $MAIN_IPV6 ]]; then
				ipv6_display+=" (${MAIN_IPV6})"
			fi
			;;
		manual)
			ipv6_display="Manual"
			if [[ -n $MAIN_IPV6 ]]; then
				ipv6_display+=" (${MAIN_IPV6}, gw: ${IPV6_GATEWAY})"
			fi
			;;
		disabled) ipv6_display="Disabled" ;;
		*) ipv6_display="$IPV6_MODE" ;;
		esac
	fi

	local tailscale_display=""
	if [[ -n $INSTALL_TAILSCALE ]]; then
		if [[ $INSTALL_TAILSCALE == "yes" ]]; then
			tailscale_display="Enabled + Stealth"
		else
			tailscale_display="Disabled"
		fi
	fi

	local ssl_display=""
	if [[ -n $SSL_TYPE ]]; then
		case "$SSL_TYPE" in
		self-signed) ssl_display="Self-signed" ;;
		letsencrypt) ssl_display="Let's Encrypt" ;;
		*) ssl_display="$SSL_TYPE" ;;
		esac
	fi

	local repo_display=""
	if [[ -n $PVE_REPO_TYPE ]]; then
		case "$PVE_REPO_TYPE" in
		no-subscription) repo_display="No-subscription (free)" ;;
		enterprise) repo_display="Enterprise" ;;
		test) repo_display="Test/Development" ;;
		*) repo_display="$PVE_REPO_TYPE" ;;
		esac
	fi

	local bridge_display=""
	if [[ -n $BRIDGE_MODE ]]; then
		case "$BRIDGE_MODE" in
		external) bridge_display="External bridge" ;;
		internal) bridge_display="Internal NAT" ;;
		both) bridge_display="Both" ;;
		*) bridge_display="$BRIDGE_MODE" ;;
		esac
	fi

	local zfs_display=""
	if [[ -n $ZFS_RAID ]]; then
		case "$ZFS_RAID" in
		single) zfs_display="Single disk" ;;
		raid0) zfs_display="RAID-0 (striped)" ;;
		raid1) zfs_display="RAID-1 (mirror)" ;;
		raidz1) zfs_display="RAID-Z1 (parity)" ;;
		raidz2) zfs_display="RAID-Z2 (double parity)" ;;
		raid5) zfs_display="RAID-5 (parity)" ;; # legacy
		raid10) zfs_display="RAID-10 (striped mirrors)" ;;
		*) zfs_display="$ZFS_RAID" ;;
		esac
	fi

	local zfs_arc_display=""
	if [[ -n $ZFS_ARC_MODE ]]; then
		case "$ZFS_ARC_MODE" in
		vm-focused) zfs_arc_display="VM-focused (4GB)" ;;
		balanced) zfs_arc_display="Balanced (25-40%)" ;;
		storage-focused) zfs_arc_display="Storage-focused (50%)" ;;
		*) zfs_arc_display="$ZFS_ARC_MODE" ;;
		esac
	fi

	local shell_display=""
	if [[ -n $SHELL_TYPE ]]; then
		case "$SHELL_TYPE" in
		zsh) shell_display="ZSH" ;;
		bash) shell_display="Bash" ;;
		*) shell_display="$SHELL_TYPE" ;;
		esac
	fi

	local power_display=""
	if [[ -n $CPU_GOVERNOR ]]; then
		case "$CPU_GOVERNOR" in
		performance) power_display="Performance" ;;
		ondemand) power_display="Balanced" ;;
		powersave) power_display="Power saving" ;;
		schedutil) power_display="Adaptive" ;;
		conservative) power_display="Conservative" ;;
		*) power_display="$CPU_GOVERNOR" ;;
		esac
	fi

	# Security features display
	local security_display="none"
	local security_items=()
	[[ $INSTALL_APPARMOR == "yes" ]] && security_items+=("apparmor")
	[[ $INSTALL_AUDITD == "yes" ]] && security_items+=("auditd")
	[[ $INSTALL_AIDE == "yes" ]] && security_items+=("aide")
	[[ $INSTALL_CHKROOTKIT == "yes" ]] && security_items+=("chkrootkit")
	[[ $INSTALL_LYNIS == "yes" ]] && security_items+=("lynis")
	[[ $INSTALL_NEEDRESTART == "yes" ]] && security_items+=("needrestart")
	[[ ${#security_items[@]} -gt 0 ]] && security_display="${security_items[*]// /, }"

	# Monitoring features display
	local monitoring_display="none"
	local monitoring_items=()
	[[ $INSTALL_VNSTAT == "yes" ]] && monitoring_items+=("vnstat")
	[[ $INSTALL_NETDATA == "yes" ]] && monitoring_items+=("netdata")
	[[ $INSTALL_PROMETHEUS == "yes" ]] && monitoring_items+=("prometheus")
	[[ ${#monitoring_items[@]} -gt 0 ]] && monitoring_display="${monitoring_items[*]// /, }"

	# Tools display
	local tools_display="none"
	local tools_items=()
	[[ $INSTALL_YAZI == "yes" ]] && tools_items+=("yazi")
	[[ $INSTALL_NVIM == "yes" ]] && tools_items+=("nvim")
	[[ $INSTALL_RINGBUFFER == "yes" ]] && tools_items+=("ringbuffer")
	[[ ${#tools_items[@]} -gt 0 ]] && tools_display="${tools_items[*]// /, }"

	local api_token_display=""
	if [[ -n $INSTALL_API_TOKEN ]]; then
		case "$INSTALL_API_TOKEN" in
		yes) api_token_display="Yes (${API_TOKEN_NAME})" ;;
		no) api_token_display="No" ;;
		*) api_token_display="" ;;
		esac
	fi

	local ssh_display=""
	if [[ -n $SSH_PUBLIC_KEY ]]; then
		# Show first 20 chars of key type and fingerprint hint
		ssh_display="${SSH_PUBLIC_KEY:0:20}..."
	fi

	local firewall_display=""
	if [[ -n $INSTALL_FIREWALL ]]; then
		if [[ $INSTALL_FIREWALL == "yes" ]]; then
			case "$FIREWALL_MODE" in
			stealth) firewall_display="Stealth (Tailscale only)" ;;
			strict) firewall_display="Strict (SSH only)" ;;
			standard) firewall_display="Standard (SSH + Web UI)" ;;
			*) firewall_display="$FIREWALL_MODE" ;;
			esac
		else
			firewall_display="Disabled"
		fi
	fi

	local iso_version_display=""
	if [[ -n $PROXMOX_ISO_VERSION ]]; then
		iso_version_display=$(get_iso_version "$PROXMOX_ISO_VERSION")
	fi

	local hostname_display=""
	if [[ -n $PVE_HOSTNAME && -n $DOMAIN_SUFFIX ]]; then
		hostname_display="${PVE_HOSTNAME}.${DOMAIN_SUFFIX}"
	fi

	# Reset field map
	_WIZ_FIELD_MAP=()
	local field_idx=0

	# Helper to add section header
	_add_section() {
		output+="${CLR_CYAN}--- $1 ---${CLR_RESET}\n"
	}

	# Helper to add field
	_add_field() {
		local label="$1"
		local value="$2"
		local field_name="$3"
		_WIZ_FIELD_MAP+=("$field_name")
		if [[ $field_idx -eq $selection ]]; then
			output+="${CLR_ORANGE}›${CLR_RESET} ${CLR_GRAY}${label}${CLR_RESET}${value}\n"
		else
			output+="  ${CLR_GRAY}${label}${CLR_RESET}${value}\n"
		fi
		((field_idx++))
	}

	# --- Basic Settings ---
	_add_section "Basic Settings"
	_add_field "Hostname         " "$(_wiz_fmt "$hostname_display")" "hostname"
	_add_field "Email            " "$(_wiz_fmt "$EMAIL")" "email"
	_add_field "Password         " "$(_wiz_fmt "$pass_display")" "password"
	_add_field "Timezone         " "$(_wiz_fmt "$TIMEZONE")" "timezone"
	_add_field "Keyboard         " "$(_wiz_fmt "$KEYBOARD")" "keyboard"
	_add_field "Country          " "$(_wiz_fmt "$COUNTRY")" "country"

	# --- Proxmox ---
	_add_section "Proxmox"
	_add_field "Version          " "$(_wiz_fmt "$iso_version_display")" "iso_version"
	_add_field "Repository       " "$(_wiz_fmt "$repo_display")" "repository"

	# --- Network ---
	_add_section "Network"
	# Show interface selector only if multiple interfaces available
	if [[ ${INTERFACE_COUNT:-1} -gt 1 ]]; then
		_add_field "Interface        " "$(_wiz_fmt "$INTERFACE_NAME")" "interface"
	fi
	_add_field "Bridge mode      " "$(_wiz_fmt "$bridge_display")" "bridge_mode"
	# Show private network options only for internal/both modes
	if [[ $BRIDGE_MODE == "internal" ]] || [[ $BRIDGE_MODE == "both" ]]; then
		_add_field "Private subnet   " "$(_wiz_fmt "$PRIVATE_SUBNET")" "private_subnet"
		local mtu_display="${BRIDGE_MTU:-9000}"
		[[ $mtu_display == "9000" ]] && mtu_display="9000 (jumbo)"
		_add_field "Bridge MTU       " "$(_wiz_fmt "$mtu_display")" "bridge_mtu"
	fi
	_add_field "IPv6             " "$(_wiz_fmt "$ipv6_display")" "ipv6"
	_add_field "Firewall         " "$(_wiz_fmt "$firewall_display")" "firewall"

	# --- Storage ---
	_add_section "Storage"

	# Show boot/pool selectors if multiple disks
	if [[ $DRIVE_COUNT -gt 1 ]]; then
		local boot_display="All in pool"
		if [[ -n $BOOT_DISK ]]; then
			# Find disk model by matching BOOT_DISK in DRIVES array
			for i in "${!DRIVES[@]}"; do
				if [[ ${DRIVES[$i]} == "$BOOT_DISK" ]]; then
					boot_display="${DRIVE_MODELS[$i]}"
					break
				fi
			done
		fi
		_add_field "Boot disk        " "$(_wiz_fmt "$boot_display")" "boot_disk"

		local pool_display="${#ZFS_POOL_DISKS[@]} disks"
		_add_field "Pool disks       " "$(_wiz_fmt "$pool_display")" "pool_disks"
	fi

	_add_field "ZFS mode         " "$(_wiz_fmt "$zfs_display")" "zfs_mode"
	_add_field "ZFS ARC          " "$(_wiz_fmt "$zfs_arc_display")" "zfs_arc"

	# --- VPN ---
	_add_section "VPN"
	_add_field "Tailscale        " "$(_wiz_fmt "$tailscale_display")" "tailscale"

	# --- SSL --- (hidden when Tailscale enabled - uses Tailscale certs)
	if [[ $INSTALL_TAILSCALE != "yes" ]]; then
		_add_section "SSL"
		_add_field "Certificate      " "$(_wiz_fmt "$ssl_display")" "ssl"
	fi

	# --- Optional ---
	_add_section "Optional"
	_add_field "Shell            " "$(_wiz_fmt "$shell_display")" "shell"
	_add_field "Power profile    " "$(_wiz_fmt "$power_display")" "power_profile"
	_add_field "Security         " "$(_wiz_fmt "$security_display")" "security"
	_add_field "Monitoring       " "$(_wiz_fmt "$monitoring_display")" "monitoring"
	_add_field "Tools            " "$(_wiz_fmt "$tools_display")" "tools"
	_add_field "API Token        " "$(_wiz_fmt "$api_token_display")" "api_token"

	# --- SSH ---
	_add_section "SSH"
	_add_field "SSH Key          " "$(_wiz_fmt "$ssh_display")" "ssh_key"

	# Store total field count
	_WIZ_FIELD_COUNT=$field_idx

	output+="\n"

	# Footer
	output+="${CLR_GRAY}[${CLR_ORANGE}↑↓${CLR_GRAY}] navigate  [${CLR_ORANGE}Enter${CLR_GRAY}] edit  [${CLR_ORANGE}S${CLR_GRAY}] start  [${CLR_ORANGE}Q${CLR_GRAY}] quit${CLR_RESET}"

	# Clear screen and output everything atomically
	_wiz_clear
	printf '%b' "$output"
}
