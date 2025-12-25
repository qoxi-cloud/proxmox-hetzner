# shellcheck shell=bash
# =============================================================================
# Wizard menu option lists (WIZ_ prefix to avoid conflicts)
# =============================================================================

# Proxmox repository types
# shellcheck disable=SC2034
readonly WIZ_REPO_TYPES="No-subscription (free)
Enterprise
Test/Development"

# IPv6 configuration modes
# shellcheck disable=SC2034
readonly WIZ_IPV6_MODES="Auto
Manual
Disabled"

# Private subnet presets
# shellcheck disable=SC2034
readonly WIZ_PRIVATE_SUBNETS="10.0.0.0/24
192.168.1.0/24
172.16.0.0/24
Custom"

# ZFS RAID levels (base options, raid5/raid10 added dynamically based on drive count)
# shellcheck disable=SC2034
readonly WIZ_ZFS_MODES="Single disk
RAID-1 (mirror)"

# SSL certificate types
# shellcheck disable=SC2034
readonly WIZ_SSL_TYPES="Self-signed
Let's Encrypt"

# Firewall modes (nftables)
# shellcheck disable=SC2034
readonly WIZ_FIREWALL_MODES="Stealth (Tailscale only)
Strict (SSH only)
Standard (SSH + Web UI)
Disabled"

# Common toggle options (reusable for multiple menus)
# shellcheck disable=SC2034
readonly WIZ_TOGGLE_OPTIONS="Enabled
Disabled"

# Password entry options
# shellcheck disable=SC2034
readonly WIZ_PASSWORD_OPTIONS="Manual entry
Generate password"

# SSH key options (when key detected)
# shellcheck disable=SC2034
readonly WIZ_SSH_KEY_OPTIONS="Use detected key
Enter different key"

# Feature toggles - Security
# shellcheck disable=SC2034
readonly WIZ_FEATURES_SECURITY="apparmor
auditd
aide
chkrootkit
lynis
needrestart"

# Feature toggles - Monitoring
# shellcheck disable=SC2034
readonly WIZ_FEATURES_MONITORING="vnstat
netdata
promtail"

# Feature toggles - Tools
# shellcheck disable=SC2034
readonly WIZ_FEATURES_TOOLS="yazi
nvim
ringbuffer"

# =============================================================================
# Display → Internal value mappings for _wiz_choose_mapped
# Format: "Display text:internal_value"
# =============================================================================

# Bridge mode mapping
# shellcheck disable=SC2034
readonly WIZ_MAP_BRIDGE_MODE=(
  "External bridge:external"
  "Internal NAT:internal"
  "Both:both"
)

# Bridge MTU mapping
# shellcheck disable=SC2034
readonly WIZ_MAP_BRIDGE_MTU=(
  "9000 (jumbo frames):9000"
  "1500 (standard):1500"
)

# Shell type mapping
# shellcheck disable=SC2034
readonly WIZ_MAP_SHELL=(
  "ZSH:zsh"
  "Bash:bash"
)

# ZFS ARC mode mapping
# shellcheck disable=SC2034
readonly WIZ_MAP_ZFS_ARC=(
  "VM-focused (4GB fixed):vm-focused"
  "Balanced (25-40% of RAM):balanced"
  "Storage-focused (50% of RAM):storage-focused"
)
