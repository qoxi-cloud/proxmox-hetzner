#!/usr/bin/env bash
cd /root||exit 1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
readonly CLR_BOLD=$'\033[1m'
readonly CLR_RED=$'\033[1;31m'
readonly CLR_CYAN=$'\033[38;2;0;177;255m'
readonly CLR_YELLOW=$'\033[1;33m'
readonly CLR_ORANGE=$'\033[38;5;208m'
readonly CLR_GRAY=$'\033[38;5;240m'
readonly CLR_HETZNER=$'\033[38;5;160m'
readonly CLR_RESET=$'\033[m'
readonly HEX_RED="#ff0000"
readonly HEX_CYAN="#00b1ff"
readonly HEX_YELLOW="#ffff00"
readonly HEX_ORANGE="#ff8700"
readonly HEX_GRAY="#585858"
readonly HEX_WHITE="#ffffff"
readonly HEX_NONE="7"
readonly VERSION="2.0.345-pr.21"
GITHUB_REPO="${GITHUB_REPO:-qoxi-cloud/proxmox-hetzner}"
GITHUB_BRANCH="${GITHUB_BRANCH:-feat/interactive-config-table}"
GITHUB_BASE_URL="https://github.com/$GITHUB_REPO/raw/refs/heads/$GITHUB_BRANCH"
readonly PROXMOX_ISO_BASE_URL="https://enterprise.proxmox.com/iso/"
readonly PROXMOX_CHECKSUM_URL="https://enterprise.proxmox.com/iso/SHA256SUMS"
readonly DNS_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
readonly DNS_PRIMARY="1.1.1.1"
readonly DNS_SECONDARY="1.0.0.1"
readonly DNS6_PRIMARY="2606:4700:4700::1111"
readonly DNS6_SECONDARY="2606:4700:4700::1001"
readonly MIN_DISK_SPACE_MB=6000
readonly MIN_RAM_MB=4000
readonly MIN_CPU_CORES=2
readonly MIN_QEMU_RAM=4096
readonly DOWNLOAD_RETRY_COUNT=3
readonly DOWNLOAD_RETRY_DELAY=2
readonly SSH_CONNECT_TIMEOUT=10
readonly DEFAULT_PASSWORD_LENGTH=16
readonly QEMU_MIN_RAM_RESERVE=2048
readonly DNS_LOOKUP_TIMEOUT=5
readonly DNS_RETRY_DELAY=10
readonly WIZ_KEYBOARD_LAYOUTS="de
de-ch
dk
en-gb
en-us
es
fi
fr
fr-be
fr-ca
fr-ch
hu
is
it
jp
lt
mk
nl
no
pl
pt
pt-br
se
si
tr"
readonly WIZ_REPO_TYPES="No-subscription (free)
Enterprise
Test/Development"
readonly WIZ_BRIDGE_MODES="External bridge
Internal NAT
Both"
readonly WIZ_BRIDGE_MTU="9000 (jumbo frames)
1500 (standard)"
readonly WIZ_IPV6_MODES="Auto
Manual
Disabled"
readonly WIZ_PRIVATE_SUBNETS="10.0.0.0/24
192.168.1.0/24
172.16.0.0/24
Custom"
readonly WIZ_ZFS_MODES="Single disk
RAID-1 (mirror)"
readonly WIZ_ZFS_ARC_MODES="VM-focused (4GB fixed)
Balanced (25-40% of RAM)
Storage-focused (50% of RAM)"
readonly WIZ_SSL_TYPES="Self-signed
Let's Encrypt"
readonly WIZ_SHELL_OPTIONS="ZSH
Bash"
readonly WIZ_FIREWALL_MODES="Stealth (Tailscale only)
Strict (SSH only)
Standard (SSH + Web UI)
Disabled"
BOOT_DISK=""
ZFS_POOL_DISKS=()
SYSTEM_UTILITIES="btop iotop ncdu tmux pigz smartmontools jq bat fastfetch sysstat nethogs ethtool"
OPTIONAL_PACKAGES="libguestfs-tools"
LOG_FILE="/root/pve-install-$(date +%Y%m%d-%H%M%S).log"
INSTALL_COMPLETED=false
cleanup_temp_files(){
rm -f /tmp/tailscale_*.txt /tmp/iso_checksum.txt /tmp/*.tmp /tmp/pve-install-api-token.env 2>/dev/null||true
rm -f /root/answer.toml 2>/dev/null||true
if [[ $INSTALL_COMPLETED != "true" ]];then
rm -f /root/pve.iso /root/pve-autoinstall.iso /root/SHA256SUMS 2>/dev/null||true
rm -f /root/qemu_*.log 2>/dev/null||true
fi
find /dev/shm /tmp -name "pve-passfile.*" -type f -delete 2>/dev/null||true
find /dev/shm /tmp -name "*passfile*" -type f -delete 2>/dev/null||true
}
cleanup_and_error_handler(){
local exit_code=$?
jobs -p|xargs -r kill 2>/dev/null||true
sleep 1
cleanup_temp_files
if [[ -n ${QEMU_PID:-} ]]&&kill -0 "$QEMU_PID" 2>/dev/null;then
log "Cleaning up QEMU process $QEMU_PID"
if type release_drives &>/dev/null;then
release_drives
else
pkill -TERM qemu-system-x86 2>/dev/null||true
sleep 2
pkill -9 qemu-system-x86 2>/dev/null||true
fi
fi
tput cnorm 2>/dev/null||true
if [[ $INSTALL_COMPLETED != "true" && $exit_code -ne 0 ]];then
echo -e "$CLR_RED*** INSTALLATION FAILED ***$CLR_RESET"
echo ""
echo -e "${CLR_YELLOW}An error occurred and the installation was aborted.$CLR_RESET"
echo ""
echo -e "${CLR_YELLOW}Please check the log file for details:$CLR_RESET"
echo -e "$CLR_YELLOW  $LOG_FILE$CLR_RESET"
echo ""
fi
}
trap cleanup_and_error_handler EXIT
INSTALL_START_TIME=$(date +%s)
QEMU_RAM_OVERRIDE=""
QEMU_CORES_OVERRIDE=""
PROXMOX_ISO_VERSION=""
PVE_REPO_TYPE=""
PVE_SUBSCRIPTION_KEY=""
SSL_TYPE=""
SHELL_TYPE=""
KEYBOARD="en-us"
COUNTRY="us"
LOCALE="en_US.UTF-8"
TIMEZONE="UTC"
INSTALL_AUDITD=""
INSTALL_AIDE=""
INSTALL_APPARMOR=""
CPU_GOVERNOR=""
ZFS_ARC_MODE=""
INSTALL_CHKROOTKIT=""
INSTALL_LYNIS=""
INSTALL_NEEDRESTART=""
INSTALL_NETDATA=""
INSTALL_RINGBUFFER=""
INSTALL_VNSTAT=""
INSTALL_PROMETHEUS=""
INSTALL_YAZI=""
INSTALL_NVIM=""
INSTALL_UNATTENDED_UPGRADES=""
INSTALL_TAILSCALE=""
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH=""
TAILSCALE_WEBUI=""
BRIDGE_MTU=""
INSTALL_API_TOKEN=""
API_TOKEN_NAME="automation"
API_TOKEN_VALUE=""
API_TOKEN_ID=""
INSTALL_FIREWALL=""
FIREWALL_MODE=""
show_help(){
cat <<EOF
Proxmox VE Automated Installer for Hetzner v$VERSION

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
exit 0
}
while [[ $# -gt 0 ]];do
case $1 in
-h|--help)show_help
;;
-v|--version)echo "Proxmox Installer v$VERSION"
exit 0
;;
--qemu-ram)if
[[ -z $2 || $2 =~ ^- ]]
then
echo -e "${CLR_RED}Error: --qemu-ram requires a value in MB$CLR_RESET"
exit 1
fi
if ! [[ $2 =~ ^[0-9]+$ ]]||[[ $2 -lt 2048 ]];then
echo -e "${CLR_RED}Error: --qemu-ram must be a number >= 2048 MB$CLR_RESET"
exit 1
fi
if [[ $2 -gt 131072 ]];then
echo -e "${CLR_RED}Error: --qemu-ram must be <= 131072 MB (128 GB)$CLR_RESET"
exit 1
fi
QEMU_RAM_OVERRIDE="$2"
shift 2
;;
--qemu-cores)if
[[ -z $2 || $2 =~ ^- ]]
then
echo -e "${CLR_RED}Error: --qemu-cores requires a value$CLR_RESET"
exit 1
fi
if ! [[ $2 =~ ^[0-9]+$ ]]||[[ $2 -lt 1 ]];then
echo -e "${CLR_RED}Error: --qemu-cores must be a positive number$CLR_RESET"
exit 1
fi
if [[ $2 -gt 256 ]];then
echo -e "${CLR_RED}Error: --qemu-cores must be <= 256$CLR_RESET"
exit 1
fi
QEMU_CORES_OVERRIDE="$2"
shift 2
;;
--iso-version)if
[[ -z $2 || $2 =~ ^- ]]
then
echo -e "${CLR_RED}Error: --iso-version requires a filename$CLR_RESET"
exit 1
fi
if ! [[ $2 =~ ^proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso$ ]];then
echo -e "${CLR_RED}Error: --iso-version must be in format: proxmox-ve_X.Y-Z.iso$CLR_RESET"
exit 1
fi
PROXMOX_ISO_VERSION="$2"
shift 2
;;
*)echo "Unknown option: $1"
echo "Use --help for usage information"
exit 1
esac
done
log(){
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}
INSTALL_START_TIME=""
metrics_start(){
INSTALL_START_TIME=$(date +%s)
log "METRIC: installation_started"
}
log_metric(){
local step="$1"
if [[ -n $INSTALL_START_TIME ]];then
local elapsed=$(($(date +%s)-INSTALL_START_TIME))
log "METRIC: ${step}_completed elapsed=${elapsed}s"
fi
}
metrics_finish(){
if [[ -n $INSTALL_START_TIME ]];then
local total=$(($(date +%s)-INSTALL_START_TIME))
local minutes=$((total/60))
local seconds=$((total%60))
log "METRIC: installation_completed total_time=${total}s (${minutes}m ${seconds}s)"
fi
}
BANNER_LETTER_COUNT=7
BANNER_HEIGHT=9
_BANNER_PAD="        "
show_banner(){
local p="$_BANNER_PAD"
printf '%s\n' \
"$p$CLR_GRAY _____                                             $CLR_RESET" \
"$p$CLR_GRAY|  __ \\                                            $CLR_RESET" \
"$p$CLR_GRAY| |__) | _ __   ___  ${CLR_ORANGE}__  __$CLR_GRAY  _ __ ___    ___  ${CLR_ORANGE}__  __$CLR_RESET" \
"$p$CLR_GRAY|  ___/ | '__| / _ \\ $CLR_ORANGE\\ \\/ /$CLR_GRAY | '_ \` _ \\  / _ \\ $CLR_ORANGE\\ \\/ /$CLR_RESET" \
"$p$CLR_GRAY| |     | |   | (_) |$CLR_ORANGE >  <$CLR_GRAY  | | | | | || (_) |$CLR_ORANGE >  <$CLR_RESET" \
"$p$CLR_GRAY|_|     |_|    \\___/ $CLR_ORANGE/_/\\_\\$CLR_GRAY |_| |_| |_| \\___/ $CLR_ORANGE/_/\\_\\$CLR_RESET" \
"" \
"$p$CLR_HETZNER            Hetzner ${CLR_GRAY}Automated Installer$CLR_RESET"
}
_show_banner_frame(){
local h="${1:--1}"
local M="$CLR_GRAY"
local A="$CLR_ORANGE"
local R="$CLR_RESET"
local p="$_BANNER_PAD"
local line1="$p$M "
[[ $h -eq 0 ]]&&line1+="${A}_____$M"||line1+="_____"
line1+="                                             $R"
local line2="$p$M"
[[ $h -eq 0 ]]&&line2+="$A|  __ \\$M"||line2+='|  __ \'
line2+="                                            $R"
local line3="$p$M"
[[ $h -eq 0 ]]&&line3+="$A| |__) |$M"||line3+="| |__) |"
[[ $h -eq 1 ]]&&line3+=" ${A}_ __$M"||line3+=" _ __"
[[ $h -eq 2 ]]&&line3+="   ${A}___$M"||line3+="   ___"
[[ $h -eq 3 ]]&&line3+="  ${A}__  __$M"||line3+="  __  __"
[[ $h -eq 4 ]]&&line3+="  ${A}_ __ ___$M"||line3+="  _ __ ___"
[[ $h -eq 5 ]]&&line3+="    ${A}___$M"||line3+="    ___"
[[ $h -eq 6 ]]&&line3+="  ${A}__  __$M"||line3+="  __  __"
line3+="$R"
local line4="$p$M"
[[ $h -eq 0 ]]&&line4+="$A|  ___/ $M"||line4+="|  ___/ "
[[ $h -eq 1 ]]&&line4+="$A| '__|$M"||line4+="| '__|"
[[ $h -eq 2 ]]&&line4+=" $A/ _ \\$M"||line4+=' / _ \'
[[ $h -eq 3 ]]&&line4+=" $A\\ \\/ /$M"||line4+=' \ \/ /'
[[ $h -eq 4 ]]&&line4+=" $A| '_ \` _ \\$M"||line4+=" | '_ \` _ \\"
[[ $h -eq 5 ]]&&line4+="  $A/ _ \\$M"||line4+='  / _ \'
[[ $h -eq 6 ]]&&line4+=" $A\\ \\/ /$M"||line4+=' \ \/ /'
line4+="$R"
local line5="$p$M"
[[ $h -eq 0 ]]&&line5+="$A| |     $M"||line5+="| |     "
[[ $h -eq 1 ]]&&line5+="$A| |$M"||line5+="| |"
[[ $h -eq 2 ]]&&line5+="   $A| (_) |$M"||line5+="   | (_) |"
[[ $h -eq 3 ]]&&line5+="$A >  <$M"||line5+=" >  <"
[[ $h -eq 4 ]]&&line5+="  $A| | | | | |$M"||line5+="  | | | | | |"
[[ $h -eq 5 ]]&&line5+="$A| (_) |$M"||line5+="| (_) |"
[[ $h -eq 6 ]]&&line5+="$A >  <$M"||line5+=" >  <"
line5+="$R"
local line6="$p$M"
[[ $h -eq 0 ]]&&line6+="$A|_|     $M"||line6+="|_|     "
[[ $h -eq 1 ]]&&line6+="$A|_|$M"||line6+="|_|"
[[ $h -eq 2 ]]&&line6+="    $A\\___/$M"||line6+='    \___/'
[[ $h -eq 3 ]]&&line6+=" $A/_/\\_\\$M"||line6+=' /_/\_\'
[[ $h -eq 4 ]]&&line6+=" $A|_| |_| |_|$M"||line6+=" |_| |_| |_|"
[[ $h -eq 5 ]]&&line6+=" $A\\___/$M"||line6+=' \___/'
[[ $h -eq 6 ]]&&line6+=" $A/_/\\_\\$M"||line6+=' /_/\_\'
line6+="$R"
local line_hetzner="$p$CLR_HETZNER            Hetzner ${M}Automated Installer$R"
local frame
frame=$(printf '\033[H\033[J%s\n%s\n%s\n%s\n%s\n%s\n\n%s\n' \
"$line1" \
"$line2" \
"$line3" \
"$line4" \
"$line5" \
"$line6" \
"$line_hetzner")
printf '%s' "$frame"
}
BANNER_ANIMATION_PID=""
show_banner_animated_start(){
local frame_delay="${1:-0.1}"
[[ ! -t 1 ]]&&return
show_banner_animated_stop 2>/dev/null
_wiz_hide_cursor
clear
(local direction=1
local current_letter=0
trap 'exit 0' TERM INT
trap 'clear' WINCH
exec 3>&1
exec 1>/dev/tty
exec 2>/dev/null
while true;do
_show_banner_frame "$current_letter"
sleep "$frame_delay"
if [[ $direction -eq 1 ]];then
((current_letter++))
if [[ $current_letter -ge $BANNER_LETTER_COUNT ]];then
current_letter=$((BANNER_LETTER_COUNT-2))
direction=-1
fi
else
((current_letter--))
if [[ $current_letter -lt 0 ]];then
current_letter=1
direction=1
fi
fi
done) \
&
BANNER_ANIMATION_PID=$!
}
show_banner_animated_stop(){
if [[ -n $BANNER_ANIMATION_PID ]];then
kill "$BANNER_ANIMATION_PID" 2>/dev/null
wait "$BANNER_ANIMATION_PID" 2>/dev/null
BANNER_ANIMATION_PID=""
fi
clear
show_banner
_wiz_show_cursor
}
print_success(){
if [[ $# -eq 2 ]];then
echo -e "$CLR_CYAN✓$CLR_RESET $1 $CLR_CYAN$2$CLR_RESET"
else
echo -e "$CLR_CYAN✓$CLR_RESET $1"
fi
}
print_error(){
echo -e "$CLR_RED✗$CLR_RESET $1"
}
print_warning(){
local message="$1"
local second="${2:-false}"
local indent=""
if [[ $# -eq 2 && $second != "true" ]];then
echo -e "$CLR_YELLOW⚠️$CLR_RESET $message $CLR_CYAN$second$CLR_RESET"
else
if [[ $second == "true" ]];then
indent="  "
fi
echo -e "$indent$CLR_YELLOW⚠️$CLR_RESET $message"
fi
}
print_info(){
echo -e "$CLR_CYANℹ$CLR_RESET $1"
}
print_section(){
echo "$CLR_CYAN$CLR_BOLD$1$CLR_RESET"
}
show_progress(){
local pid=$1
local message="${2:-Processing}"
local done_message="${3:-$message}"
local silent=false
[[ ${3:-} == "--silent" || ${4:-} == "--silent" ]]&&silent=true
[[ ${3:-} == "--silent" ]]&&done_message="$message"
gum spin --spinner meter --spinner.foreground "#ff8700" --title "$message" -- bash -c "
    while kill -0 $pid 2>/dev/null; do
      sleep 0.2
    done
  "
wait "$pid" 2>/dev/null
local exit_code=$?
if [[ $exit_code -eq 0 ]];then
if [[ $silent != true ]];then
printf "$CLR_CYAN✓$CLR_RESET %s\n" "$done_message"
fi
else
printf "$CLR_RED✗$CLR_RESET %s\n" "$message"
fi
return $exit_code
}
download_file(){
local output_file="$1"
local url="$2"
local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"
local retry_delay="${DOWNLOAD_RETRY_DELAY:-2}"
local retry_count=0
while [ "$retry_count" -lt "$max_retries" ];do
if wget -q -O "$output_file" "$url";then
if [ -s "$output_file" ];then
local file_type
file_type=$(file "$output_file" 2>/dev/null||echo "")
if echo "$file_type"|grep -q "empty";then
print_error "Downloaded file is empty: $output_file"
retry_count=$((retry_count+1))
continue
fi
return 0
else
print_error "Downloaded file is empty: $output_file"
fi
else
print_warning "Download failed (attempt $((retry_count+1))/$max_retries): $url"
fi
retry_count=$((retry_count+1))
[ "$retry_count" -lt "$max_retries" ]&&sleep "$retry_delay"
done
log "ERROR: Failed to download $url after $max_retries attempts"
return 1
}
validate_template_vars(){
local file="$1"
local unfilled
if [[ ! -f $file ]];then
log "ERROR: Cannot validate - file not found: $file"
return 1
fi
unfilled=$(grep -oE '\{\{[A-Z0-9_]+\}\}' "$file" 2>/dev/null|sort -u|tr '\n' ' ')
if [[ -n $unfilled ]];then
log "ERROR: Unfilled template variables in $file: $unfilled"
return 1
fi
return 0
}
apply_template_vars(){
local file="$1"
shift
if [[ ! -f $file ]];then
log "ERROR: Template file not found: $file"
return 1
fi
local sed_args=()
if [[ $# -gt 0 ]];then
for pair in "$@";do
local var="${pair%%=*}"
local value="${pair#*=}"
value="${value//\\/\\\\}"
value="${value//&/\\&}"
value="${value//|/\\|}"
sed_args+=(-e "s|{{$var}}|$value|g")
done
fi
if [[ ${#sed_args[@]} -gt 0 ]];then
sed -i "${sed_args[@]}" "$file"
fi
}
apply_common_template_vars(){
local file="$1"
local -a critical_vars=(MAIN_IPV4 MAIN_IPV4_GW PVE_HOSTNAME INTERFACE_NAME)
for var in "${critical_vars[@]}";do
if [[ -z ${!var:-} ]];then
log "WARNING: [apply_common_template_vars] Critical variable $var is empty for $file"
fi
done
apply_template_vars "$file" \
"MAIN_IPV4=${MAIN_IPV4:-}" \
"MAIN_IPV4_GW=${MAIN_IPV4_GW:-}" \
"MAIN_IPV6=${MAIN_IPV6:-}" \
"FIRST_IPV6_CIDR=${FIRST_IPV6_CIDR:-}" \
"IPV6_GATEWAY=${IPV6_GATEWAY:-fe80::1}" \
"FQDN=${FQDN:-}" \
"HOSTNAME=${PVE_HOSTNAME:-}" \
"INTERFACE_NAME=${INTERFACE_NAME:-}" \
"PRIVATE_IP_CIDR=${PRIVATE_IP_CIDR:-}" \
"PRIVATE_SUBNET=${PRIVATE_SUBNET:-}" \
"BRIDGE_MTU=${BRIDGE_MTU:-9000}" \
"DNS_PRIMARY=${DNS_PRIMARY:-1.1.1.1}" \
"DNS_SECONDARY=${DNS_SECONDARY:-1.0.0.1}" \
"DNS6_PRIMARY=${DNS6_PRIMARY:-2606:4700:4700::1111}" \
"DNS6_SECONDARY=${DNS6_SECONDARY:-2606:4700:4700::1001}" \
"LOCALE=${LOCALE:-en_US.UTF-8}" \
"KEYBOARD=${KEYBOARD:-us}" \
"COUNTRY=${COUNTRY:-US}" \
"BAT_THEME=${BAT_THEME:-Catppuccin Mocha}"
}
postprocess_interfaces_ipv6(){
local file="$1"
if [[ ! -f $file ]];then
log "ERROR: Interfaces file not found: $file"
return 1
fi
if [[ -z ${MAIN_IPV6:-} ]]||[[ ${IPV6_MODE:-} == "disabled" ]];then
log "IPv6 disabled - removing inet6 sections from interfaces"
sed -i '/^iface .* inet6 static$/,/^$/d' "$file"
fi
}
download_template(){
local local_path="$1"
local remote_file="${2:-$(basename "$local_path")}"
local url="$GITHUB_BASE_URL/templates/$remote_file.tmpl"
if ! download_file "$local_path" "$url";then
return 1
fi
if [[ ! -s $local_path ]];then
print_error "Template $remote_file is empty or download failed"
log "ERROR: Template $remote_file is empty after download"
return 1
fi
local filename
filename=$(basename "$local_path")
case "$filename" in
answer.toml)if
! grep -q "\[global\]" "$local_path" 2>/dev/null
then
print_error "Template $remote_file appears corrupted (missing [global] section)"
log "ERROR: Template $remote_file corrupted - missing [global] section"
return 1
fi
;;
sshd_config)if
! grep -q "PasswordAuthentication" "$local_path" 2>/dev/null
then
print_error "Template $remote_file appears corrupted (missing PasswordAuthentication)"
log "ERROR: Template $remote_file corrupted - missing PasswordAuthentication"
return 1
fi
;;
*.sh)if
! head -1 "$local_path"|grep -qE "^#!.*bash|^# shellcheck|^export "&&! grep -qE "(if|then|echo|function|export)" "$local_path" 2>/dev/null
then
print_error "Template $remote_file appears corrupted (invalid shell script)"
log "ERROR: Template $remote_file corrupted - invalid shell script"
return 1
fi
;;
*.conf|*.sources|*.service|*.timer)if
[[ $(wc -l <"$local_path" 2>/dev/null||echo 0) -lt 2 ]]
then
print_error "Template $remote_file appears corrupted (too short)"
log "ERROR: Template $remote_file corrupted - file too short"
return 1
fi
esac
log "Template $remote_file downloaded and validated successfully"
return 0
}
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10}"
SSH_PORT="5555"
_SSH_SESSION_PASSFILE=""
_SSH_SESSION_LOGGED=false
_ssh_session_init(){
[[ -n $_SSH_SESSION_PASSFILE ]]&&[[ -f $_SSH_SESSION_PASSFILE ]]&&return 0
if [[ -d /dev/shm ]]&&[[ -w /dev/shm ]];then
_SSH_SESSION_PASSFILE=$(mktemp --tmpdir=/dev/shm pve-ssh-session.XXXXXX 2>/dev/null||mktemp)
else
_SSH_SESSION_PASSFILE=$(mktemp)
fi
echo "$NEW_ROOT_PASSWORD" >"$_SSH_SESSION_PASSFILE"
chmod 600 "$_SSH_SESSION_PASSFILE"
if [[ $BASHPID == "$$" ]];then
local existing_trap
existing_trap=$(trap -p EXIT 2>/dev/null|sed "s/trap -- '\\(.*\\)' EXIT/\\1/"||true)
if [[ -n $existing_trap ]];then
trap "$existing_trap; _ssh_session_cleanup" EXIT
else
trap '_ssh_session_cleanup' EXIT
fi
if [[ $_SSH_SESSION_LOGGED != true ]];then
log "SSH session initialized"
_SSH_SESSION_LOGGED=true
fi
fi
}
_ssh_session_cleanup(){
[[ -z $_SSH_SESSION_PASSFILE ]]&&return 0
[[ ! -f $_SSH_SESSION_PASSFILE ]]&&return 0
if command -v shred &>/dev/null;then
shred -u -z "$_SSH_SESSION_PASSFILE" 2>/dev/null||rm -f "$_SSH_SESSION_PASSFILE"
else
if command -v dd &>/dev/null;then
local file_size
file_size=$(stat -c%s "$_SSH_SESSION_PASSFILE" 2>/dev/null||echo 1024)
dd if=/dev/zero of="$_SSH_SESSION_PASSFILE" bs=1 count="$file_size" 2>/dev/null||true
fi
rm -f "$_SSH_SESSION_PASSFILE"
fi
_SSH_SESSION_PASSFILE=""
log "SSH session cleaned up"
}
_ssh_get_passfile(){
_ssh_session_init
echo "$_SSH_SESSION_PASSFILE"
}
check_port_available(){
local port="$1"
if command -v ss &>/dev/null;then
if ss -tuln 2>/dev/null|grep -q ":$port ";then
return 1
fi
elif command -v netstat &>/dev/null;then
if netstat -tuln 2>/dev/null|grep -q ":$port ";then
return 1
fi
fi
return 0
}
wait_for_ssh_ready(){
local timeout="${1:-120}"
ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:$SSH_PORT" 2>/dev/null||true
local port_check=0
for _ in {1..10};do
if (echo >/dev/tcp/localhost/$SSH_PORT) 2>/dev/null;then
port_check=1
break
fi
sleep 1
done
if [[ $port_check -eq 0 ]];then
print_error "Port $SSH_PORT is not accessible"
log "ERROR: Port $SSH_PORT not accessible after 10 attempts"
return 1
fi
local passfile
passfile=$(_ssh_get_passfile)
(local elapsed=0
while ((elapsed<timeout));do
if sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'echo ready' >/dev/null 2>&1;then
exit 0
fi
sleep 2
((elapsed+=2))
done
exit 1) \
&
local wait_pid=$!
show_progress $wait_pid "Waiting for SSH to be ready" "SSH connection established"
return $?
}
remote_exec(){
local passfile
passfile=$(_ssh_get_passfile)
local max_attempts=3
local attempt=0
local exit_code=1
while [[ $attempt -lt $max_attempts ]];do
attempt=$((attempt+1))
if sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "$@";then
return 0
fi
if [[ $attempt -lt $max_attempts ]];then
log "SSH attempt $attempt failed, retrying in 2 seconds..."
sleep 2
fi
done
log "ERROR: SSH command failed after $max_attempts attempts: $*"
return 1
}
_remote_exec_with_progress(){
local message="$1"
local script="$2"
local done_message="${3:-$message}"
log "_remote_exec_with_progress: $message"
log "--- Script start ---"
echo "$script" >>"$LOG_FILE"
log "--- Script end ---"
local passfile
passfile=$(_ssh_get_passfile)
local output_file
output_file=$(mktemp)
echo "$script"|sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s' >"$output_file" 2>&1&
local pid=$!
show_progress $pid "$message" "$done_message"
local exit_code=$?
if grep -qiE "(error|failed|cannot|unable|fatal)" "$output_file" 2>/dev/null;then
log "WARNING: Potential errors in remote command output:"
grep -iE "(error|failed|cannot|unable|fatal)" "$output_file" >>"$LOG_FILE" 2>/dev/null||true
fi
cat "$output_file" >>"$LOG_FILE"
rm -f "$output_file"
if [[ $exit_code -ne 0 ]];then
log "_remote_exec_with_progress: FAILED with exit code $exit_code"
else
log "_remote_exec_with_progress: completed successfully"
fi
return $exit_code
}
run_remote(){
local message="$1"
local script="$2"
local done_message="${3:-$message}"
if ! _remote_exec_with_progress "$message" "$script" "$done_message";then
log "ERROR: $message failed"
exit 1
fi
}
remote_copy(){
local src="$1"
local dst="$2"
local passfile
passfile=$(_ssh_get_passfile)
sshpass -f "$passfile" scp -P "$SSH_PORT" $SSH_OPTS "$src" "root@localhost:$dst"
}
parse_ssh_key(){
local key="$1"
SSH_KEY_TYPE=""
SSH_KEY_DATA=""
SSH_KEY_COMMENT=""
SSH_KEY_SHORT=""
[[ -z $key ]]&&return 1
SSH_KEY_TYPE=$(echo "$key"|awk '{print $1}')
SSH_KEY_DATA=$(echo "$key"|awk '{print $2}')
SSH_KEY_COMMENT=$(echo "$key"|awk '{$1=""; $2=""; print}'|sed 's/^ *//')
if [[ ${#SSH_KEY_DATA} -gt 35 ]];then
SSH_KEY_SHORT="${SSH_KEY_DATA:0:20}...${SSH_KEY_DATA: -10}"
else
SSH_KEY_SHORT="$SSH_KEY_DATA"
fi
return 0
}
get_rescue_ssh_key(){
if [[ -f /root/.ssh/authorized_keys ]];then
grep -E "^ssh-(rsa|ed25519|ecdsa)" /root/.ssh/authorized_keys 2>/dev/null|head -1
fi
}
generate_password(){
local length="${1:-16}"
tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom|head -c "$length"
}
create_virtio_mapping(){
local boot_disk="$1"
shift
local pool_disks=("$@")
declare -A VIRTIO_MAP
local virtio_idx=0
local vdev_letters=(a b c d e f g h i j k l m n o p q r s t u v w x y z)
if [[ -n $boot_disk ]];then
local vdev="vd${vdev_letters[$virtio_idx]}"
VIRTIO_MAP["$boot_disk"]="$vdev"
log "Virtio mapping: $boot_disk → /dev/$vdev (boot)"
((virtio_idx++))
fi
for drive in "${pool_disks[@]}";do
local vdev="vd${vdev_letters[$virtio_idx]}"
VIRTIO_MAP["$drive"]="$vdev"
log "Virtio mapping: $drive → /dev/$vdev (pool)"
((virtio_idx++))
done
declare -p VIRTIO_MAP|sed 's/declare -A/declare -gA/' >/tmp/virtio_map.env
log "Virtio mapping saved to /tmp/virtio_map.env"
}
load_virtio_mapping(){
if [[ -f /tmp/virtio_map.env ]];then
source /tmp/virtio_map.env
return 0
else
log "ERROR: Virtio mapping file not found"
return 1
fi
}
map_disks_to_virtio(){
local format="$1"
shift
local disks=("$@")
if [[ ${#disks[@]} -eq 0 ]];then
log "ERROR: No disks provided to map_disks_to_virtio"
return 1
fi
local vdevs=()
for disk in "${disks[@]}";do
local vdev="${VIRTIO_MAP[$disk]}"
if [[ -z $vdev ]];then
log "ERROR: No virtio mapping for disk $disk"
return 1
fi
vdevs+=("/dev/$vdev")
done
case "$format" in
toml_array)local result="["
for i in "${!vdevs[@]}";do
local short_name="${vdevs[$i]#/dev/}"
result+="\"$short_name\""
[[ $i -lt $((${#vdevs[@]}-1)) ]]&&result+=", "
done
result+="]"
echo "$result"
;;
bash_array)echo "(${vdevs[*]})"
;;
space_separated)echo "${vdevs[*]}"
;;
*)log "ERROR: Unknown format: $format"
return 1
esac
}
build_zpool_command(){
local pool_name="$1"
local raid_type="$2"
shift 2
local vdevs=("$@")
if [[ -z $pool_name ]];then
log "ERROR: Pool name not provided"
return 1
fi
if [[ ${#vdevs[@]} -eq 0 ]];then
log "ERROR: No vdevs provided to build_zpool_command"
return 1
fi
local cmd="zpool create -f $pool_name"
case "$raid_type" in
single)cmd+=" ${vdevs[0]}"
;;
raid0)cmd+=" ${vdevs[*]}"
;;
raid1)cmd+=" mirror ${vdevs[*]}"
;;
raidz1)cmd+=" raidz ${vdevs[*]}"
;;
raidz2)cmd+=" raidz2 ${vdevs[*]}"
;;
raidz3)cmd+=" raidz3 ${vdevs[*]}"
;;
raid10)local vdev_count=${#vdevs[@]}
for ((i=0; i<vdev_count; i+=2));do
cmd+=" mirror ${vdevs[$i]} ${vdevs[$((i+1))]}"
done
;;
*)log "ERROR: Unknown RAID type: $raid_type"
return 1
esac
echo "$cmd"
}
map_raid_to_toml(){
local raid="$1"
case "$raid" in
single)echo "raid0";;
raid0)echo "raid0";;
raid1)echo "raid1";;
raidz1)echo "raidz-1";;
raidz2)echo "raidz-2";;
raidz3)echo "raidz-3";;
raid5)echo "raidz-1";;
raid10)echo "raid10";;
*)log "WARNING: Unknown RAID type '$raid', defaulting to raid0"
echo "raid0"
esac
}
show_validation_error(){
local message="$1"
_wiz_hide_cursor
_wiz_error "$message"
sleep 3
}
install_base_packages(){
local packages="$SYSTEM_UTILITIES $OPTIONAL_PACKAGES locales chrony unattended-upgrades apt-listchanges linux-cpupower"
if [[ ${SHELL_TYPE:-bash} == "zsh" ]];then
packages="$packages zsh git curl"
fi
log "Installing base packages: $packages"
run_remote "Installing system packages" "
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get dist-upgrade -yqq
    apt-get install -yqq $packages
    apt-get autoremove -yqq
    apt-get clean
    set +e
    pveupgrade 2>/dev/null || true
    pveam update 2>/dev/null || true
  " "System packages installed"
}
batch_install_packages(){
local packages=()
[[ $INSTALL_FIREWALL == "yes" ]]&&packages+=(nftables)
if [[ $INSTALL_FIREWALL == "yes" && ${FIREWALL_MODE:-standard} != "stealth" ]];then
packages+=(fail2ban)
fi
[[ $INSTALL_APPARMOR == "yes" ]]&&packages+=(apparmor apparmor-utils)
[[ $INSTALL_AUDITD == "yes" ]]&&packages+=(auditd audispd-plugins)
[[ $INSTALL_AIDE == "yes" ]]&&packages+=(aide aide-common)
[[ $INSTALL_CHKROOTKIT == "yes" ]]&&packages+=(chkrootkit)
[[ $INSTALL_LYNIS == "yes" ]]&&packages+=(lynis)
[[ $INSTALL_NEEDRESTART == "yes" ]]&&packages+=(needrestart)
[[ $INSTALL_VNSTAT == "yes" ]]&&packages+=(vnstat)
[[ $INSTALL_PROMETHEUS == "yes" ]]&&packages+=(prometheus-node-exporter)
[[ $INSTALL_NETDATA == "yes" ]]&&packages+=(netdata)
[[ $INSTALL_NVIM == "yes" ]]&&packages+=(neovim)
[[ $INSTALL_RINGBUFFER == "yes" ]]&&packages+=(ethtool)
[[ $INSTALL_YAZI == "yes" ]]&&packages+=(curl file unzip)
[[ $INSTALL_TAILSCALE == "yes" ]]&&packages+=(tailscale)
[[ ${SSL_TYPE:-self-signed} == "letsencrypt" ]]&&packages+=(certbot)
if [[ ${#packages[@]} -eq 0 ]];then
log "No optional packages to install"
return 0
fi
log "Batch installing packages: ${packages[*]}"
local repo_setup=""
if [[ $INSTALL_TAILSCALE == "yes" ]];then
repo_setup+='
      curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
      curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
    '
fi
if [[ $INSTALL_NETDATA == "yes" ]];then
repo_setup+='
      curl -fsSL https://repo.netdata.cloud/netdatabot.gpg.key | gpg --dearmor -o /usr/share/keyrings/netdata-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/netdata-archive-keyring.gpg] https://repo.netdata.cloud/repos/stable/debian/ bookworm/" > /etc/apt/sources.list.d/netdata.list
    '
fi
(remote_exec '
      set -e
      export DEBIAN_FRONTEND=noninteractive
      '"$repo_setup"'
      apt-get update -qq
      apt-get install -yqq '"${packages[*]}"'
    '||exit 1) > \
/dev/null 2>&1&
show_progress $! "Installing packages (${#packages[@]})" "Packages installed"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Batch package installation failed"
return 1
fi
return 0
}
run_parallel_group(){
local group_name="$1"
local done_msg="$2"
shift 2
local funcs=("$@")
if [[ ${#funcs[@]} -eq 0 ]];then
log "No functions to run in parallel group: $group_name"
return 0
fi
log "Running parallel group '$group_name' with functions: ${funcs[*]}"
local result_dir
result_dir=$(mktemp -d)
trap "rm -rf '$result_dir'" RETURN
local i=0
for func in "${funcs[@]}";do
(if
"$func" 2>&1
then
touch "$result_dir/success_$i"
else
touch "$result_dir/fail_$i"
fi) > \
/dev/null&
((i++))
done
local count=$i
(while
true
do
local done_count=0
for j in $(seq 0 $((count-1)));do
[[ -f "$result_dir/success_$j" || -f "$result_dir/fail_$j" ]]&&((done_count++))
done
[[ $done_count -eq $count ]]&&break
sleep 0.2
done) \
&
show_progress $! "$group_name" "$done_msg"
local failures=0
for j in $(seq 0 $((count-1)));do
[[ -f "$result_dir/fail_$j" ]]&&((failures++))
done
if [[ $failures -gt 0 ]];then
log "WARNING: $failures/$count functions failed in group '$group_name'"
return 0
fi
return 0
}
validate_hostname(){
local hostname="$1"
[[ $hostname =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}
validate_fqdn(){
local fqdn="$1"
[[ $fqdn =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]
}
validate_email(){
local email="$1"
[[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}
is_ascii_printable(){
LC_ALL=C bash -c '[[ "$1" =~ ^[[:print:]]+$ ]]' _ "$1"
}
get_password_error(){
local password="$1"
if [[ -z $password ]];then
echo "Password cannot be empty!"
elif [[ ${#password} -lt 8 ]];then
echo "Password must be at least 8 characters long."
elif ! is_ascii_printable "$password";then
echo "Password contains invalid characters (Cyrillic or non-ASCII). Only Latin letters, digits, and special characters are allowed."
fi
}
validate_subnet(){
local subnet="$1"
if [[ ! $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]];then
return 1
fi
local ip="${subnet%/*}"
local octet1 octet2 octet3 octet4 temp
octet1="${ip%%.*}"
temp="${ip#*.}"
octet2="${temp%%.*}"
temp="${temp#*.}"
octet3="${temp%%.*}"
octet4="${temp#*.}"
[[ $octet1 -le 255 && $octet2 -le 255 && $octet3 -le 255 && $octet4 -le 255 ]]
}
validate_ipv6(){
local ipv6="$1"
[[ -z $ipv6 ]]&&return 1
ipv6="${ipv6%%\%*}"
[[ ! $ipv6 =~ ^[0-9a-fA-F:]+$ ]]&&return 1
[[ $ipv6 =~ ^:[^:] ]]&&return 1
[[ $ipv6 =~ [^:]:$ ]]&&return 1
local double_colon_count
double_colon_count=$(grep -o '::' <<<"$ipv6"|wc -l)
[[ $double_colon_count -gt 1 ]]&&return 1
local groups
if [[ $ipv6 == *"::"* ]];then
local left="${ipv6%%::*}"
local right="${ipv6##*::}"
local left_count=0 right_count=0
[[ -n $left ]]&&left_count=$(tr ':' '\n' <<<"$left"|grep -c .)
[[ -n $right ]]&&right_count=$(tr ':' '\n' <<<"$right"|grep -c .)
groups=$((left_count+right_count))
[[ $groups -ge 8 ]]&&return 1
else
groups=$(tr ':' '\n' <<<"$ipv6"|grep -c .)
[[ $groups -ne 8 ]]&&return 1
fi
local group
for group in $(tr ':' ' ' <<<"$ipv6");do
[[ -z $group ]]&&continue
[[ ${#group} -gt 4 ]]&&return 1
[[ ! $group =~ ^[0-9a-fA-F]+$ ]]&&return 1
done
return 0
}
validate_ipv6_cidr(){
local ipv6_cidr="$1"
[[ ! $ipv6_cidr =~ ^.+/[0-9]+$ ]]&&return 1
local ipv6="${ipv6_cidr%/*}"
local prefix="${ipv6_cidr##*/}"
[[ ! $prefix =~ ^[0-9]+$ ]]&&return 1
[[ $prefix -lt 0 || $prefix -gt 128 ]]&&return 1
validate_ipv6 "$ipv6"
}
validate_ipv6_gateway(){
local gateway="$1"
[[ -z $gateway ]]&&return 0
[[ $gateway == "auto" ]]&&return 0
validate_ipv6 "$gateway"
}
validate_dns_resolution(){
local fqdn="$1"
local expected_ip="$2"
local resolved_ip=""
local dns_timeout="${DNS_LOOKUP_TIMEOUT:-5}"
local retry_delay="${DNS_RETRY_DELAY:-10}"
local max_attempts=3
local dns_tool=""
if command -v dig &>/dev/null;then
dns_tool="dig"
elif command -v host &>/dev/null;then
dns_tool="host"
elif command -v nslookup &>/dev/null;then
dns_tool="nslookup"
fi
if [[ -z $dns_tool ]];then
log "WARNING: No DNS lookup tool available (dig, host, or nslookup)"
DNS_RESOLVED_IP=""
return 1
fi
for attempt in $(seq 1 "$max_attempts");do
resolved_ip=""
for dns_server in "${DNS_SERVERS[@]}";do
case "$dns_tool" in
dig)resolved_ip=$(timeout "$dns_timeout" dig +short +time=3 +tries=1 A "$fqdn" "@$dns_server" 2>/dev/null|grep -E '^[0-9]+\.'|head -1)
;;
host)resolved_ip=$(timeout "$dns_timeout" host -W 3 -t A "$fqdn" "$dns_server" 2>/dev/null|grep "has address"|head -1|awk '{print $NF}')
;;
nslookup)resolved_ip=$(timeout "$dns_timeout" nslookup -timeout=3 "$fqdn" "$dns_server" 2>/dev/null|awk '/^Address: / {print $2}'|head -1)
esac
if [[ -n $resolved_ip ]];then
break
fi
done
if [[ -z $resolved_ip ]];then
case "$dns_tool" in
dig)resolved_ip=$(timeout "$dns_timeout" dig +short +time=3 +tries=1 A "$fqdn" 2>/dev/null|grep -E '^[0-9]+\.'|head -1)
;;
*)if
command -v getent &>/dev/null
then
resolved_ip=$(timeout "$dns_timeout" getent ahosts "$fqdn" 2>/dev/null|grep STREAM|head -1|awk '{print $1}')
fi
esac
fi
if [[ -n $resolved_ip ]];then
DNS_RESOLVED_IP="$resolved_ip"
if [[ $resolved_ip == "$expected_ip" ]];then
return 0
else
return 2
fi
fi
if [[ $attempt -lt $max_attempts ]];then
log "WARN: DNS lookup for $fqdn failed (attempt $attempt/$max_attempts), retrying in ${retry_delay}s..."
sleep "$retry_delay"
fi
done
log "ERROR: Failed to resolve $fqdn after $max_attempts attempts"
DNS_RESOLVED_IP=""
return 1
}
validate_ssh_key_secure(){
local key="$1"
if ! echo "$key"|ssh-keygen -l -f - >/dev/null 2>&1;then
log "ERROR: Invalid SSH public key format"
return 1
fi
local key_type
key_type=$(echo "$key"|awk '{print $1}')
case "$key_type" in
ssh-ed25519)log "INFO: SSH key validated (ED25519)"
return 0
;;
ssh-rsa|ecdsa-*)local bits
bits=$(echo "$key"|ssh-keygen -l -f - 2>/dev/null|awk '{print $1}')
if [[ $bits -ge 2048 ]];then
log "INFO: SSH key validated ($key_type, $bits bits)"
return 0
fi
log "ERROR: RSA/ECDSA key must be >= 2048 bits (current: $bits)"
return 1
;;
*)log "ERROR: Unsupported key type: $key_type"
return 1
esac
}
validate_disk_space(){
local path="${1:-/root}"
local min_required_mb="${2:-$MIN_DISK_SPACE_MB}"
local available_mb
available_mb=$(df -m "$path" 2>/dev/null|awk 'NR==2 {print $4}')
if [[ -z $available_mb ]];then
log "ERROR: Could not determine disk space for $path"
return 1
fi
DISK_SPACE_MB=$available_mb
if [[ $available_mb -lt $min_required_mb ]];then
log "ERROR: Insufficient disk space: ${available_mb}MB available, ${min_required_mb}MB required"
return 1
fi
log "INFO: Disk space OK: ${available_mb}MB available (${min_required_mb}MB required)"
return 0
}
validate_tailscale_key(){
local key="$1"
[[ -z $key ]]&&return 1
if [[ $key =~ ^tskey-(auth|client)-[a-zA-Z0-9]+-[a-zA-Z0-9]+$ ]];then
return 0
fi
return 1
}
collect_system_info(){
local errors=0
local -A required_commands=(
[column]="bsdmainutils"
[ip]="iproute2"
[udevadm]="udev"
[timeout]="coreutils"
[curl]="curl"
[jq]="jq"
[aria2c]="aria2"
[findmnt]="util-linux"
[gum]="gum")
local packages_to_install=""
local need_charm_repo=false
for cmd in "${!required_commands[@]}";do
if ! command -v "$cmd" &>/dev/null;then
packages_to_install+=" ${required_commands[$cmd]}"
[[ $cmd == "gum" ]]&&need_charm_repo=true
fi
done
if [[ $need_charm_repo == true ]];then
mkdir -p /etc/apt/keyrings 2>/dev/null
curl -fsSL https://repo.charm.sh/apt/gpg.key 2>/dev/null|gpg --dearmor -o /etc/apt/keyrings/charm.gpg >/dev/null 2>&1
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" >/etc/apt/sources.list.d/charm.list 2>/dev/null
fi
if [[ -n $packages_to_install ]];then
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -qq -y $packages_to_install >/dev/null 2>&1
fi
if [[ $EUID -ne 0 ]];then
PREFLIGHT_ROOT="✗ Not root"
PREFLIGHT_ROOT_STATUS="error"
errors=$((errors+1))
else
PREFLIGHT_ROOT="Running as root"
PREFLIGHT_ROOT_STATUS="ok"
fi
if ping -c 1 -W 3 "$DNS_PRIMARY" >/dev/null 2>&1;then
PREFLIGHT_NET="Available"
PREFLIGHT_NET_STATUS="ok"
else
PREFLIGHT_NET="No connection"
PREFLIGHT_NET_STATUS="error"
errors=$((errors+1))
fi
if validate_disk_space "/root" "$MIN_DISK_SPACE_MB";then
PREFLIGHT_DISK="$DISK_SPACE_MB MB"
PREFLIGHT_DISK_STATUS="ok"
else
PREFLIGHT_DISK="${DISK_SPACE_MB:-0} MB (need ${MIN_DISK_SPACE_MB}MB+)"
PREFLIGHT_DISK_STATUS="error"
errors=$((errors+1))
fi
local total_ram_mb
total_ram_mb=$(free -m|awk '/^Mem:/{print $2}')
if [[ $total_ram_mb -ge $MIN_RAM_MB ]];then
PREFLIGHT_RAM="$total_ram_mb MB"
PREFLIGHT_RAM_STATUS="ok"
else
PREFLIGHT_RAM="$total_ram_mb MB (need ${MIN_RAM_MB}MB+)"
PREFLIGHT_RAM_STATUS="error"
errors=$((errors+1))
fi
local cpu_cores
cpu_cores=$(nproc)
if [[ $cpu_cores -ge 2 ]];then
PREFLIGHT_CPU="$cpu_cores cores"
PREFLIGHT_CPU_STATUS="ok"
else
PREFLIGHT_CPU="$cpu_cores core(s)"
PREFLIGHT_CPU_STATUS="warn"
fi
if [[ ! -e /dev/kvm ]];then
modprobe kvm 2>/dev/null||true
if grep -q "Intel" /proc/cpuinfo 2>/dev/null;then
modprobe kvm_intel 2>/dev/null||true
elif grep -q "AMD" /proc/cpuinfo 2>/dev/null;then
modprobe kvm_amd 2>/dev/null||true
else
modprobe kvm_intel 2>/dev/null||modprobe kvm_amd 2>/dev/null||true
fi
sleep 0.5
fi
if [[ -e /dev/kvm ]];then
PREFLIGHT_KVM="Available"
PREFLIGHT_KVM_STATUS="ok"
else
PREFLIGHT_KVM="Not available"
PREFLIGHT_KVM_STATUS="error"
errors=$((errors+1))
fi
PREFLIGHT_ERRORS=$errors
if command -v ip &>/dev/null&&command -v jq &>/dev/null;then
CURRENT_INTERFACE=$(ip -j route 2>/dev/null|jq -r '.[] | select(.dst == "default") | .dev'|head -n1)
elif command -v ip &>/dev/null;then
CURRENT_INTERFACE=$(ip route|grep default|awk '{print $5}'|head -n1)
elif command -v route &>/dev/null;then
CURRENT_INTERFACE=$(route -n|awk '/^0\.0\.0\.0/ {print $8}'|head -n1)
fi
if [[ -z $CURRENT_INTERFACE ]];then
if command -v ip &>/dev/null&&command -v jq &>/dev/null;then
CURRENT_INTERFACE=$(ip -j link show 2>/dev/null|jq -r '.[] | select(.ifname != "lo" and .operstate == "UP") | .ifname'|head -n1)
elif command -v ip &>/dev/null;then
CURRENT_INTERFACE=$(ip link show|awk -F': ' '/^[0-9]+:/ && !/lo:/ {print $2; exit}')
elif command -v ifconfig &>/dev/null;then
CURRENT_INTERFACE=$(ifconfig -a|awk '/^[a-z]/ && !/^lo/ {print $1; exit}'|tr -d ':')
fi
fi
if [[ -z $CURRENT_INTERFACE ]];then
CURRENT_INTERFACE="eth0"
log "WARNING: Could not detect network interface, defaulting to eth0"
fi
PREDICTABLE_NAME=""
if [[ -e "/sys/class/net/$CURRENT_INTERFACE" ]];then
local udev_info
udev_info=$(udevadm info "/sys/class/net/$CURRENT_INTERFACE" 2>/dev/null)
PREDICTABLE_NAME=$(echo "$udev_info"|grep "ID_NET_NAME_PATH="|cut -d'=' -f2)
if [[ -z $PREDICTABLE_NAME ]];then
PREDICTABLE_NAME=$(echo "$udev_info"|grep "ID_NET_NAME_ONBOARD="|cut -d'=' -f2)
fi
if [[ -z $PREDICTABLE_NAME ]];then
PREDICTABLE_NAME=$(ip -d link show "$CURRENT_INTERFACE" 2>/dev/null|grep "altname"|awk '{print $2}'|head -1)
fi
fi
if [[ -n $PREDICTABLE_NAME ]];then
DEFAULT_INTERFACE="$PREDICTABLE_NAME"
else
DEFAULT_INTERFACE="$CURRENT_INTERFACE"
fi
AVAILABLE_ALTNAMES=$(ip -d link show|grep -v "lo:"|grep -E '(^[0-9]+:|altname)'|awk '/^[0-9]+:/ {interface=$2; gsub(/:/, "", interface); printf "%s", interface} /altname/ {printf ", %s", $2} END {print ""}'|sed 's/, $//')
if command -v ip &>/dev/null&&command -v jq &>/dev/null;then
AVAILABLE_INTERFACES=$(ip -j link show 2>/dev/null|jq -r '.[] | select(.ifname != "lo") | .ifname'|sort)
elif command -v ip &>/dev/null;then
AVAILABLE_INTERFACES=$(ip link show|awk -F': ' '/^[0-9]+:/ && !/lo:/ {print $2}'|sort)
else
AVAILABLE_INTERFACES="$CURRENT_INTERFACE"
fi
INTERFACE_COUNT=$(echo "$AVAILABLE_INTERFACES"|wc -l)
if [[ -z $INTERFACE_NAME ]];then
INTERFACE_NAME="$DEFAULT_INTERFACE"
fi
local max_attempts=3
local attempt=0
while [[ $attempt -lt $max_attempts ]];do
attempt=$((attempt+1))
if command -v ip &>/dev/null&&command -v jq &>/dev/null;then
MAIN_IPV4_CIDR=$(ip -j address show "$CURRENT_INTERFACE" 2>/dev/null|jq -r '.[0].addr_info[] | select(.family == "inet" and .scope == "global") | "\(.local)/\(.prefixlen)"'|head -n1)
MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
MAIN_IPV4_GW=$(ip -j route 2>/dev/null|jq -r '.[] | select(.dst == "default") | .gateway'|head -n1)
[[ -n $MAIN_IPV4 ]]&&[[ -n $MAIN_IPV4_GW ]]&&break
elif command -v ip &>/dev/null;then
MAIN_IPV4_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null|grep global|grep "inet "|awk '{print $2}'|head -n1)
MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
MAIN_IPV4_GW=$(ip route 2>/dev/null|grep default|awk '{print $3}'|head -n1)
[[ -n $MAIN_IPV4 ]]&&[[ -n $MAIN_IPV4_GW ]]&&break
elif command -v ifconfig &>/dev/null;then
MAIN_IPV4=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null|awk '/inet / {print $2}'|sed 's/addr://')
local netmask
netmask=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null|awk '/inet / {print $4}'|sed 's/Mask://')
if [[ -n $MAIN_IPV4 ]]&&[[ -n $netmask ]];then
case "$netmask" in
255.255.255.0)MAIN_IPV4_CIDR="$MAIN_IPV4/24";;
255.255.255.128)MAIN_IPV4_CIDR="$MAIN_IPV4/25";;
255.255.255.192)MAIN_IPV4_CIDR="$MAIN_IPV4/26";;
255.255.255.224)MAIN_IPV4_CIDR="$MAIN_IPV4/27";;
255.255.255.240)MAIN_IPV4_CIDR="$MAIN_IPV4/28";;
255.255.255.248)MAIN_IPV4_CIDR="$MAIN_IPV4/29";;
255.255.255.252)MAIN_IPV4_CIDR="$MAIN_IPV4/30";;
255.255.0.0)MAIN_IPV4_CIDR="$MAIN_IPV4/16";;
*)MAIN_IPV4_CIDR="$MAIN_IPV4/24"
esac
fi
if command -v route &>/dev/null;then
MAIN_IPV4_GW=$(route -n 2>/dev/null|awk '/^0\.0\.0\.0/ {print $2}'|head -n1)
fi
[[ -n $MAIN_IPV4 ]]&&[[ -n $MAIN_IPV4_GW ]]&&break
fi
if [[ $attempt -lt $max_attempts ]];then
log "Network info attempt $attempt failed, retrying in 2 seconds..."
sleep 2
fi
done
if command -v ip &>/dev/null&&command -v jq &>/dev/null;then
MAC_ADDRESS=$(ip -j link show "$CURRENT_INTERFACE" 2>/dev/null|jq -r '.[0].address // empty')
IPV6_CIDR=$(ip -j address show "$CURRENT_INTERFACE" 2>/dev/null|jq -r '.[0].addr_info[] | select(.family == "inet6" and .scope == "global") | "\(.local)/\(.prefixlen)"'|head -n1)
elif command -v ip &>/dev/null;then
MAC_ADDRESS=$(ip link show "$CURRENT_INTERFACE" 2>/dev/null|awk '/ether/ {print $2}')
IPV6_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null|grep global|grep "inet6 "|awk '{print $2}'|head -n1)
elif command -v ifconfig &>/dev/null;then
MAC_ADDRESS=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null|awk '/ether/ {print $2}')
IPV6_CIDR=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null|awk '/inet6/ && /global/ {print $2}')
fi
MAIN_IPV6="${IPV6_CIDR%/*}"
if [[ -n $IPV6_CIDR ]];then
local ipv6_prefix="${MAIN_IPV6%%:*:*:*:*}"
if [[ $ipv6_prefix == "$MAIN_IPV6" ]]||[[ -z $ipv6_prefix ]];then
ipv6_prefix=$(printf '%s' "$MAIN_IPV6"|cut -d':' -f1-4)
fi
FIRST_IPV6_CIDR="$ipv6_prefix:1::1/80"
else
FIRST_IPV6_CIDR=""
fi
if [[ -n $MAIN_IPV6 ]];then
if command -v ip &>/dev/null;then
IPV6_GATEWAY=$(ip -6 route 2>/dev/null|grep default|awk '{print $3}'|head -n1)
fi
fi
_load_wizard_data
}
_load_timezones(){
if command -v timedatectl &>/dev/null;then
WIZ_TIMEZONES=$(timedatectl list-timezones 2>/dev/null)
else
WIZ_TIMEZONES=$(find /usr/share/zoneinfo -type f 2>/dev/null|sed 's|/usr/share/zoneinfo/||'|grep -E '^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/'|sort)
fi
WIZ_TIMEZONES+=$'\nUTC'
}
_load_countries(){
local iso_file="/usr/share/iso-codes/json/iso_3166-1.json"
if [[ -f $iso_file ]];then
WIZ_COUNTRIES=$(grep -oP '"alpha_2":\s*"\K[^"]+' "$iso_file"|tr '[:upper:]' '[:lower:]'|sort)
else
WIZ_COUNTRIES=$(locale -a 2>/dev/null|grep -oP '^[a-z]{2}(?=_)'|sort -u)
fi
}
_build_tz_to_country(){
declare -gA TZ_TO_COUNTRY
local zone_tab="/usr/share/zoneinfo/zone.tab"
[[ -f $zone_tab ]]||return 0
while IFS=$'\t' read -r country _ tz _;do
[[ $country == \#* ]]&&continue
[[ -z $tz ]]&&continue
TZ_TO_COUNTRY["$tz"]="${country,,}"
done <"$zone_tab"
}
_load_wizard_data(){
_load_timezones
_load_countries
_build_tz_to_country
}
detect_drives(){
mapfile -t DRIVES < <(lsblk -d -n -o NAME,TYPE|grep nvme|grep disk|awk '{print "/dev/"$1}'|sort)
DRIVE_COUNT=${#DRIVES[@]}
if [[ $DRIVE_COUNT -eq 0 ]];then
mapfile -t DRIVES < <(lsblk -d -n -o NAME,TYPE|grep disk|grep -v loop|awk '{print "/dev/"$1}'|sort)
DRIVE_COUNT=${#DRIVES[@]}
fi
DRIVE_NAMES=()
DRIVE_SIZES=()
DRIVE_MODELS=()
for drive in "${DRIVES[@]}";do
local name size model
name=$(basename "$drive")
size=$(lsblk -d -n -o SIZE "$drive"|xargs)
model=$(lsblk -d -n -o MODEL "$drive" 2>/dev/null|xargs||echo "Disk")
DRIVE_NAMES+=("$name")
DRIVE_SIZES+=("$size")
DRIVE_MODELS+=("$model")
done
}
detect_disk_roles(){
[[ $DRIVE_COUNT -eq 0 ]]&&return 1
local size_bytes=()
for size in "${DRIVE_SIZES[@]}";do
local bytes
if [[ $size =~ ([0-9.]+)T ]];then
bytes=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * 1099511627776}")
elif [[ $size =~ ([0-9.]+)G ]];then
bytes=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * 1073741824}")
else
bytes=0
fi
size_bytes+=("$bytes")
done
local min_size=${size_bytes[0]}
local max_size=${size_bytes[0]}
for size in "${size_bytes[@]}";do
[[ $size -lt $min_size ]]&&min_size=$size
[[ $size -gt $max_size ]]&&max_size=$size
done
local size_diff=$((max_size-min_size))
local threshold=$((min_size/10))
if [[ $size_diff -le $threshold ]];then
log "All disks same size, using all for ZFS pool"
BOOT_DISK=""
ZFS_POOL_DISKS=("${DRIVES[@]}")
else
log "Mixed disk sizes, using smallest for boot"
local smallest_idx=0
for i in "${!size_bytes[@]}";do
[[ ${size_bytes[$i]} -lt ${size_bytes[$smallest_idx]} ]]&&smallest_idx=$i
done
BOOT_DISK="${DRIVES[$smallest_idx]}"
ZFS_POOL_DISKS=()
for i in "${!DRIVES[@]}";do
[[ $i -ne $smallest_idx ]]&&ZFS_POOL_DISKS+=("${DRIVES[$i]}")
done
fi
log "Boot disk: ${BOOT_DISK:-all in pool}"
log "Pool disks: ${ZFS_POOL_DISKS[*]}"
}
show_system_status(){
detect_drives
detect_disk_roles
local no_drives=0
if [[ $DRIVE_COUNT -eq 0 ]];then
no_drives=1
fi
local table_data
table_data=",,
Status,Item,Value
"
format_status(){
local status="$1"
case "$status" in
ok)gum style --foreground "$HEX_CYAN" "[OK]";;
warn)gum style --foreground "$HEX_YELLOW" "[WARN]";;
error)gum style --foreground "$HEX_RED" "[ERROR]"
esac
}
add_row(){
local status="$1"
local label="$2"
local value="$3"
local status_text
status_text=$(format_status "$status")
table_data+="$status_text,$label,$value
"
}
add_row "ok" "Installer" "v$VERSION"
add_row "$PREFLIGHT_ROOT_STATUS" "Root Access" "$PREFLIGHT_ROOT"
add_row "$PREFLIGHT_NET_STATUS" "Internet" "$PREFLIGHT_NET"
add_row "$PREFLIGHT_DISK_STATUS" "Temp Space" "$PREFLIGHT_DISK"
add_row "$PREFLIGHT_RAM_STATUS" "RAM" "$PREFLIGHT_RAM"
add_row "$PREFLIGHT_CPU_STATUS" "CPU" "$PREFLIGHT_CPU"
add_row "$PREFLIGHT_KVM_STATUS" "KVM" "$PREFLIGHT_KVM"
if [[ $no_drives -eq 1 ]];then
local error_status
error_status=$(format_status "error")
table_data+="$error_status,No drives detected!,
"
else
for i in "${!DRIVE_NAMES[@]}";do
local ok_status
ok_status=$(format_status "ok")
table_data+="$ok_status,${DRIVE_NAMES[$i]},${DRIVE_SIZES[$i]}  ${DRIVE_MODELS[$i]:0:25}
"
done
fi
table_data="${table_data%$'\n'}"
echo "$table_data"|gum table \
--print \
--border "none" \
--cell.foreground "$HEX_GRAY" \
--header.foreground "$HEX_ORANGE"
echo ""
local has_errors=false
if [[ $PREFLIGHT_ERRORS -gt 0 || $no_drives -eq 1 ]];then
has_errors=true
fi
if [[ $has_errors == true ]];then
print_error "System requirements not met. Please fix the issues above."
echo ""
gum confirm "Exit installer?" \
--affirmative "Exit" \
--negative "" \
--default=true \
--prompt.foreground "#ff8700" \
--selected.background "#ff8700" \
--unselected.foreground "#585858"||true
log "ERROR: Pre-flight checks failed"
exit 1
else
if ! gum confirm "Start configuration?" \
--affirmative "Start" \
--negative "Cancel" \
--default=true \
--prompt.foreground "#ff8700" \
--selected.background "#ff8700" \
--unselected.foreground "#585858";then
log "INFO: User cancelled installation"
print_info "Installation cancelled by user"
exit 0
fi
_wiz_start_edit
fi
}
get_terminal_dimensions(){
TERM_HEIGHT=$(tput lines)
TERM_WIDTH=$(tput cols)
}
LOGO_HEIGHT=${BANNER_HEIGHT:-9}
HEADER_HEIGHT=2
calculate_log_area(){
get_terminal_dimensions
LOG_AREA_HEIGHT=$((TERM_HEIGHT-LOGO_HEIGHT-HEADER_HEIGHT-1))
}
declare -a LOG_LINES=()
LOG_COUNT=0
save_cursor_position(){
printf '\033[s'
}
restore_cursor_position(){
printf '\033[u'
printf '\033[J'
}
add_log(){
local message="$1"
LOG_LINES+=("$message")
((LOG_COUNT++))
render_logs
}
render_logs(){
restore_cursor_position
print_section " Installation Progress"
_wiz_blank_line
local start_line=0
if ((LOG_COUNT>LOG_AREA_HEIGHT));then
start_line=$((LOG_COUNT-LOG_AREA_HEIGHT))
fi
for ((i=start_line; i<LOG_COUNT; i++));do
echo "${LOG_LINES[$i]}"
done
}
start_task(){
local message="$1"
add_log "$message..."
TASK_INDEX=$((LOG_COUNT-1))
}
complete_task(){
local task_index="$1"
local message="$2"
LOG_LINES[task_index]="$message $CLR_CYAN✓$CLR_RESET"
render_logs
}
add_subtask_log(){
local message="$1"
add_log "$CLR_GRAY│$CLR_RESET   $CLR_GRAY$message$CLR_RESET"
}
start_live_installation(){
if ! command -v gum &>/dev/null;then
log "WARNING: gum is not installed, live logs disabled"
return 1
fi
LIVE_LOGS_ACTIVE=true
if type show_progress &>/dev/null;then
source <(declare -f show_progress|sed '1s/show_progress/show_progress_original/')
fi
show_progress(){
live_show_progress "$@"
}
export -f show_progress 2>/dev/null||true
calculate_log_area
tput smcup
tput civis
_wiz_clear
show_banner
save_cursor_position
render_logs
trap 'tput cnorm; tput rmcup' EXIT RETURN
}
finish_live_installation(){
LIVE_LOGS_ACTIVE=false
if type show_progress_original &>/dev/null 2>&1;then
show_progress(){
show_progress_original "$@"
}
fi
tput cnorm
tput rmcup
}
LIVE_LOGS_ACTIVE=false
live_show_progress(){
local pid=$1
local message="${2:-Processing}"
local done_message="${3:-$message}"
local silent=false
[[ ${3:-} == "--silent" || ${4:-} == "--silent" ]]&&silent=true
[[ ${3:-} == "--silent" ]]&&done_message="$message"
start_task "$CLR_GRAY├─$CLR_RESET $message"
local task_idx=$TASK_INDEX
while kill -0 "$pid" 2>/dev/null;do
sleep 0.3
local dots_count=$((($(date +%s)%3)+1))
local dots
dots=$(printf '.%.0s' $(seq 1 $dots_count))
LOG_LINES[task_idx]="$CLR_GRAY├─$CLR_RESET $message$CLR_ORANGE$dots$CLR_RESET"
render_logs
done
wait "$pid" 2>/dev/null
local exit_code=$?
if [[ $exit_code -eq 0 ]];then
if [[ $silent != true ]];then
complete_task "$task_idx" "$CLR_GRAY├─$CLR_RESET $done_message"
else
unset 'LOG_LINES[task_idx]'
LOG_LINES=("${LOG_LINES[@]}")
((LOG_COUNT--))
render_logs
fi
else
LOG_LINES[task_idx]="$CLR_GRAY├─$CLR_RESET $message $CLR_RED✗$CLR_RESET"
render_logs
fi
return $exit_code
}
live_log_subtask(){
local message="$1"
add_subtask_log "$message"
}
_wizard_main(){
local selection=0
while true;do
_wiz_render_menu "$selection"
_wiz_read_key
case "$WIZ_KEY" in
up)if
[[ $selection -gt 0 ]]
then
((selection--))
fi
;;
down)if
[[ $selection -lt $((_WIZ_FIELD_COUNT-1)) ]]
then
((selection++))
fi
;;
left)if
[[ $WIZ_CURRENT_SCREEN -gt 0 ]]
then
((WIZ_CURRENT_SCREEN--))
selection=0
fi
;;
right)if
[[ $WIZ_CURRENT_SCREEN -lt $((${#WIZ_SCREENS[@]}-1)) ]]
then
((WIZ_CURRENT_SCREEN++))
selection=0
fi
;;
enter)_wiz_show_cursor
local field_name="${_WIZ_FIELD_MAP[$selection]}"
case "$field_name" in
hostname)_edit_hostname;;
email)_edit_email;;
password)_edit_password;;
timezone)_edit_timezone;;
keyboard)_edit_keyboard;;
country)_edit_country;;
iso_version)_edit_iso_version;;
repository)_edit_repository;;
interface)_edit_interface;;
bridge_mode)_edit_bridge_mode;;
private_subnet)_edit_private_subnet;;
bridge_mtu)_edit_bridge_mtu;;
ipv6)_edit_ipv6;;
firewall)_edit_firewall;;
boot_disk)_edit_boot_disk;;
pool_disks)_edit_pool_disks;;
zfs_mode)_edit_zfs_mode;;
zfs_arc)_edit_zfs_arc;;
tailscale)_edit_tailscale;;
ssl)_edit_ssl;;
shell)_edit_shell;;
power_profile)_edit_power_profile;;
security)_edit_features_security;;
monitoring)_edit_features_monitoring;;
tools)_edit_features_tools;;
api_token)_edit_api_token;;
ssh_key)_edit_ssh_key
esac
_wiz_hide_cursor
;;
start)return 0
;;
quit|esc)_wiz_start_edit
_wiz_show_cursor
if _wiz_confirm "Quit installation?" --default=false;then
exit 0
fi
_wiz_hide_cursor
esac
done
}
_show_input_footer(){
local type="${1:-input}"
local component_lines="${2:-1}"
local i
for ((i=0; i<component_lines; i++));do
_wiz_blank_line
done
_wiz_blank_line
case "$type" in
filter)echo -e "$CLR_GRAY[$CLR_ORANGE↑↓$CLR_GRAY] navigate  [${CLR_ORANGE}Enter$CLR_GRAY] select  [${CLR_ORANGE}Esc$CLR_GRAY] cancel$CLR_RESET"
;;
checkbox)echo -e "$CLR_GRAY[$CLR_ORANGE↑↓$CLR_GRAY] navigate  [${CLR_ORANGE}Space$CLR_GRAY] toggle  [${CLR_ORANGE}Enter$CLR_GRAY] confirm  [${CLR_ORANGE}Esc$CLR_GRAY] cancel$CLR_RESET"
;;
*)echo -e "$CLR_GRAY[${CLR_ORANGE}Enter$CLR_GRAY] confirm  [${CLR_ORANGE}Esc$CLR_GRAY] cancel$CLR_RESET"
esac
tput cuu $((component_lines+2))
}
_validate_config(){
_wiz_config_complete&&return 0
local missing_fields=()
[[ -z $PVE_HOSTNAME ]]&&missing_fields+=("Hostname")
[[ -z $DOMAIN_SUFFIX ]]&&missing_fields+=("Domain")
[[ -z $EMAIL ]]&&missing_fields+=("Email")
[[ -z $NEW_ROOT_PASSWORD ]]&&missing_fields+=("Password")
[[ -z $TIMEZONE ]]&&missing_fields+=("Timezone")
[[ -z $KEYBOARD ]]&&missing_fields+=("Keyboard")
[[ -z $COUNTRY ]]&&missing_fields+=("Country")
[[ -z $PROXMOX_ISO_VERSION ]]&&missing_fields+=("Proxmox Version")
[[ -z $PVE_REPO_TYPE ]]&&missing_fields+=("Repository")
[[ -z $INTERFACE_NAME ]]&&missing_fields+=("Network Interface")
[[ -z $BRIDGE_MODE ]]&&missing_fields+=("Bridge mode")
[[ -z $PRIVATE_SUBNET ]]&&missing_fields+=("Private subnet")
[[ -z $IPV6_MODE ]]&&missing_fields+=("IPv6")
[[ -z $ZFS_RAID ]]&&missing_fields+=("ZFS mode")
[[ -z $ZFS_ARC_MODE ]]&&missing_fields+=("ZFS ARC")
[[ -z $SHELL_TYPE ]]&&missing_fields+=("Shell")
[[ -z $CPU_GOVERNOR ]]&&missing_fields+=("Power profile")
[[ -z $SSH_PUBLIC_KEY ]]&&missing_fields+=("SSH Key")
[[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]]&&missing_fields+=("Pool disks")
[[ $INSTALL_TAILSCALE != "yes" && -z $SSL_TYPE ]]&&missing_fields+=("SSL Certificate")
[[ $FIREWALL_MODE == "stealth" && $INSTALL_TAILSCALE != "yes" ]]&&missing_fields+=("Tailscale (required for Stealth firewall)")
if [[ ${#missing_fields[@]} -gt 0 ]];then
_wiz_start_edit
_wiz_hide_cursor
_wiz_error --bold "Configuration incomplete!"
_wiz_blank_line
_wiz_warn "Please configure the following required fields:"
_wiz_blank_line
for field in "${missing_fields[@]}";do
echo "  $CLR_CYAN•$CLR_RESET $field"
done
_wiz_blank_line
_wiz_show_cursor
_wiz_confirm "Return to configuration?" --default=true||exit 1
_wiz_hide_cursor
return 1
fi
return 0
}
show_gum_config_editor(){
tput smcup
_wiz_hide_cursor
trap '_wiz_show_cursor; tput rmcup' EXIT
while true;do
_wizard_main
if _validate_config;then
break
fi
done
}
WIZ_SCREENS=("Basic" "Proxmox" "Network" "Storage" "Services" "SSH")
WIZ_CURRENT_SCREEN=0
_NAV_COL_WIDTH=10
_nav_repeat(){
local char="$1" count="$2" i
for ((i=0; i<count; i++));do
printf '%s' "$char"
done
}
_nav_color(){
local idx="$1" current="$2"
if [[ $idx -eq $current ]];then
echo "$CLR_ORANGE"
elif [[ $idx -lt $current ]];then
echo "$CLR_CYAN"
else
echo "$CLR_GRAY"
fi
}
_nav_dot(){
local idx="$1" current="$2"
if [[ $idx -eq $current ]];then
echo "◉"
elif [[ $idx -lt $current ]];then
echo "●"
else
echo "○"
fi
}
_nav_line(){
local idx="$1" current="$2" len="$3"
if [[ $idx -lt $current ]];then
_nav_repeat "━" "$len"
else
_nav_repeat "─" "$len"
fi
}
_wiz_render_nav(){
local current=$WIZ_CURRENT_SCREEN
local total=${#WIZ_SCREENS[@]}
local col=$_NAV_COL_WIDTH
local nav_width=$((col*total))
local footer_width=69
local pad_left=$(((footer_width-nav_width)/2))
local padding=""
((pad_left>0))&&padding=$(printf '%*s' $pad_left '')
local labels="$padding"
for i in "${!WIZ_SCREENS[@]}";do
local name="${WIZ_SCREENS[$i]}"
local name_len=${#name}
local pad_left=$(((col-name_len)/2))
local pad_right=$((col-name_len-pad_left))
local centered
centered=$(printf '%*s%s%*s' $pad_left '' "$name" $pad_right '')
labels+="$(_nav_color "$i" "$current")$centered$CLR_RESET"
done
local dots="$padding"
local center_pad=$(((col-1)/2))
local right_pad=$((col-center_pad-1))
for i in "${!WIZ_SCREENS[@]}";do
local color line_color dot
color=$(_nav_color "$i" "$current")
dot=$(_nav_dot "$i" "$current")
if [[ $i -eq 0 ]];then
dots+=$(printf '%*s' $center_pad '')
dots+="$color$dot$CLR_RESET"
local line_clr
line_clr=$([[ $i -lt $current ]]&&echo "$CLR_CYAN"||echo "$CLR_GRAY")
dots+="$line_clr$(_nav_line "$i" "$current" "$right_pad")$CLR_RESET"
elif [[ $i -eq $((total-1)) ]];then
local prev_line_clr
prev_line_clr=$([[ $((i-1)) -lt $current ]]&&echo "$CLR_CYAN"||echo "$CLR_GRAY")
dots+="$prev_line_clr$(_nav_line "$((i-1))" "$current" "$center_pad")$CLR_RESET"
dots+="$color$dot$CLR_RESET"
else
local prev_line_clr
prev_line_clr=$([[ $((i-1)) -lt $current ]]&&echo "$CLR_CYAN"||echo "$CLR_GRAY")
dots+="$prev_line_clr$(_nav_line "$((i-1))" "$current" "$center_pad")$CLR_RESET"
dots+="$color$dot$CLR_RESET"
local next_line_clr
next_line_clr=$([[ $i -lt $current ]]&&echo "$CLR_CYAN"||echo "$CLR_GRAY")
dots+="$next_line_clr$(_nav_line "$i" "$current" "$right_pad")$CLR_RESET"
fi
done
printf '%s\n%s\n' "$labels" "$dots"
}
_wiz_read_key(){
local key
IFS= read -rsn1 key
if [[ $key == $'\x1b' ]];then
read -rsn2 -t 0.1 key
case "$key" in
'[A')WIZ_KEY="up";;
'[B')WIZ_KEY="down";;
'[C')WIZ_KEY="right";;
'[D')WIZ_KEY="left";;
*)WIZ_KEY="esc"
esac
elif [[ $key == "" ]];then
WIZ_KEY="enter"
elif [[ $key == "q" || $key == "Q" ]];then
WIZ_KEY="quit"
elif [[ $key == "s" || $key == "S" ]];then
WIZ_KEY="start"
else
WIZ_KEY="$key"
fi
}
_wiz_hide_cursor(){ printf '\033[?25l';}
_wiz_show_cursor(){ printf '\033[?25h';}
_wiz_blank_line(){ echo "";}
_wiz_error(){ gum style --foreground "$HEX_RED" "$@";}
_wiz_warn(){ gum style --foreground "$HEX_YELLOW" "$@";}
_wiz_info(){ gum style --foreground "$HEX_CYAN" "$@";}
_wiz_dim(){ gum style --foreground "$HEX_GRAY" "$@";}
_wiz_description(){
local output=""
for line in "$@";do
line="${line//\{\{cyan:/$CLR_CYAN}"
line="${line//\}\}/$CLR_GRAY}"
output+="$CLR_GRAY$line$CLR_RESET\n"
done
printf '%b' "$output"
}
_wiz_confirm(){
gum confirm "$@" \
--prompt.foreground "$HEX_ORANGE" \
--selected.background "$HEX_ORANGE"
}
_wiz_choose(){
gum choose \
--header.foreground "$HEX_CYAN" \
--cursor "$CLR_ORANGE›$CLR_RESET " \
--cursor.foreground "$HEX_NONE" \
--selected.foreground "$HEX_WHITE" \
--no-show-help \
"$@"
}
_wiz_input(){
gum input \
--prompt.foreground "$HEX_CYAN" \
--cursor.foreground "$HEX_ORANGE" \
--no-show-help \
"$@"
}
_wiz_clear(){
printf '\033[H\033[J'
}
_wiz_start_edit(){
_wiz_clear
show_banner
_wiz_blank_line
}
_wiz_input_screen(){
_wiz_start_edit
for line in "$@";do
_wiz_dim "$line"
done
[[ $# -gt 0 ]]&&echo ""
_show_input_footer
}
_wiz_fmt(){
local value="$1"
local placeholder="${2:-→ set value}"
if [[ -n $value ]];then
echo "$value"
else
echo "$CLR_GRAY$placeholder$CLR_RESET"
fi
}
_WIZ_FIELD_COUNT=0
_WIZ_FIELD_MAP=()
_wiz_config_complete(){
[[ -z $PVE_HOSTNAME ]]&&return 1
[[ -z $DOMAIN_SUFFIX ]]&&return 1
[[ -z $EMAIL ]]&&return 1
[[ -z $NEW_ROOT_PASSWORD ]]&&return 1
[[ -z $TIMEZONE ]]&&return 1
[[ -z $KEYBOARD ]]&&return 1
[[ -z $COUNTRY ]]&&return 1
[[ -z $PROXMOX_ISO_VERSION ]]&&return 1
[[ -z $PVE_REPO_TYPE ]]&&return 1
[[ -z $INTERFACE_NAME ]]&&return 1
[[ -z $BRIDGE_MODE ]]&&return 1
[[ -z $PRIVATE_SUBNET ]]&&return 1
[[ -z $IPV6_MODE ]]&&return 1
[[ -z $ZFS_RAID ]]&&return 1
[[ -z $ZFS_ARC_MODE ]]&&return 1
[[ -z $SHELL_TYPE ]]&&return 1
[[ -z $CPU_GOVERNOR ]]&&return 1
[[ -z $SSH_PUBLIC_KEY ]]&&return 1
[[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]]&&return 1
[[ $INSTALL_TAILSCALE != "yes" && -z $SSL_TYPE ]]&&return 1
[[ $FIREWALL_MODE == "stealth" && $INSTALL_TAILSCALE != "yes" ]]&&return 1
return 0
}
_wiz_build_display_values(){
_DSP_PASS=""
[[ -n $NEW_ROOT_PASSWORD ]]&&_DSP_PASS="********"
_DSP_HOSTNAME=""
[[ -n $PVE_HOSTNAME && -n $DOMAIN_SUFFIX ]]&&_DSP_HOSTNAME="$PVE_HOSTNAME.$DOMAIN_SUFFIX"
_DSP_IPV6=""
if [[ -n $IPV6_MODE ]];then
case "$IPV6_MODE" in
auto)_DSP_IPV6="Auto"
[[ -n $MAIN_IPV6 ]]&&_DSP_IPV6+=" ($MAIN_IPV6)"
;;
manual)_DSP_IPV6="Manual"
[[ -n $MAIN_IPV6 ]]&&_DSP_IPV6+=" ($MAIN_IPV6, gw: $IPV6_GATEWAY)"
;;
disabled)_DSP_IPV6="Disabled";;
*)_DSP_IPV6="$IPV6_MODE"
esac
fi
_DSP_TAILSCALE=""
if [[ -n $INSTALL_TAILSCALE ]];then
[[ $INSTALL_TAILSCALE == "yes" ]]&&_DSP_TAILSCALE="Enabled + Stealth"||_DSP_TAILSCALE="Disabled"
fi
_DSP_SSL=""
if [[ -n $SSL_TYPE ]];then
case "$SSL_TYPE" in
self-signed)_DSP_SSL="Self-signed";;
letsencrypt)_DSP_SSL="Let's Encrypt";;
*)_DSP_SSL="$SSL_TYPE"
esac
fi
_DSP_REPO=""
if [[ -n $PVE_REPO_TYPE ]];then
case "$PVE_REPO_TYPE" in
no-subscription)_DSP_REPO="No-subscription (free)";;
enterprise)_DSP_REPO="Enterprise";;
test)_DSP_REPO="Test/Development";;
*)_DSP_REPO="$PVE_REPO_TYPE"
esac
fi
_DSP_BRIDGE=""
if [[ -n $BRIDGE_MODE ]];then
case "$BRIDGE_MODE" in
external)_DSP_BRIDGE="External bridge";;
internal)_DSP_BRIDGE="Internal NAT";;
both)_DSP_BRIDGE="Both";;
*)_DSP_BRIDGE="$BRIDGE_MODE"
esac
fi
_DSP_ZFS=""
if [[ -n $ZFS_RAID ]];then
case "$ZFS_RAID" in
single)_DSP_ZFS="Single disk";;
raid0)_DSP_ZFS="RAID-0 (striped)";;
raid1)_DSP_ZFS="RAID-1 (mirror)";;
raidz1)_DSP_ZFS="RAID-Z1 (parity)";;
raidz2)_DSP_ZFS="RAID-Z2 (double parity)";;
raid10)_DSP_ZFS="RAID-10 (striped mirrors)";;
*)_DSP_ZFS="$ZFS_RAID"
esac
fi
_DSP_ARC=""
if [[ -n $ZFS_ARC_MODE ]];then
case "$ZFS_ARC_MODE" in
vm-focused)_DSP_ARC="VM-focused (4GB)";;
balanced)_DSP_ARC="Balanced (25-40%)";;
storage-focused)_DSP_ARC="Storage-focused (50%)";;
*)_DSP_ARC="$ZFS_ARC_MODE"
esac
fi
_DSP_SHELL=""
if [[ -n $SHELL_TYPE ]];then
case "$SHELL_TYPE" in
zsh)_DSP_SHELL="ZSH";;
bash)_DSP_SHELL="Bash";;
*)_DSP_SHELL="$SHELL_TYPE"
esac
fi
_DSP_POWER=""
if [[ -n $CPU_GOVERNOR ]];then
case "$CPU_GOVERNOR" in
performance)_DSP_POWER="Performance";;
ondemand|powersave)_DSP_POWER="Balanced";;
schedutil)_DSP_POWER="Adaptive";;
conservative)_DSP_POWER="Conservative";;
*)_DSP_POWER="$CPU_GOVERNOR"
esac
fi
_DSP_SECURITY="none"
local sec_items=()
[[ $INSTALL_APPARMOR == "yes" ]]&&sec_items+=("apparmor")
[[ $INSTALL_AUDITD == "yes" ]]&&sec_items+=("auditd")
[[ $INSTALL_AIDE == "yes" ]]&&sec_items+=("aide")
[[ $INSTALL_CHKROOTKIT == "yes" ]]&&sec_items+=("chkrootkit")
[[ $INSTALL_LYNIS == "yes" ]]&&sec_items+=("lynis")
[[ $INSTALL_NEEDRESTART == "yes" ]]&&sec_items+=("needrestart")
[[ ${#sec_items[@]} -gt 0 ]]&&_DSP_SECURITY="${sec_items[*]}"
_DSP_MONITORING="none"
local mon_items=()
[[ $INSTALL_VNSTAT == "yes" ]]&&mon_items+=("vnstat")
[[ $INSTALL_NETDATA == "yes" ]]&&mon_items+=("netdata")
[[ $INSTALL_PROMETHEUS == "yes" ]]&&mon_items+=("prometheus")
[[ ${#mon_items[@]} -gt 0 ]]&&_DSP_MONITORING="${mon_items[*]}"
_DSP_TOOLS="none"
local tool_items=()
[[ $INSTALL_YAZI == "yes" ]]&&tool_items+=("yazi")
[[ $INSTALL_NVIM == "yes" ]]&&tool_items+=("nvim")
[[ $INSTALL_RINGBUFFER == "yes" ]]&&tool_items+=("ringbuffer")
[[ ${#tool_items[@]} -gt 0 ]]&&_DSP_TOOLS="${tool_items[*]}"
_DSP_API=""
if [[ -n $INSTALL_API_TOKEN ]];then
case "$INSTALL_API_TOKEN" in
yes)_DSP_API="Yes ($API_TOKEN_NAME)";;
no)_DSP_API="No"
esac
fi
_DSP_SSH=""
[[ -n $SSH_PUBLIC_KEY ]]&&_DSP_SSH="${SSH_PUBLIC_KEY:0:20}..."
_DSP_FIREWALL=""
if [[ -n $INSTALL_FIREWALL ]];then
if [[ $INSTALL_FIREWALL == "yes" ]];then
case "$FIREWALL_MODE" in
stealth)_DSP_FIREWALL="Stealth (Tailscale only)";;
strict)_DSP_FIREWALL="Strict (SSH only)";;
standard)_DSP_FIREWALL="Standard (SSH + Web UI)";;
*)_DSP_FIREWALL="$FIREWALL_MODE"
esac
else
_DSP_FIREWALL="Disabled"
fi
fi
_DSP_ISO=""
[[ -n $PROXMOX_ISO_VERSION ]]&&_DSP_ISO=$(get_iso_version "$PROXMOX_ISO_VERSION")
_DSP_MTU="${BRIDGE_MTU:-9000}"
[[ $_DSP_MTU == "9000" ]]&&_DSP_MTU="9000 (jumbo)"
_DSP_BOOT="All in pool"
if [[ -n $BOOT_DISK ]];then
for i in "${!DRIVES[@]}";do
if [[ ${DRIVES[$i]} == "$BOOT_DISK" ]];then
_DSP_BOOT="${DRIVE_MODELS[$i]}"
break
fi
done
fi
_DSP_POOL="${#ZFS_POOL_DISKS[@]} disks"
}
_wiz_render_screen_content(){
local screen="$1"
local selection="$2"
case $screen in
0)_add_field "Hostname         " "$(_wiz_fmt "$_DSP_HOSTNAME")" "hostname"
_add_field "Email            " "$(_wiz_fmt "$EMAIL")" "email"
_add_field "Password         " "$(_wiz_fmt "$_DSP_PASS")" "password"
_add_field "Timezone         " "$(_wiz_fmt "$TIMEZONE")" "timezone"
_add_field "Keyboard         " "$(_wiz_fmt "$KEYBOARD")" "keyboard"
_add_field "Country          " "$(_wiz_fmt "$COUNTRY")" "country"
;;
1)_add_field "Version          " "$(_wiz_fmt "$_DSP_ISO")" "iso_version"
_add_field "Repository       " "$(_wiz_fmt "$_DSP_REPO")" "repository"
;;
2)if
[[ ${INTERFACE_COUNT:-1} -gt 1 ]]
then
_add_field "Interface        " "$(_wiz_fmt "$INTERFACE_NAME")" "interface"
fi
_add_field "Bridge mode      " "$(_wiz_fmt "$_DSP_BRIDGE")" "bridge_mode"
if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]];then
_add_field "Private subnet   " "$(_wiz_fmt "$PRIVATE_SUBNET")" "private_subnet"
_add_field "Bridge MTU       " "$(_wiz_fmt "$_DSP_MTU")" "bridge_mtu"
fi
_add_field "IPv6             " "$(_wiz_fmt "$_DSP_IPV6")" "ipv6"
_add_field "Firewall         " "$(_wiz_fmt "$_DSP_FIREWALL")" "firewall"
;;
3)if
[[ $DRIVE_COUNT -gt 1 ]]
then
_add_field "Boot disk        " "$(_wiz_fmt "$_DSP_BOOT")" "boot_disk"
_add_field "Pool disks       " "$(_wiz_fmt "$_DSP_POOL")" "pool_disks"
fi
_add_field "ZFS mode         " "$(_wiz_fmt "$_DSP_ZFS")" "zfs_mode"
_add_field "ZFS ARC          " "$(_wiz_fmt "$_DSP_ARC")" "zfs_arc"
;;
4)_add_field "Tailscale        " "$(_wiz_fmt "$_DSP_TAILSCALE")" "tailscale"
if [[ $INSTALL_TAILSCALE != "yes" ]];then
_add_field "SSL Certificate  " "$(_wiz_fmt "$_DSP_SSL")" "ssl"
fi
_add_field "Shell            " "$(_wiz_fmt "$_DSP_SHELL")" "shell"
_add_field "Power profile    " "$(_wiz_fmt "$_DSP_POWER")" "power_profile"
_add_field "Security         " "$(_wiz_fmt "$_DSP_SECURITY")" "security"
_add_field "Monitoring       " "$(_wiz_fmt "$_DSP_MONITORING")" "monitoring"
_add_field "Tools            " "$(_wiz_fmt "$_DSP_TOOLS")" "tools"
_add_field "API Token        " "$(_wiz_fmt "$_DSP_API")" "api_token"
;;
5)_add_field "SSH Key          " "$(_wiz_fmt "$_DSP_SSH")" "ssh_key"
esac
}
_wiz_render_menu(){
local selection="$1"
local output=""
local banner_output
banner_output=$(show_banner)
_wiz_build_display_values
output+="$banner_output\n\n$(_wiz_render_nav)\n\n"
_WIZ_FIELD_MAP=()
local field_idx=0
_add_field(){
local label="$1"
local value="$2"
local field_name="$3"
_WIZ_FIELD_MAP+=("$field_name")
if [[ $field_idx -eq $selection ]];then
output+="$CLR_ORANGE›$CLR_RESET $CLR_GRAY$label$CLR_RESET$value\n"
else
output+="  $CLR_GRAY$label$CLR_RESET$value\n"
fi
((field_idx++))
}
_wiz_render_screen_content "$WIZ_CURRENT_SCREEN" "$selection"
_WIZ_FIELD_COUNT=$field_idx
output+="\n"
local left_clr right_clr start_clr
left_clr=$([[ $WIZ_CURRENT_SCREEN -gt 0 ]]&&echo "$CLR_ORANGE"||echo "$CLR_GRAY")
right_clr=$([[ $WIZ_CURRENT_SCREEN -lt $((${#WIZ_SCREENS[@]}-1)) ]]&&echo "$CLR_ORANGE"||echo "$CLR_GRAY")
start_clr=$(_wiz_config_complete&&echo "$CLR_ORANGE"||echo "$CLR_GRAY")
local nav_hint=""
nav_hint+="[$left_clr←$CLR_GRAY] prev  "
nav_hint+="[$CLR_ORANGE↑↓$CLR_GRAY] navigate  [${CLR_ORANGE}Enter$CLR_GRAY] edit  "
nav_hint+="[$right_clr→$CLR_GRAY] next  "
nav_hint+="[${start_clr}S$CLR_GRAY] start  [${CLR_ORANGE}Q$CLR_GRAY] quit"
output+="$CLR_GRAY$nav_hint$CLR_RESET"
_wiz_clear
printf '%b' "$output"
}
_country_to_locale(){
local country="${1:-us}"
country="${country,,}"
case "$country" in
us|gb|au|nz|ca|ie)echo "en_${country^^}.UTF-8";;
ru)echo "ru_RU.UTF-8";;
ua)echo "uk_UA.UTF-8";;
de|at)echo "de_${country^^}.UTF-8";;
fr|be)echo "fr_${country^^}.UTF-8";;
es|mx|ar|co|cl|pe)echo "es_${country^^}.UTF-8";;
pt|br)echo "pt_${country^^}.UTF-8";;
it)echo "it_IT.UTF-8";;
nl)echo "nl_NL.UTF-8";;
pl)echo "pl_PL.UTF-8";;
cz)echo "cs_CZ.UTF-8";;
sk)echo "sk_SK.UTF-8";;
hu)echo "hu_HU.UTF-8";;
ro)echo "ro_RO.UTF-8";;
bg)echo "bg_BG.UTF-8";;
hr)echo "hr_HR.UTF-8";;
rs)echo "sr_RS.UTF-8";;
si)echo "sl_SI.UTF-8";;
se)echo "sv_SE.UTF-8";;
no)echo "nb_NO.UTF-8";;
dk)echo "da_DK.UTF-8";;
fi)echo "fi_FI.UTF-8";;
ee)echo "et_EE.UTF-8";;
lv)echo "lv_LV.UTF-8";;
lt)echo "lt_LT.UTF-8";;
gr)echo "el_GR.UTF-8";;
tr)echo "tr_TR.UTF-8";;
il)echo "he_IL.UTF-8";;
jp)echo "ja_JP.UTF-8";;
cn)echo "zh_CN.UTF-8";;
tw)echo "zh_TW.UTF-8";;
kr)echo "ko_KR.UTF-8";;
in)echo "hi_IN.UTF-8";;
th)echo "th_TH.UTF-8";;
vn)echo "vi_VN.UTF-8";;
id)echo "id_ID.UTF-8";;
my)echo "ms_MY.UTF-8";;
ph)echo "en_PH.UTF-8";;
sg)echo "en_SG.UTF-8";;
za)echo "en_ZA.UTF-8";;
eg)echo "ar_EG.UTF-8";;
sa)echo "ar_SA.UTF-8";;
ae)echo "ar_AE.UTF-8";;
ir)echo "fa_IR.UTF-8";;
*)echo "en_US.UTF-8"
esac
}
_update_locale_from_country(){
LOCALE=$(_country_to_locale "$COUNTRY")
log "Set LOCALE=$LOCALE from COUNTRY=$COUNTRY"
}
_edit_hostname(){
while true;do
_wiz_start_edit
_show_input_footer
local new_hostname
new_hostname=$(_wiz_input \
--placeholder "e.g., pve, proxmox, node1" \
--value "$PVE_HOSTNAME" \
--prompt "Hostname: ")
if [[ -z $new_hostname ]];then
return
fi
if validate_hostname "$new_hostname";then
PVE_HOSTNAME="$new_hostname"
break
else
show_validation_error "Invalid hostname format"
fi
done
while true;do
_wiz_start_edit
_show_input_footer
local new_domain
new_domain=$(_wiz_input \
--placeholder "e.g., local, example.com" \
--value "$DOMAIN_SUFFIX" \
--prompt "Domain: ")
if [[ -z $new_domain ]];then
return
fi
DOMAIN_SUFFIX="$new_domain"
break
done
FQDN="$PVE_HOSTNAME.$DOMAIN_SUFFIX"
}
_edit_email(){
while true;do
_wiz_start_edit
_show_input_footer
local new_email
new_email=$(_wiz_input \
--placeholder "admin@example.com" \
--value "$EMAIL" \
--prompt "Email: ")
if [[ -z $new_email ]];then
return
fi
if validate_email "$new_email";then
EMAIL="$new_email"
break
else
show_validation_error "Invalid email format"
fi
done
}
_edit_password(){
while true;do
_wiz_start_edit
_show_input_footer "filter" 3
local choice
choice=$(echo -e "Manual entry\nGenerate password"|_wiz_choose \
--header="Password:")
if [[ -z $choice ]];then
return
fi
case "$choice" in
"Generate password")NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
PASSWORD_GENERATED="yes"
_wiz_start_edit
_wiz_hide_cursor
_wiz_warn "Please save this password - it will be required for login"
_wiz_blank_line
echo -e "${CLR_CYAN}Generated password:$CLR_RESET $CLR_ORANGE$NEW_ROOT_PASSWORD$CLR_RESET"
_wiz_blank_line
echo -e "${CLR_GRAY}Press any key to continue...$CLR_RESET"
read -n 1 -s -r
break
;;
"Manual entry")_wiz_start_edit
_show_input_footer
local new_password
new_password=$(_wiz_input \
--password \
--placeholder "Enter password" \
--prompt "Password: ")
if [[ -z $new_password ]];then
continue
fi
local password_error
password_error=$(get_password_error "$new_password")
if [[ -n $password_error ]];then
show_validation_error "$password_error"
continue
fi
NEW_ROOT_PASSWORD="$new_password"
PASSWORD_GENERATED="no"
break
esac
done
}
_edit_timezone(){
_wiz_start_edit
_show_input_footer "filter" 6
local selected
selected=$(echo "$WIZ_TIMEZONES"|gum filter \
--placeholder "Type to search..." \
--indicator "›" \
--height 5 \
--no-show-help \
--prompt "Timezone: " \
--prompt.foreground "$HEX_CYAN" \
--indicator.foreground "$HEX_ORANGE" \
--match.foreground "$HEX_ORANGE")
if [[ -n $selected ]];then
TIMEZONE="$selected"
local country_code="${TZ_TO_COUNTRY[$selected]:-}"
if [[ -n $country_code ]];then
COUNTRY="$country_code"
_update_locale_from_country
fi
fi
}
_edit_keyboard(){
_wiz_start_edit
_show_input_footer "filter" 6
local selected
selected=$(echo "$WIZ_KEYBOARD_LAYOUTS"|gum filter \
--placeholder "Type to search..." \
--indicator "›" \
--height 5 \
--no-show-help \
--prompt "Keyboard: " \
--prompt.foreground "$HEX_CYAN" \
--indicator.foreground "$HEX_ORANGE" \
--match.foreground "$HEX_ORANGE")
if [[ -n $selected ]];then
KEYBOARD="$selected"
fi
}
_edit_country(){
_wiz_start_edit
_show_input_footer "filter" 6
local selected
selected=$(echo "$WIZ_COUNTRIES"|gum filter \
--placeholder "Type to search..." \
--indicator "›" \
--height 5 \
--no-show-help \
--prompt "Country: " \
--prompt.foreground "$HEX_CYAN" \
--indicator.foreground "$HEX_ORANGE" \
--match.foreground "$HEX_ORANGE")
if [[ -n $selected ]];then
COUNTRY="$selected"
_update_locale_from_country
fi
}
_edit_iso_version(){
_wiz_start_edit
local iso_list
iso_list=$(get_available_proxmox_isos 5)
if [[ -z $iso_list ]];then
_wiz_hide_cursor
_wiz_error "Failed to fetch ISO list"
sleep 2
return
fi
_show_input_footer "filter" 6
local selected
selected=$(echo "$iso_list"|_wiz_choose \
--header="Proxmox Version:")
[[ -n $selected ]]&&PROXMOX_ISO_VERSION="$selected"
}
_edit_repository(){
_wiz_start_edit
_wiz_description \
"Proxmox VE package repository:" \
"" \
"  {{cyan:No-subscription}}: Free updates, community tested" \
"  {{cyan:Enterprise}}:      Stable updates, requires license" \
"  {{cyan:Test}}:            Latest builds, may be unstable" \
""
_show_input_footer "filter" 4
local selected
selected=$(echo "$WIZ_REPO_TYPES"|_wiz_choose \
--header="Repository:")
if [[ -n $selected ]];then
local repo_type=""
case "$selected" in
"No-subscription (free)")repo_type="no-subscription";;
"Enterprise")repo_type="enterprise";;
"Test/Development")repo_type="test"
esac
PVE_REPO_TYPE="$repo_type"
if [[ $repo_type == "enterprise" ]];then
_wiz_input_screen "Enter Proxmox subscription key (optional)"
local sub_key
sub_key=$(_wiz_input \
--placeholder "pve2c-..." \
--value "$PVE_SUBSCRIPTION_KEY" \
--prompt "Subscription Key: ")
PVE_SUBSCRIPTION_KEY="$sub_key"
else
PVE_SUBSCRIPTION_KEY=""
fi
fi
}
_edit_interface(){
_wiz_start_edit
local interface_count=${INTERFACE_COUNT:-1}
local available_interfaces=${AVAILABLE_INTERFACES:-$INTERFACE_NAME}
local footer_size=$((interface_count+1))
_show_input_footer "filter" "$footer_size"
local selected
selected=$(echo "$available_interfaces"|_wiz_choose \
--header="Network Interface:")
[[ -n $selected ]]&&INTERFACE_NAME="$selected"
}
_edit_bridge_mode(){
_wiz_start_edit
_wiz_description \
"Network bridge configuration for VMs:" \
"" \
"  {{cyan:External}}: VMs get public IPs directly (routed mode)" \
"  {{cyan:Internal}}: Private network with NAT (10.x.x.x)" \
"  {{cyan:Both}}:     External + Internal bridges" \
""
_show_input_footer "filter" 4
local selected
selected=$(echo "$WIZ_BRIDGE_MODES"|_wiz_choose \
--header="Bridge mode:")
if [[ -n $selected ]];then
case "$selected" in
"External bridge")BRIDGE_MODE="external";;
"Internal NAT")BRIDGE_MODE="internal";;
"Both")BRIDGE_MODE="both"
esac
fi
}
_edit_private_subnet(){
_wiz_start_edit
_show_input_footer "filter" 5
local selected
selected=$(echo "$WIZ_PRIVATE_SUBNETS"|_wiz_choose \
--header="Private subnet:")
if [[ -z $selected ]];then
return
fi
if [[ $selected == "Custom" ]];then
while true;do
_wiz_input_screen \
"Enter private subnet in CIDR notation" \
"Example: 10.0.0.0/24"
local new_subnet
new_subnet=$(_wiz_input \
--placeholder "e.g., 10.10.10.0/24" \
--value "$PRIVATE_SUBNET" \
--prompt "Private subnet: ")
if [[ -z $new_subnet ]];then
return
fi
if validate_subnet "$new_subnet";then
PRIVATE_SUBNET="$new_subnet"
break
else
show_validation_error "Invalid subnet format. Use CIDR notation like: 10.0.0.0/24"
fi
done
else
PRIVATE_SUBNET="$selected"
fi
}
_edit_bridge_mtu(){
_wiz_start_edit
_wiz_description \
"MTU for private bridge (VM-to-VM traffic):" \
"" \
"  {{cyan:9000}}:  Jumbo frames (better VM performance)" \
"  {{cyan:1500}}:  Standard MTU (safe default)" \
""
_show_input_footer "filter" 3
local selected
selected=$(echo "$WIZ_BRIDGE_MTU"|_wiz_choose \
--header="Bridge MTU:")
case "$selected" in
"9000 (jumbo frames)")BRIDGE_MTU="9000";;
"1500 (standard)")BRIDGE_MTU="1500"
esac
}
_edit_ipv6(){
_wiz_start_edit
_show_input_footer "filter" 4
local selected
selected=$(echo "$WIZ_IPV6_MODES"|_wiz_choose \
--header="IPv6:")
if [[ -z $selected ]];then
return
fi
local ipv6_mode=""
case "$selected" in
"Auto")ipv6_mode="auto";;
"Manual")ipv6_mode="manual";;
"Disabled")ipv6_mode="disabled"
esac
IPV6_MODE="$ipv6_mode"
if [[ $ipv6_mode == "manual" ]];then
while true;do
_wiz_input_screen \
"Enter IPv6 address in CIDR notation" \
"Example: 2001:db8::1/64"
local ipv6_addr
ipv6_addr=$(_wiz_input \
--placeholder "2001:db8::1/64" \
--prompt "IPv6 Address: " \
--value "${IPV6_ADDRESS:-${MAIN_IPV6:+$MAIN_IPV6/64}}")
if [[ -z $ipv6_addr ]];then
IPV6_MODE=""
return
fi
if validate_ipv6_cidr "$ipv6_addr";then
IPV6_ADDRESS="$ipv6_addr"
MAIN_IPV6="${ipv6_addr%/*}"
break
else
show_validation_error "Invalid IPv6 CIDR notation. Use format like: 2001:db8::1/64"
fi
done
while true;do
_wiz_input_screen \
"Enter IPv6 gateway address" \
"Default for Hetzner: fe80::1 (link-local)"
local ipv6_gw
ipv6_gw=$(_wiz_input \
--placeholder "fe80::1" \
--prompt "Gateway: " \
--value "${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}")
if [[ -z $ipv6_gw ]];then
IPV6_GATEWAY="$DEFAULT_IPV6_GATEWAY"
break
fi
if validate_ipv6_gateway "$ipv6_gw";then
IPV6_GATEWAY="$ipv6_gw"
break
else
show_validation_error "Invalid IPv6 gateway address"
fi
done
elif [[ $ipv6_mode == "disabled" ]];then
MAIN_IPV6=""
IPV6_GATEWAY=""
FIRST_IPV6_CIDR=""
IPV6_ADDRESS=""
elif [[ $ipv6_mode == "auto" ]];then
IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
fi
}
_edit_firewall(){
_wiz_start_edit
_wiz_description \
"Host firewall (nftables):" \
"" \
"  {{cyan:Stealth}}:  Blocks ALL incoming (Tailscale/bridges only)" \
"  {{cyan:Strict}}:   Allows SSH only (port 22)" \
"  {{cyan:Standard}}: Allows SSH + Proxmox Web UI (8006)" \
"  {{cyan:Disabled}}: No firewall rules" \
"" \
"  Note: VMs always have full network access via bridges." \
""
_show_input_footer "filter" 5
local selected
selected=$(echo "$WIZ_FIREWALL_MODES"|_wiz_choose \
--header="Firewall mode:")
if [[ -n $selected ]];then
case "$selected" in
"Stealth (Tailscale only)")INSTALL_FIREWALL="yes"
FIREWALL_MODE="stealth"
;;
"Strict (SSH only)")INSTALL_FIREWALL="yes"
FIREWALL_MODE="strict"
;;
"Standard (SSH + Web UI)")INSTALL_FIREWALL="yes"
FIREWALL_MODE="standard"
;;
"Disabled")INSTALL_FIREWALL="no"
FIREWALL_MODE=""
esac
fi
}
_edit_zfs_mode(){
_wiz_start_edit
local pool_count=${#ZFS_POOL_DISKS[@]}
local options=""
if [[ $pool_count -eq 1 ]];then
options="Single disk"
elif [[ $pool_count -eq 2 ]];then
options="RAID-0 (striped)\nRAID-1 (mirror)"
elif [[ $pool_count -eq 3 ]];then
options="RAID-0 (striped)\nRAID-1 (mirror)\nRAID-Z1 (parity)"
elif [[ $pool_count -eq 4 ]];then
options="RAID-0 (striped)\nRAID-1 (mirror)\nRAID-Z1 (parity)\nRAID-Z2 (double parity)\nRAID-10 (striped mirrors)"
elif [[ $pool_count -ge 5 ]];then
options="RAID-0 (striped)\nRAID-1 (mirror)\nRAID-Z1 (parity)\nRAID-Z2 (double parity)\nRAID-Z3 (triple parity)\nRAID-10 (striped mirrors)"
fi
local item_count
item_count=$(echo -e "$options"|wc -l)
_show_input_footer "filter" "$((item_count+1))"
local selected
selected=$(echo -e "$options"|_wiz_choose \
--header="ZFS mode ($pool_count disks in pool):")
if [[ -n $selected ]];then
case "$selected" in
"Single disk")ZFS_RAID="single";;
"RAID-0 (striped)")ZFS_RAID="raid0";;
"RAID-1 (mirror)")ZFS_RAID="raid1";;
"RAID-Z1 (parity)")ZFS_RAID="raidz1";;
"RAID-Z2 (double parity)")ZFS_RAID="raidz2";;
"RAID-Z3 (triple parity)")ZFS_RAID="raidz3";;
"RAID-10 (striped mirrors)")ZFS_RAID="raid10"
esac
fi
}
_edit_zfs_arc(){
_wiz_start_edit
_wiz_description \
"ZFS Adaptive Replacement Cache (ARC) memory allocation:" \
"" \
"  {{cyan:VM-focused}}:      Fixed 4GB for ARC (more RAM for VMs)" \
"  {{cyan:Balanced}}:        25-40% of RAM based on total size" \
"  {{cyan:Storage-focused}}: 50% of RAM (maximize ZFS caching)" \
""
_show_input_footer "filter" 4
local selected
selected=$(echo "$WIZ_ZFS_ARC_MODES"|_wiz_choose \
--header="ZFS ARC memory strategy:")
if [[ -n $selected ]];then
case "$selected" in
"VM-focused (4GB fixed)")ZFS_ARC_MODE="vm-focused";;
"Balanced (25-40% of RAM)")ZFS_ARC_MODE="balanced";;
"Storage-focused (50% of RAM)")ZFS_ARC_MODE="storage-focused"
esac
fi
}
_edit_tailscale(){
_wiz_start_edit
_wiz_description \
"Tailscale VPN with stealth mode:" \
"" \
"  {{cyan:Enabled}}:  Access via Tailscale only (blocks public SSH)" \
"  {{cyan:Disabled}}: Standard access via public IP" \
"" \
"  Stealth mode blocks ALL incoming traffic on public IP." \
""
_show_input_footer "filter" 3
local selected
selected=$(echo -e "Disabled\nEnabled"|_wiz_choose \
--header="Tailscale:")
case "$selected" in
Enabled)local auth_key=""
while true;do
_wiz_start_edit
_show_input_footer
auth_key=$(_wiz_input \
--placeholder "tskey-auth-..." \
--prompt "Auth Key: ")
[[ -z $auth_key ]]&&break
if validate_tailscale_key "$auth_key";then
break
fi
show_validation_error "Invalid key format. Expected: tskey-auth-xxx-xxx"
done
if [[ -n $auth_key ]];then
INSTALL_TAILSCALE="yes"
TAILSCALE_AUTH_KEY="$auth_key"
TAILSCALE_SSH="yes"
TAILSCALE_WEBUI="yes"
SSL_TYPE="self-signed"
if [[ -z $INSTALL_FIREWALL ]];then
INSTALL_FIREWALL="yes"
FIREWALL_MODE="stealth"
fi
else
INSTALL_TAILSCALE="no"
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH=""
TAILSCALE_WEBUI=""
SSL_TYPE=""
fi
;;
Disabled)INSTALL_TAILSCALE="no"
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH=""
TAILSCALE_WEBUI=""
SSL_TYPE=""
if [[ -z $INSTALL_FIREWALL ]];then
INSTALL_FIREWALL="yes"
FIREWALL_MODE="standard"
fi
esac
}
_edit_ssl(){
_wiz_start_edit
_wiz_description \
"SSL certificate for Proxmox web interface:" \
"" \
"  {{cyan:Self-signed}}:   Works always, browser shows warning" \
"  {{cyan:Let's Encrypt}}: Trusted cert, requires public DNS" \
""
_show_input_footer "filter" 3
local selected
selected=$(echo "$WIZ_SSL_TYPES"|_wiz_choose \
--header="SSL Certificate:")
local ssl_type=""
case "$selected" in
"Self-signed")ssl_type="self-signed";;
"Let's Encrypt")ssl_type="letsencrypt"
esac
if [[ $ssl_type == "letsencrypt" ]];then
if [[ -z $FQDN ]];then
_wiz_start_edit
_wiz_hide_cursor
_wiz_error "Error: Hostname not configured!"
_wiz_blank_line
_wiz_dim "Let's Encrypt requires a fully qualified domain name."
_wiz_dim "Please configure hostname first."
sleep 3
SSL_TYPE="self-signed"
return
fi
if [[ $FQDN == *.local ]]||! validate_fqdn "$FQDN";then
_wiz_start_edit
_wiz_hide_cursor
_wiz_error "Error: Invalid domain name!"
_wiz_blank_line
_wiz_dim "Current hostname: $CLR_ORANGE$FQDN$CLR_RESET"
_wiz_dim "Let's Encrypt requires a valid public FQDN (e.g., pve.example.com)."
_wiz_dim "Domains ending with .local are not supported."
sleep 3
SSL_TYPE="self-signed"
return
fi
_wiz_start_edit
_wiz_hide_cursor
_wiz_blank_line
_wiz_dim "Domain: $CLR_ORANGE$FQDN$CLR_RESET"
_wiz_dim "Expected IP: $CLR_ORANGE$MAIN_IPV4$CLR_RESET"
_wiz_blank_line
local dns_result_file
dns_result_file=$(mktemp)
(validate_dns_resolution "$FQDN" "$MAIN_IPV4"
echo $? >"$dns_result_file") > \
/dev/null 2>&1&
local dns_pid=$!
printf "%s" "${CLR_CYAN}Validating DNS resolution$CLR_RESET"
while kill -0 "$dns_pid" 2>/dev/null;do
sleep 0.3
local dots_count=$((($(date +%s)%3)+1))
local dots
dots=$(printf '.%.0s' $(seq 1 $dots_count))
printf "\r%sValidating DNS resolution%s%-3s%s" "$CLR_CYAN" "$CLR_ORANGE" "$dots" "$CLR_RESET"
done
wait "$dns_pid" 2>/dev/null
local dns_result
dns_result=$(cat "$dns_result_file")
rm -f "$dns_result_file"
printf "\r%-80s\r" " "
if [[ $dns_result -eq 1 ]];then
_wiz_hide_cursor
_wiz_error "✗ Domain does not resolve to any IP address"
_wiz_blank_line
_wiz_dim "Please configure DNS A record:"
_wiz_dim "  $CLR_ORANGE$FQDN$CLR_RESET → $CLR_ORANGE$MAIN_IPV4$CLR_RESET"
_wiz_blank_line
_wiz_dim "Falling back to self-signed certificate."
sleep 5
SSL_TYPE="self-signed"
return
elif [[ $dns_result -eq 2 ]];then
_wiz_hide_cursor
_wiz_error "✗ Domain resolves to wrong IP address"
_wiz_blank_line
_wiz_dim "Current DNS: $CLR_ORANGE$FQDN$CLR_RESET → $CLR_RED$DNS_RESOLVED_IP$CLR_RESET"
_wiz_dim "Expected:    $CLR_ORANGE$FQDN$CLR_RESET → $CLR_ORANGE$MAIN_IPV4$CLR_RESET"
_wiz_blank_line
_wiz_dim "Please update DNS A record to point to $CLR_ORANGE$MAIN_IPV4$CLR_RESET"
_wiz_blank_line
_wiz_dim "Falling back to self-signed certificate."
sleep 5
SSL_TYPE="self-signed"
return
else
_wiz_info "✓ DNS resolution successful"
_wiz_dim "  $CLR_ORANGE$FQDN$CLR_RESET → $CLR_CYAN$DNS_RESOLVED_IP$CLR_RESET"
sleep 3
SSL_TYPE="$ssl_type"
fi
else
[[ -n $ssl_type ]]&&SSL_TYPE="$ssl_type"
fi
}
_edit_shell(){
_wiz_start_edit
_show_input_footer "filter" 3
local selected
selected=$(echo "$WIZ_SHELL_OPTIONS"|_wiz_choose \
--header="Shell:")
if [[ -n $selected ]];then
case "$selected" in
"ZSH")SHELL_TYPE="zsh";;
"Bash")SHELL_TYPE="bash"
esac
fi
}
_edit_power_profile(){
_wiz_start_edit
local avail_governors=""
if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]];then
avail_governors=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
fi
local options=()
local descriptions=()
if [[ -z $avail_governors ]]||echo "$avail_governors"|grep -qw "performance";then
options+=("Performance")
descriptions+=("  {{cyan:Performance}}:  Max frequency (highest power)")
fi
if echo "$avail_governors"|grep -qw "ondemand";then
options+=("Balanced")
descriptions+=("  {{cyan:Balanced}}:     Scale based on load")
elif echo "$avail_governors"|grep -qw "powersave";then
options+=("Balanced")
descriptions+=("  {{cyan:Balanced}}:     Dynamic scaling (power efficient)")
fi
if echo "$avail_governors"|grep -qw "schedutil";then
options+=("Adaptive")
descriptions+=("  {{cyan:Adaptive}}:     Kernel-managed scaling")
fi
if echo "$avail_governors"|grep -qw "conservative";then
options+=("Conservative")
descriptions+=("  {{cyan:Conservative}}: Gradual frequency changes")
fi
if [[ ${#options[@]} -eq 0 ]];then
options=("Performance" "Balanced")
descriptions=(
"  {{cyan:Performance}}:  Max frequency (highest power)"
"  {{cyan:Balanced}}:     Dynamic scaling (power efficient)")
fi
_wiz_description \
"CPU frequency scaling governor:" \
"" \
"${descriptions[@]}" \
""
_show_input_footer "filter" $((${#options[@]}+1))
local options_str
options_str=$(printf '%s\n' "${options[@]}")
local selected
selected=$(echo "$options_str"|_wiz_choose \
--header="Power profile:")
if [[ -n $selected ]];then
case "$selected" in
"Performance")CPU_GOVERNOR="performance";;
"Balanced")if
echo "$avail_governors"|grep -qw "ondemand"
then
CPU_GOVERNOR="ondemand"
else
CPU_GOVERNOR="powersave"
fi
;;
"Adaptive")CPU_GOVERNOR="schedutil";;
"Conservative")CPU_GOVERNOR="conservative"
esac
fi
}
_edit_features_security(){
_wiz_start_edit
_wiz_description \
"Security features (use Space to toggle):" \
"" \
"  {{cyan:apparmor}}:    Mandatory access control (MAC)" \
"  {{cyan:auditd}}:      Security audit logging" \
"  {{cyan:aide}}:        File integrity monitoring (daily)" \
"  {{cyan:chkrootkit}}:  Rootkit scanning (weekly)" \
"  {{cyan:lynis}}:       Security auditing (weekly)" \
"  {{cyan:needrestart}}: Auto-restart services after updates" \
""
_show_input_footer "checkbox" 7
local preselected=()
[[ $INSTALL_APPARMOR == "yes" ]]&&preselected+=("apparmor")
[[ $INSTALL_AUDITD == "yes" ]]&&preselected+=("auditd")
[[ $INSTALL_AIDE == "yes" ]]&&preselected+=("aide")
[[ $INSTALL_CHKROOTKIT == "yes" ]]&&preselected+=("chkrootkit")
[[ $INSTALL_LYNIS == "yes" ]]&&preselected+=("lynis")
[[ $INSTALL_NEEDRESTART == "yes" ]]&&preselected+=("needrestart")
local gum_args=(
--no-limit
--header="Security:"
--header.foreground "$HEX_CYAN"
--cursor "$CLR_ORANGE›$CLR_RESET "
--cursor.foreground "$HEX_NONE"
--cursor-prefix "◦ "
--selected.foreground "$HEX_WHITE"
--selected-prefix "$CLR_CYAN✓$CLR_RESET "
--unselected-prefix "◦ "
--no-show-help)
for item in "${preselected[@]}";do
gum_args+=(--selected "$item")
done
local selected
selected=$(printf '%s\n' apparmor auditd aide chkrootkit lynis needrestart|_wiz_choose "${gum_args[@]}")
INSTALL_APPARMOR="no"
INSTALL_AUDITD="no"
INSTALL_AIDE="no"
INSTALL_CHKROOTKIT="no"
INSTALL_LYNIS="no"
INSTALL_NEEDRESTART="no"
[[ $selected == *apparmor* ]]&&INSTALL_APPARMOR="yes"
[[ $selected == *auditd* ]]&&INSTALL_AUDITD="yes"
[[ $selected == *aide* ]]&&INSTALL_AIDE="yes"
[[ $selected == *chkrootkit* ]]&&INSTALL_CHKROOTKIT="yes"
[[ $selected == *lynis* ]]&&INSTALL_LYNIS="yes"
[[ $selected == *needrestart* ]]&&INSTALL_NEEDRESTART="yes"
}
_edit_features_monitoring(){
_wiz_start_edit
_wiz_description \
"Monitoring features (use Space to toggle):" \
"" \
"  {{cyan:vnstat}}:     Network traffic monitoring" \
"  {{cyan:netdata}}:    Real-time monitoring (port 19999)" \
"  {{cyan:prometheus}}: Node exporter for metrics (port 9100)" \
""
_show_input_footer "checkbox" 4
local preselected=()
[[ $INSTALL_VNSTAT == "yes" ]]&&preselected+=("vnstat")
[[ $INSTALL_NETDATA == "yes" ]]&&preselected+=("netdata")
[[ $INSTALL_PROMETHEUS == "yes" ]]&&preselected+=("prometheus")
local gum_args=(
--no-limit
--header="Monitoring:"
--header.foreground "$HEX_CYAN"
--cursor "$CLR_ORANGE›$CLR_RESET "
--cursor.foreground "$HEX_NONE"
--cursor-prefix "◦ "
--selected.foreground "$HEX_WHITE"
--selected-prefix "$CLR_CYAN✓$CLR_RESET "
--unselected-prefix "◦ "
--no-show-help)
for item in "${preselected[@]}";do
gum_args+=(--selected "$item")
done
local selected
selected=$(printf '%s\n' vnstat netdata prometheus|_wiz_choose "${gum_args[@]}")
INSTALL_VNSTAT="no"
INSTALL_NETDATA="no"
INSTALL_PROMETHEUS="no"
[[ $selected == *vnstat* ]]&&INSTALL_VNSTAT="yes"
[[ $selected == *netdata* ]]&&INSTALL_NETDATA="yes"
[[ $selected == *prometheus* ]]&&INSTALL_PROMETHEUS="yes"
}
_edit_features_tools(){
_wiz_start_edit
_wiz_description \
"Tools (use Space to toggle):" \
"" \
"  {{cyan:yazi}}:       Terminal file manager (Catppuccin theme)" \
"  {{cyan:nvim}}:       Neovim as default editor" \
"  {{cyan:ringbuffer}}: Network ring buffer tuning" \
""
_show_input_footer "checkbox" 4
local preselected=()
[[ $INSTALL_YAZI == "yes" ]]&&preselected+=("yazi")
[[ $INSTALL_NVIM == "yes" ]]&&preselected+=("nvim")
[[ $INSTALL_RINGBUFFER == "yes" ]]&&preselected+=("ringbuffer")
local gum_args=(
--no-limit
--header="Tools:"
--header.foreground "$HEX_CYAN"
--cursor "$CLR_ORANGE›$CLR_RESET "
--cursor.foreground "$HEX_NONE"
--cursor-prefix "◦ "
--selected.foreground "$HEX_WHITE"
--selected-prefix "$CLR_CYAN✓$CLR_RESET "
--unselected-prefix "◦ "
--no-show-help)
for item in "${preselected[@]}";do
gum_args+=(--selected "$item")
done
local selected
selected=$(printf '%s\n' yazi nvim ringbuffer|_wiz_choose "${gum_args[@]}")
INSTALL_YAZI="no"
INSTALL_NVIM="no"
INSTALL_RINGBUFFER="no"
[[ $selected == *yazi* ]]&&INSTALL_YAZI="yes"
[[ $selected == *nvim* ]]&&INSTALL_NVIM="yes"
[[ $selected == *ringbuffer* ]]&&INSTALL_RINGBUFFER="yes"
}
_edit_api_token(){
_wiz_start_edit
_show_input_footer "filter" 3
local selected
selected=$(echo -e "Disabled\nEnabled"|_wiz_choose \
--header="API Token (privileged, no expiration):")
case "$selected" in
Enabled)_wiz_input_screen "Enter API token name (default: automation)"
local token_name
token_name=$(_wiz_input \
--placeholder "automation" \
--prompt "Token name: " \
--no-show-help \
--value="${API_TOKEN_NAME:-automation}")
if [[ -n $token_name && $token_name =~ ^[a-zA-Z0-9_-]+$ ]];then
API_TOKEN_NAME="$token_name"
INSTALL_API_TOKEN="yes"
else
API_TOKEN_NAME="automation"
INSTALL_API_TOKEN="yes"
fi
;;
Disabled)INSTALL_API_TOKEN="no"
API_TOKEN_NAME="automation"
esac
}
_edit_ssh_key(){
while true;do
_wiz_start_edit
local detected_key
detected_key=$(get_rescue_ssh_key)
if [[ -n $detected_key ]];then
parse_ssh_key "$detected_key"
_wiz_hide_cursor
_wiz_warn "Detected SSH key from Rescue System:"
_wiz_blank_line
echo -e "${CLR_GRAY}Type:$CLR_RESET    $SSH_KEY_TYPE"
echo -e "${CLR_GRAY}Key:$CLR_RESET     $SSH_KEY_SHORT"
[[ -n $SSH_KEY_COMMENT ]]&&echo -e "${CLR_GRAY}Comment:$CLR_RESET $SSH_KEY_COMMENT"
_wiz_blank_line
_show_input_footer "filter" 3
local choice
choice=$(echo -e "Use detected key\nEnter different key"|_wiz_choose \
--header="SSH Key:")
if [[ -z $choice ]];then
return
fi
case "$choice" in
"Use detected key")SSH_PUBLIC_KEY="$detected_key"
break
;;
"Enter different key")
esac
fi
_wiz_input_screen "Paste your SSH public key (ssh-rsa, ssh-ed25519, etc.)"
local new_key
new_key=$(_wiz_input \
--placeholder "ssh-ed25519 AAAA... user@host" \
--value "$SSH_PUBLIC_KEY" \
--prompt "SSH Key: ")
if [[ -z $new_key ]];then
if [[ -n $detected_key ]];then
continue
else
return
fi
fi
if validate_ssh_key_secure "$new_key";then
SSH_PUBLIC_KEY="$new_key"
break
else
show_validation_error "Invalid SSH key. Must be ED25519, RSA/ECDSA ≥2048 bits"
if [[ -n $detected_key ]];then
continue
fi
fi
done
}
_edit_boot_disk(){
_wiz_start_edit
_wiz_description \
"Separate boot disk selection (auto-detected by disk size):" \
"" \
"  {{cyan:None}}: All disks in ZFS rpool (system + VMs)" \
"  {{cyan:Disk}}: Boot disk uses ext4 (system + ISO/templates)" \
"       Pool disks use ZFS tank (VMs only)" \
""
local options="None (all in pool)"
for i in "${!DRIVES[@]}";do
local disk_name="${DRIVE_NAMES[$i]}"
local disk_size="${DRIVE_SIZES[$i]}"
local disk_model="${DRIVE_MODELS[$i]:0:25}"
options+="\n$disk_name - $disk_size  $disk_model"
done
_show_input_footer "filter" "$((DRIVE_COUNT+2))"
local selected
selected=$(echo -e "$options"|_wiz_choose \
--header="Boot disk:")
if [[ -n $selected ]];then
local old_boot_disk="$BOOT_DISK"
if [[ $selected == "None (all in pool)" ]];then
BOOT_DISK=""
else
local disk_name="${selected%% -*}"
BOOT_DISK="/dev/$disk_name"
fi
_rebuild_pool_disks
if [[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]];then
_wiz_start_edit
_wiz_hide_cursor
_wiz_error "✗ Cannot use this boot disk: No disks left for ZFS pool"
_wiz_blank_line
_wiz_dim "At least one disk must remain for the ZFS pool."
_wiz_blank_line
_wiz_dim "Press any key to continue..."
read -r -n 1
BOOT_DISK="$old_boot_disk"
_rebuild_pool_disks
fi
fi
}
_edit_pool_disks(){
while true;do
_wiz_start_edit
local options=""
local preselected=()
for i in "${!DRIVES[@]}";do
if [[ -z $BOOT_DISK || ${DRIVES[$i]} != "$BOOT_DISK" ]];then
local disk_name="${DRIVE_NAMES[$i]}"
local disk_size="${DRIVE_SIZES[$i]}"
local disk_model="${DRIVE_MODELS[$i]:0:25}"
local disk_label="$disk_name - $disk_size  $disk_model"
options+="$disk_label\n"
for pool_disk in "${ZFS_POOL_DISKS[@]}";do
if [[ $pool_disk == "/dev/$disk_name" ]];then
preselected+=("$disk_label")
break
fi
done
fi
done
options="${options%\\n}"
local available_count
if [[ -n $BOOT_DISK ]];then
available_count=$((DRIVE_COUNT-1))
else
available_count=$DRIVE_COUNT
fi
_show_input_footer "checkbox" "$((available_count+1))"
local gum_args=(
--no-limit
--header="ZFS pool disks (min 1):"
--header.foreground "$HEX_CYAN"
--cursor "$CLR_ORANGE›$CLR_RESET "
--cursor.foreground "$HEX_NONE"
--cursor-prefix "◦ "
--selected.foreground "$HEX_WHITE"
--selected-prefix "$CLR_CYAN✓$CLR_RESET "
--unselected-prefix "◦ "
--no-show-help)
for item in "${preselected[@]}";do
gum_args+=(--selected "$item")
done
local selected
local gum_exit_code=0
selected=$(echo -e "$options"|_wiz_choose "${gum_args[@]}")||gum_exit_code=$?
if [[ $gum_exit_code -eq 130 ]];then
return 0
fi
if [[ -z $selected ]];then
show_validation_error "✗ At least one disk must be selected for ZFS pool"
continue
fi
ZFS_POOL_DISKS=()
while IFS= read -r line;do
local disk_name="${line%% -*}"
ZFS_POOL_DISKS+=("/dev/$disk_name")
done <<<"$selected"
_update_zfs_mode_options
break
done
}
_rebuild_pool_disks(){
ZFS_POOL_DISKS=()
for drive in "${DRIVES[@]}";do
[[ -z $BOOT_DISK || $drive != "$BOOT_DISK" ]]&&ZFS_POOL_DISKS+=("$drive")
done
_update_zfs_mode_options
}
_update_zfs_mode_options(){
local pool_count=${#ZFS_POOL_DISKS[@]}
case "$ZFS_RAID" in
single)[[ $pool_count -ne 1 ]]&&ZFS_RAID="";;
raid1|raid0)[[ $pool_count -lt 2 ]]&&ZFS_RAID="";;
raid5|raidz1)[[ $pool_count -lt 3 ]]&&ZFS_RAID="";;
raid10|raidz2)[[ $pool_count -lt 4 ]]&&ZFS_RAID="";;
raidz3)[[ $pool_count -lt 5 ]]&&ZFS_RAID=""
esac
}
prepare_packages(){
log "Starting package preparation"
log "Adding Proxmox repository"
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >/etc/apt/sources.list.d/pve.list
log "Downloading Proxmox GPG key"
curl -fsSL -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg >>"$LOG_FILE" 2>&1&
show_progress $! "Adding Proxmox repository" "Proxmox repository added"
wait $!
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: Failed to download Proxmox GPG key"
print_error "Cannot reach Proxmox repository"
exit 1
fi
log "Proxmox GPG key downloaded successfully"
if type live_log_subtask &>/dev/null 2>&1;then
live_log_subtask "Configuring APT sources"
fi
log "Updating package lists"
apt clean >>"$LOG_FILE" 2>&1
apt update >>"$LOG_FILE" 2>&1&
show_progress $! "Updating package lists" "Package lists updated"
wait $!
exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: Failed to update package lists"
exit 1
fi
log "Package lists updated successfully"
if type live_log_subtask &>/dev/null 2>&1;then
live_log_subtask "Downloading package lists"
fi
log "Installing required packages: proxmox-auto-install-assistant xorriso ovmf wget sshpass"
apt install -yq proxmox-auto-install-assistant xorriso ovmf wget sshpass >>"$LOG_FILE" 2>&1&
show_progress $! "Installing required packages" "Required packages installed"
wait $!
exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: Failed to install required packages"
exit 1
fi
log "Required packages installed successfully"
if type live_log_subtask &>/dev/null 2>&1;then
live_log_subtask "Installing proxmox-auto-install-assistant"
live_log_subtask "Installing xorriso and ovmf"
fi
}
_ISO_LIST_CACHE=""
_CHECKSUM_CACHE=""
prefetch_proxmox_iso_info(){
_ISO_LIST_CACHE=$(curl -s "$PROXMOX_ISO_BASE_URL" 2>/dev/null|grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso'|sort -uV)||true
_CHECKSUM_CACHE=$(curl -s "$PROXMOX_CHECKSUM_URL" 2>/dev/null)||true
}
get_available_proxmox_isos(){
local count="${1:-5}"
echo "$_ISO_LIST_CACHE"|tail -n "$count"|tac
}
get_proxmox_iso_url(){
local iso_filename="$1"
echo "$PROXMOX_ISO_BASE_URL$iso_filename"
}
get_iso_version(){
local iso_filename="$1"
echo "$iso_filename"|sed -E 's/proxmox-ve_([0-9]+\.[0-9]+-[0-9]+)\.iso/\1/'
}
_download_iso_curl(){
local url="$1"
local output="$2"
local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"
local retry_delay="${DOWNLOAD_RETRY_DELAY:-5}"
log "Downloading with curl (single connection, resume-enabled)"
curl -fSL \
--retry "$max_retries" \
--retry-delay "$retry_delay" \
--retry-connrefused \
-C - \
-o "$output" \
"$url" >>"$LOG_FILE" 2>&1
}
_download_iso_wget(){
local url="$1"
local output="$2"
local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"
log "Downloading with wget (single connection, resume-enabled)"
wget -q \
--tries="$max_retries" \
--continue \
--timeout=60 \
--waitretry=5 \
-O "$output" \
"$url" >>"$LOG_FILE" 2>&1
}
_download_iso_aria2c(){
local url="$1"
local output="$2"
local checksum="$3"
local max_retries="${DOWNLOAD_RETRY_COUNT:-3}"
log "Downloading with aria2c (4 connections, with retries)"
local aria2_args=(
-x 4
-s 4
-k 4M
--max-tries="$max_retries"
--retry-wait=5
--timeout=60
--connect-timeout=30
--max-connection-per-server=4
--allow-overwrite=true
--auto-file-renaming=false
-o "$output"
--console-log-level=error
--summary-interval=0)
if [[ -n $checksum ]];then
aria2_args+=(--checksum=sha-256="$checksum")
log "aria2c will verify checksum automatically"
fi
aria2c "${aria2_args[@]}" "$url" >>"$LOG_FILE" 2>&1
}
_download_iso_with_fallback(){
local url="$1"
local output="$2"
local checksum="$3"
if command -v aria2c &>/dev/null;then
log "Trying aria2c (parallel download)..."
if _download_iso_aria2c "$url" "$output" "$checksum"&&[[ -s $output ]];then
DOWNLOAD_METHOD="aria2c"
return 0
fi
log "aria2c failed, trying fallback..."
rm -f "$output" 2>/dev/null
fi
log "Trying curl..."
if _download_iso_curl "$url" "$output"&&[[ -s $output ]];then
DOWNLOAD_METHOD="curl"
return 0
fi
log "curl failed, trying fallback..."
rm -f "$output" 2>/dev/null
if command -v wget &>/dev/null;then
log "Trying wget..."
if _download_iso_wget "$url" "$output"&&[[ -s $output ]];then
DOWNLOAD_METHOD="wget"
return 0
fi
rm -f "$output" 2>/dev/null
fi
log "All download methods failed"
return 1
}
download_proxmox_iso(){
log "Starting Proxmox ISO download"
if [[ -f "pve.iso" ]];then
log "Proxmox ISO already exists, skipping download"
print_success "Proxmox ISO:" "already exists, skipping download"
return 0
fi
if [[ -z $PROXMOX_ISO_VERSION ]];then
log "ERROR: PROXMOX_ISO_VERSION not set"
exit 1
fi
log "Using selected ISO: $PROXMOX_ISO_VERSION"
PROXMOX_ISO_URL=$(get_proxmox_iso_url "$PROXMOX_ISO_VERSION")
log "Found ISO URL: $PROXMOX_ISO_URL"
ISO_FILENAME=$(basename "$PROXMOX_ISO_URL")
local expected_checksum=""
if [[ -n $_CHECKSUM_CACHE ]];then
expected_checksum=$(echo "$_CHECKSUM_CACHE"|grep "$ISO_FILENAME"|awk '{print $1}')
fi
log "Expected checksum: ${expected_checksum:-not available}"
log "Downloading ISO: $ISO_FILENAME"
DOWNLOAD_METHOD=""
_download_iso_with_fallback "$PROXMOX_ISO_URL" "pve.iso" "$expected_checksum"&
show_progress $! "Downloading $ISO_FILENAME" "$ISO_FILENAME downloaded"
wait $!
local exit_code=$?
if [[ $exit_code -ne 0 ]]||[[ ! -s "pve.iso" ]];then
log "ERROR: All download methods failed for Proxmox ISO"
rm -f pve.iso
exit 1
fi
log "Download successful via $DOWNLOAD_METHOD"
local iso_size
iso_size=$(stat -c%s pve.iso 2>/dev/null)||iso_size=0
log "ISO file size: $(echo "$iso_size"|awk '{printf "%.1fG", $1/1024/1024/1024}')"
if [[ -n $expected_checksum ]];then
if [[ $DOWNLOAD_METHOD == "aria2c" ]];then
log "Checksum already verified by aria2c"
if type live_log_subtask &>/dev/null 2>&1;then
live_log_subtask "SHA256: OK (verified by aria2c)"
fi
else
log "Verifying ISO checksum"
local actual_checksum
(actual_checksum=$(sha256sum pve.iso|awk '{print $1}')&&echo "$actual_checksum" >/tmp/checksum_result)&
local checksum_pid=$!
if type show_progress &>/dev/null 2>&1;then
show_progress $checksum_pid "Verifying checksum" "Checksum verified"
else
wait $checksum_pid
fi
actual_checksum=$(cat /tmp/checksum_result 2>/dev/null)
rm -f /tmp/checksum_result
if [[ $actual_checksum != "$expected_checksum" ]];then
log "ERROR: Checksum mismatch! Expected: $expected_checksum, Got: $actual_checksum"
if type live_log_subtask &>/dev/null 2>&1;then
live_log_subtask "SHA256: FAILED"
fi
rm -f pve.iso
exit 1
fi
log "Checksum verification passed"
if type live_log_subtask &>/dev/null 2>&1;then
live_log_subtask "SHA256: OK"
fi
fi
else
log "WARNING: Could not find checksum for $ISO_FILENAME"
print_warning "Could not find checksum for $ISO_FILENAME"
fi
log "Cleaning up temporary files in /tmp"
rm -rf /tmp/tmp.* /tmp/pve-* /tmp/checksum_result 2>/dev/null||true
log "Temporary files cleaned"
}
validate_answer_toml(){
local file="$1"
local required_fields=("fqdn" "mailto" "timezone" "root-password")
for field in "${required_fields[@]}";do
if ! grep -q "^\s*$field\s*=" "$file" 2>/dev/null;then
log "ERROR: Missing required field in answer.toml: $field"
return 1
fi
done
if ! grep -q "\[global\]" "$file" 2>/dev/null;then
log "ERROR: Missing [global] section in answer.toml"
return 1
fi
if command -v proxmox-auto-install-assistant &>/dev/null;then
log "Validating answer.toml with proxmox-auto-install-assistant"
if ! proxmox-auto-install-assistant validate-answer "$file" >>"$LOG_FILE" 2>&1;then
log "ERROR: answer.toml validation failed"
proxmox-auto-install-assistant validate-answer "$file" >>"$LOG_FILE" 2>&1||true
return 1
fi
log "answer.toml validation passed"
else
log "WARNING: proxmox-auto-install-assistant not found, skipping advanced validation"
fi
return 0
}
make_answer_toml(){
log "Creating answer.toml for autoinstall"
log "ZFS_RAID=$ZFS_RAID, BOOT_DISK=$BOOT_DISK"
log "ZFS_POOL_DISKS=(${ZFS_POOL_DISKS[*]})"
(create_virtio_mapping "$BOOT_DISK" "${ZFS_POOL_DISKS[@]}") \
&
show_progress $! "Creating disk mapping" "Disk mapping created"
load_virtio_mapping||{
log "ERROR: Failed to load virtio mapping"
exit 1
}
local FILESYSTEM
local all_disks=()
if [[ -n $BOOT_DISK ]];then
FILESYSTEM="ext4"
all_disks=("$BOOT_DISK")
if [[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]];then
log "ERROR: BOOT_DISK set but no pool disks for ZFS tank creation"
exit 1
fi
log "Boot disk mode: ext4 on boot disk, ZFS 'tank' pool will be created from ${#ZFS_POOL_DISKS[@]} pool disk(s)"
else
FILESYSTEM="zfs"
all_disks=("${ZFS_POOL_DISKS[@]}")
log "All-ZFS mode: ${#all_disks[@]} disk(s) in ZFS rpool ($ZFS_RAID)"
fi
DISK_LIST=$(map_disks_to_virtio "toml_array" "${all_disks[@]}")
if [[ -z $DISK_LIST ]];then
log "ERROR: Failed to map disks to virtio devices"
exit 1
fi
log "FILESYSTEM=$FILESYSTEM, DISK_LIST=$DISK_LIST"
log "Generating answer.toml for autoinstall"
local ssh_keys_toml=""
if [[ -n $SSH_PUBLIC_KEY ]];then
local escaped_key="${SSH_PUBLIC_KEY//\\/\\\\}"
escaped_key="${escaped_key//\"/\\\"}"
ssh_keys_toml="root-ssh-keys = [\"$escaped_key\"]"
fi
local escaped_password="${NEW_ROOT_PASSWORD//\\/\\\\}"
escaped_password="${escaped_password//\"/\\\"}"
cat >./answer.toml <<EOF
[global]
    keyboard = "$KEYBOARD"
    country = "$COUNTRY"
    fqdn = "$FQDN"
    mailto = "$EMAIL"
    timezone = "$TIMEZONE"
    root-password = "$escaped_password"
    reboot-on-error = false
EOF
if [[ -n $ssh_keys_toml ]];then
echo "    $ssh_keys_toml" >>./answer.toml
fi
cat >>./answer.toml <<EOF

[network]
    source = "from-dhcp"

[disk-setup]
    filesystem = "$FILESYSTEM"
    disk-list = $DISK_LIST
EOF
if [[ $FILESYSTEM == "zfs" ]];then
local zfs_raid_value
zfs_raid_value=$(map_raid_to_toml "$ZFS_RAID")
log "Using ZFS raid: $zfs_raid_value"
cat >>./answer.toml <<EOF
    zfs.raid = "$zfs_raid_value"
    zfs.compress = "lz4"
    zfs.checksum = "on"
EOF
elif [[ $FILESYSTEM == "ext4" ]]||[[ $FILESYSTEM == "xfs" ]];then
cat >>./answer.toml <<EOF
    lvm.swapsize = 0
EOF
fi
if ! validate_answer_toml "./answer.toml";then
log "ERROR: answer.toml validation failed"
exit 1
fi
log "answer.toml created and validated:"
cat answer.toml >>"$LOG_FILE"
if type live_log_subtask &>/dev/null 2>&1;then
local total_disks=${#ZFS_POOL_DISKS[@]}
[[ -n $BOOT_DISK ]]&&((total_disks++))
live_log_subtask "Mapped $total_disks disk(s) to virtio"
live_log_subtask "Generated answer.toml ($FILESYSTEM)"
fi
}
make_autoinstall_iso(){
log "Creating autoinstall ISO"
log "Input: pve.iso exists: $(test -f pve.iso&&echo 'yes'||echo 'no')"
log "Input: answer.toml exists: $(test -f answer.toml&&echo 'yes'||echo 'no')"
log "Current directory: $(pwd)"
log "Files in current directory:"
ls -la >>"$LOG_FILE" 2>&1
proxmox-auto-install-assistant prepare-iso pve.iso --fetch-from iso --answer-file answer.toml --output pve-autoinstall.iso >>"$LOG_FILE" 2>&1&
show_progress $! "Creating autoinstall ISO" "Autoinstall ISO created"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: proxmox-auto-install-assistant exited with code $exit_code"
fi
if [[ ! -f "./pve-autoinstall.iso" ]];then
log "ERROR: Autoinstall ISO not found after creation attempt"
log "Files in current directory after attempt:"
ls -la >>"$LOG_FILE" 2>&1
exit 1
fi
log "Autoinstall ISO created successfully: $(stat -c%s pve-autoinstall.iso 2>/dev/null|awk '{printf "%.1fM", $1/1024/1024}')"
if type live_log_subtask &>/dev/null 2>&1;then
live_log_subtask "Packed ISO with xorriso"
fi
log "Removing original ISO to save disk space"
rm -f pve.iso
}
is_uefi_mode(){
[[ -d /sys/firmware/efi ]]
}
setup_qemu_config(){
log "Setting up QEMU configuration"
if is_uefi_mode;then
UEFI_OPTS="-bios /usr/share/ovmf/OVMF.fd"
log "UEFI mode detected"
else
UEFI_OPTS=""
log "Legacy BIOS mode"
fi
KVM_OPTS="-enable-kvm"
CPU_OPTS="-cpu host"
log "Using KVM acceleration"
local available_cores available_ram_mb
available_cores=$(nproc)
available_ram_mb=$(free -m|awk '/^Mem:/{print $2}')
log "Available cores: $available_cores, Available RAM: ${available_ram_mb}MB"
if [[ -n $QEMU_CORES_OVERRIDE ]];then
QEMU_CORES="$QEMU_CORES_OVERRIDE"
log "Using user-specified cores: $QEMU_CORES"
else
QEMU_CORES=$available_cores
[[ $QEMU_CORES -lt $MIN_CPU_CORES ]]&&QEMU_CORES=$MIN_CPU_CORES
fi
if [[ -n $QEMU_RAM_OVERRIDE ]];then
QEMU_RAM="$QEMU_RAM_OVERRIDE"
log "Using user-specified RAM: ${QEMU_RAM}MB"
if [[ $QEMU_RAM -gt $((available_ram_mb-QEMU_MIN_RAM_RESERVE)) ]];then
print_warning "Requested QEMU RAM (${QEMU_RAM}MB) may exceed safe limits (available: ${available_ram_mb}MB)"
fi
else
QEMU_RAM=$((available_ram_mb-QEMU_MIN_RAM_RESERVE))
[[ $QEMU_RAM -lt $MIN_QEMU_RAM ]]&&QEMU_RAM=$MIN_QEMU_RAM
fi
log "QEMU config: $QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM"
load_virtio_mapping
DRIVE_ARGS=""
local disk
for disk in "${!VIRTIO_MAP[@]}";do
DRIVE_ARGS="$DRIVE_ARGS -drive file=$disk,format=raw,media=disk,if=virtio"
done
log "Drive args: $DRIVE_ARGS"
}
_signal_process(){
local pid="$1"
local signal="$2"
local message="$3"
if kill -0 "$pid" 2>/dev/null;then
log "$message"
kill "-$signal" "$pid" 2>/dev/null||true
fi
}
_kill_processes_by_pattern(){
local pattern="$1"
local pids
pids=$(pgrep -f "$pattern" 2>/dev/null||true)
if [[ -n $pids ]];then
log "Found processes matching '$pattern': $pids"
for pid in $pids;do
_signal_process "$pid" "TERM" "Sending TERM to process $pid"
done
sleep 3
for pid in $pids;do
_signal_process "$pid" "9" "Force killing process $pid"
done
sleep 1
fi
pkill -TERM "$pattern" 2>/dev/null||true
sleep 1
pkill -9 "$pattern" 2>/dev/null||true
}
_stop_mdadm_arrays(){
if ! command -v mdadm &>/dev/null;then
return 0
fi
log "Stopping mdadm arrays..."
mdadm --stop --scan 2>/dev/null||true
for md in /dev/md*;do
if [[ -b $md ]];then
mdadm --stop "$md" 2>/dev/null||true
fi
done
}
_deactivate_lvm(){
if ! command -v vgchange &>/dev/null;then
return 0
fi
log "Deactivating LVM volume groups..."
vgchange -an 2>/dev/null||true
if command -v vgs &>/dev/null;then
while IFS= read -r vg;do
if [[ -n $vg ]];then vgchange -an "$vg" 2>/dev/null||true;fi
done < <(vgs --noheadings -o vg_name 2>/dev/null)
fi
}
_unmount_drive_filesystems(){
[[ -z ${DRIVES[*]} ]]&&return 0
log "Unmounting filesystems on target drives..."
for drive in "${DRIVES[@]}";do
if command -v findmnt &>/dev/null;then
while IFS= read -r mountpoint;do
[[ -z $mountpoint ]]&&continue
log "Unmounting $mountpoint"
umount -f "$mountpoint" 2>/dev/null||true
done < <(findmnt -rn -o TARGET "$drive"* 2>/dev/null)
else
local drive_name
drive_name=$(basename "$drive")
while IFS= read -r mountpoint;do
[[ -z $mountpoint ]]&&continue
log "Unmounting $mountpoint"
umount -f "$mountpoint" 2>/dev/null||true
done < <(mount|grep -E "(^|/)$drive_name"|awk '{print $3}')
fi
done
}
_kill_drive_holders(){
[[ -z ${DRIVES[*]} ]]&&return 0
log "Checking for processes using drives..."
for drive in "${DRIVES[@]}";do
if command -v lsof &>/dev/null;then
while IFS= read -r pid;do
[[ -z $pid ]]&&continue
_signal_process "$pid" "9" "Killing process $pid using $drive"
done < <(lsof "$drive" 2>/dev/null|awk 'NR>1 {print $2}'|sort -u)
fi
if command -v fuser &>/dev/null;then
fuser -k "$drive" 2>/dev/null||true
fi
done
}
release_drives(){
log "Releasing drives from locks..."
_kill_processes_by_pattern "qemu-system-x86"
_stop_mdadm_arrays
_deactivate_lvm
_unmount_drive_filesystems
sleep 2
_kill_drive_holders
log "Drives released"
}
install_proxmox(){
local qemu_config_file
qemu_config_file=$(mktemp)
(setup_qemu_config
cat >"$qemu_config_file" <<EOF
QEMU_CORES=$QEMU_CORES
QEMU_RAM=$QEMU_RAM
UEFI_MODE=$(is_uefi_mode&&echo "yes"||echo "no")
KVM_OPTS='$KVM_OPTS'
UEFI_OPTS='$UEFI_OPTS'
CPU_OPTS='$CPU_OPTS'
DRIVE_ARGS='$DRIVE_ARGS'
EOF
if [[ ! -f "./pve-autoinstall.iso" ]];then
print_error "Autoinstall ISO not found!"
exit 1
fi
release_drives) \
&
local prep_pid=$!
local timeout=10
while [[ ! -s $qemu_config_file ]]&&((timeout>0));do
sleep 0.1
((timeout--))
done
if [[ -s $qemu_config_file ]];then
source "$qemu_config_file"
rm -f "$qemu_config_file"
fi
show_progress $prep_pid "Starting QEMU ($QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM)" "QEMU started ($QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM)"
if [[ $UEFI_MODE == "yes" ]];then
live_log_subtask "UEFI mode detected"
else
live_log_subtask "Legacy BIOS mode"
fi
live_log_subtask "KVM acceleration enabled"
live_log_subtask "Configured $QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM"
qemu-system-x86_64 $KVM_OPTS $UEFI_OPTS \
$CPU_OPTS -smp "$QEMU_CORES" -m "$QEMU_RAM" \
-boot d -cdrom ./pve-autoinstall.iso \
$DRIVE_ARGS -no-reboot -display none >qemu_install.log 2>&1&
local qemu_pid=$!
sleep 2
if ! kill -0 $qemu_pid 2>/dev/null;then
log "ERROR: QEMU failed to start"
log "QEMU install log:"
cat qemu_install.log >>"$LOG_FILE" 2>&1
exit 1
fi
show_progress "$qemu_pid" "Installing Proxmox VE" "Proxmox VE installed"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: QEMU installation failed with exit code $exit_code"
log "QEMU install log:"
cat qemu_install.log >>"$LOG_FILE" 2>&1
exit 1
fi
}
boot_proxmox_with_port_forwarding(){
setup_qemu_config
if ! check_port_available "$SSH_PORT";then
print_error "Port $SSH_PORT is already in use"
log "ERROR: Port $SSH_PORT is already in use"
exit 1
fi
nohup qemu-system-x86_64 $KVM_OPTS $UEFI_OPTS \
$CPU_OPTS -device e1000,netdev=net0 \
-netdev user,id=net0,hostfwd=tcp::5555-:22 \
-smp "$QEMU_CORES" -m "$QEMU_RAM" \
$DRIVE_ARGS -display none > \
qemu_output.log 2>&1&
QEMU_PID=$!
(local timeout=300
local elapsed=0
while ((elapsed<timeout));do
if exec 3<>/dev/tcp/localhost/5555 2>/dev/null;then
exec 3<&-
exit 0
fi 2>/dev/null
sleep 3
((elapsed+=3))
done
exit 1) 2> \
/dev/null&
local wait_pid=$!
show_progress $wait_pid "Booting installed Proxmox" "Proxmox booted"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: Timeout waiting for SSH port"
log "QEMU output log:"
cat qemu_output.log >>"$LOG_FILE" 2>&1
return 1
fi
wait_for_ssh_ready 120||{
log "ERROR: SSH connection failed"
log "QEMU output log:"
cat qemu_output.log >>"$LOG_FILE" 2>&1
return 1
}
}
_download_templates_parallel(){
local -a templates=("$@")
local input_file
input_file=$(mktemp)
for entry in "${templates[@]}";do
local local_path="${entry%%:*}"
local remote_name="${entry#*:}"
local url="$GITHUB_BASE_URL/templates/$remote_name.tmpl"
echo "$url"
echo "  out=$local_path"
done >"$input_file"
log "Downloading ${#templates[@]} templates in parallel"
if command -v aria2c &>/dev/null;then
if aria2c -q \
-j 16 \
--max-connection-per-server=4 \
--file-allocation=none \
--max-tries=3 \
--retry-wait=2 \
--timeout=30 \
--connect-timeout=10 \
-i "$input_file" >> \
"$LOG_FILE" 2>&1;then
rm -f "$input_file"
return 0
fi
log "WARNING: aria2c failed, falling back to sequential download"
fi
rm -f "$input_file"
for entry in "${templates[@]}";do
local local_path="${entry%%:*}"
local remote_name="${entry#*:}"
if ! download_template "$local_path" "$remote_name";then
return 1
fi
done
return 0
}
make_templates(){
log "Starting template preparation"
mkdir -p ./templates
local interfaces_template="interfaces.${BRIDGE_MODE:-internal}"
log "Using interfaces template: $interfaces_template"
local proxmox_sources_template="proxmox.sources"
case "${PVE_REPO_TYPE:-no-subscription}" in
enterprise)proxmox_sources_template="proxmox-enterprise.sources";;
test)proxmox_sources_template="proxmox-test.sources"
esac
log "Using repository template: $proxmox_sources_template"
local -a template_list=(
"./templates/99-proxmox.conf:99-proxmox.conf"
"./templates/hosts:hosts"
"./templates/debian.sources:debian.sources"
"./templates/proxmox.sources:$proxmox_sources_template"
"./templates/sshd_config:sshd_config"
"./templates/resolv.conf:resolv.conf"
"./templates/interfaces:$interfaces_template"
"./templates/locale.sh:locale.sh"
"./templates/default-locale:default-locale"
"./templates/environment:environment"
"./templates/zshrc:zshrc"
"./templates/p10k.zsh:p10k.zsh"
"./templates/fastfetch.sh:fastfetch.sh"
"./templates/bat-config:bat-config"
"./templates/chrony:chrony"
"./templates/50unattended-upgrades:50unattended-upgrades"
"./templates/20auto-upgrades:20auto-upgrades"
"./templates/cpupower.service:cpupower.service"
"./templates/60-io-scheduler.rules:60-io-scheduler.rules"
"./templates/remove-subscription-nag.sh:remove-subscription-nag.sh"
"./templates/configure-zfs-arc.sh:configure-zfs-arc.sh"
"./templates/zfs-scrub.service:zfs-scrub.service"
"./templates/zfs-scrub.timer:zfs-scrub.timer"
"./templates/letsencrypt-deploy-hook.sh:letsencrypt-deploy-hook.sh"
"./templates/letsencrypt-firstboot.sh:letsencrypt-firstboot.sh"
"./templates/letsencrypt-firstboot.service:letsencrypt-firstboot.service"
"./templates/disable-openssh.service:disable-openssh.service"
"./templates/nftables.conf:nftables.conf"
"./templates/fail2ban-jail.local:fail2ban-jail.local"
"./templates/fail2ban-proxmox.conf:fail2ban-proxmox.conf"
"./templates/apparmor-grub.cfg:apparmor-grub.cfg"
"./templates/auditd-rules:auditd-rules"
"./templates/aide-check.service:aide-check.service"
"./templates/aide-check.timer:aide-check.timer"
"./templates/chkrootkit-scan.service:chkrootkit-scan.service"
"./templates/chkrootkit-scan.timer:chkrootkit-scan.timer"
"./templates/lynis-audit.service:lynis-audit.service"
"./templates/lynis-audit.timer:lynis-audit.timer"
"./templates/needrestart.conf:needrestart.conf"
"./templates/vnstat.conf:vnstat.conf"
"./templates/netdata.conf:netdata.conf"
"./templates/prometheus-node-exporter:prometheus-node-exporter"
"./templates/proxmox-metrics.sh:proxmox-metrics.sh"
"./templates/proxmox-metrics.cron:proxmox-metrics.cron"
"./templates/yazi-theme.toml:yazi-theme.toml"
"./templates/network-ringbuffer.service:network-ringbuffer.service"
"./templates/validation.sh:validation.sh")
(_download_templates_parallel "${template_list[@]}"||exit 1) > \
/dev/null 2>&1&
if ! show_progress $! "Downloading template files";then
log "ERROR: Failed to download template files"
exit 1
fi
(apply_common_template_vars "./templates/hosts"
apply_common_template_vars "./templates/interfaces"
postprocess_interfaces_ipv6 "./templates/interfaces"
apply_common_template_vars "./templates/resolv.conf"
apply_template_vars "./templates/cpupower.service" "CPU_GOVERNOR=${CPU_GOVERNOR:-performance}"
apply_common_template_vars "./templates/locale.sh"
apply_common_template_vars "./templates/default-locale"
apply_common_template_vars "./templates/environment") \
&
show_progress $! "Modifying template files"
}
configure_base_system(){
(local -a copy_pids=()
remote_copy "templates/hosts" "/etc/hosts" >/dev/null 2>&1&
copy_pids+=($!)
remote_copy "templates/interfaces" "/etc/network/interfaces" >/dev/null 2>&1&
copy_pids+=($!)
remote_copy "templates/99-proxmox.conf" "/etc/sysctl.d/99-proxmox.conf" >/dev/null 2>&1&
copy_pids+=($!)
remote_copy "templates/debian.sources" "/etc/apt/sources.list.d/debian.sources" >/dev/null 2>&1&
copy_pids+=($!)
remote_copy "templates/proxmox.sources" "/etc/apt/sources.list.d/proxmox.sources" >/dev/null 2>&1&
copy_pids+=($!)
remote_copy "templates/resolv.conf" "/etc/resolv.conf" >/dev/null 2>&1&
copy_pids+=($!)
for pid in "${copy_pids[@]}";do
wait "$pid"||exit 1
done) > \
/dev/null 2>&1&
show_progress $! "Copying configuration files" "Configuration files copied"
(remote_exec "[ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak"||exit 1
remote_exec "echo '$PVE_HOSTNAME' > /etc/hostname"||exit 1
remote_exec "systemctl disable --now rpcbind rpcbind.socket 2>/dev/null"||true) > \
/dev/null 2>&1&
show_progress $! "Applying basic system settings" "Basic system settings applied"
(remote_copy "templates/configure-zfs-arc.sh" "/tmp/configure-zfs-arc.sh"||exit 1
remote_exec "chmod +x /tmp/configure-zfs-arc.sh && /tmp/configure-zfs-arc.sh && rm -f /tmp/configure-zfs-arc.sh"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring ZFS ARC memory limits" "ZFS ARC memory limits configured"
log "configure_base_system: PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
if [[ ${PVE_REPO_TYPE:-no-subscription} == "enterprise" ]];then
log "configure_base_system: configuring enterprise repository"
run_remote "Configuring enterprise repository" '
            for repo_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
                [ -f "$repo_file" ] || continue
                if grep -q "pve-no-subscription\|pvetest" "$repo_file" 2>/dev/null; then
                    mv "$repo_file" "${repo_file}.disabled"
                fi
            done
        ' "Enterprise repository configured"
if [[ -n $PVE_SUBSCRIPTION_KEY ]];then
log "configure_base_system: registering subscription key"
run_remote "Registering subscription key" \
"pvesubscription set '$PVE_SUBSCRIPTION_KEY' 2>/dev/null || true" \
"Subscription key registered"
fi
else
log "configure_base_system: configuring ${PVE_REPO_TYPE:-no-subscription} repository"
run_remote "Configuring ${PVE_REPO_TYPE:-no-subscription} repository" '
            for repo_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
                [ -f "$repo_file" ] || continue
                if grep -q "enterprise.proxmox.com" "$repo_file" 2>/dev/null; then
                    mv "$repo_file" "${repo_file}.disabled"
                fi
            done

            if [ -f /etc/apt/sources.list ] && grep -q "enterprise.proxmox.com" /etc/apt/sources.list 2>/dev/null; then
                sed -i "s|^deb.*enterprise.proxmox.com|# &|g" /etc/apt/sources.list
            fi
        ' "Repository configured"
fi
install_base_packages
local locale_name="${LOCALE%%.UTF-8}"
run_remote "Configuring UTF-8 locales" "
        # Enable user's selected locale
        sed -i 's/# $locale_name.UTF-8/$locale_name.UTF-8/' /etc/locale.gen
        # Also enable en_US as fallback (many tools expect it)
        sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
        locale-gen
        update-locale LANG=$LOCALE LC_ALL=$LOCALE
    " "UTF-8 locales configured"
(remote_copy "templates/locale.sh" "/etc/profile.d/locale.sh"||exit 1
remote_exec "chmod +x /etc/profile.d/locale.sh"||exit 1
remote_copy "templates/default-locale" "/etc/default/locale"||exit 1
remote_copy "templates/environment" "/etc/environment"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Installing locale configuration files" "Locale files installed"
(remote_copy "templates/fastfetch.sh" "/etc/profile.d/fastfetch.sh"||exit 1
remote_exec "chmod +x /etc/profile.d/fastfetch.sh"||exit 1
remote_exec "grep -q 'profile.d/fastfetch.sh' /etc/bash.bashrc || echo '[ -f /etc/profile.d/fastfetch.sh ] && . /etc/profile.d/fastfetch.sh' >> /etc/bash.bashrc"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring fastfetch" "Fastfetch configured"
(remote_exec "mkdir -p /root/.config/bat"||exit 1
remote_copy "templates/bat-config" "/root/.config/bat/config"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring bat" "Bat configured"
}
configure_shell(){
if [[ $SHELL_TYPE == "zsh" ]];then
run_remote "Installing Oh-My-Zsh" '
            export RUNZSH=no
            export CHSH=no
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        ' "Oh-My-Zsh installed"
run_remote "Installing ZSH theme and plugins" '
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/.oh-my-zsh/custom/themes/powerlevel10k &
            git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions &
            git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting &
            wait
        ' "ZSH theme and plugins installed"
(remote_copy "templates/zshrc" "/root/.zshrc"||exit 1
remote_copy "templates/p10k.zsh" "/root/.p10k.zsh"||exit 1
remote_exec "chsh -s /bin/zsh root"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring ZSH" "ZSH with Powerlevel10k configured"
else
add_log "$CLR_GRAY├─$CLR_RESET Default shell: Bash $CLR_CYAN✓$CLR_RESET"
fi
}
configure_system_services(){
(remote_exec "systemctl stop chrony"||true
remote_copy "templates/chrony" "/etc/chrony/chrony.conf"||exit 1
remote_exec "systemctl enable chrony"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring chrony" "Chrony configured"
(remote_copy "templates/50unattended-upgrades" "/etc/apt/apt.conf.d/50unattended-upgrades"||exit 1
remote_copy "templates/20auto-upgrades" "/etc/apt/apt.conf.d/20auto-upgrades"||exit 1
remote_exec "systemctl enable unattended-upgrades"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring Unattended Upgrades" "Unattended Upgrades configured"
run_remote "Configuring nf_conntrack" '
        if ! grep -q "nf_conntrack" /etc/modules 2>/dev/null; then
            echo "nf_conntrack" >> /etc/modules
        fi
    ' "nf_conntrack configured"
local governor="${CPU_GOVERNOR:-performance}"
(remote_copy "templates/cpupower.service" "/etc/systemd/system/cpupower.service"||exit 1
remote_exec "
            systemctl daemon-reload
            systemctl enable cpupower.service
            cpupower frequency-set -g '$governor' 2>/dev/null || true
        "||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring CPU governor ($governor)" "CPU governor configured"
(remote_copy "templates/60-io-scheduler.rules" "/etc/udev/rules.d/60-io-scheduler.rules"||exit 1
remote_exec "udevadm control --reload-rules && udevadm trigger"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring I/O scheduler" "I/O scheduler configured"
if [[ ${PVE_REPO_TYPE:-no-subscription} != "enterprise" ]];then
log "configure_system_services: removing subscription notice (non-enterprise)"
(remote_copy "templates/remove-subscription-nag.sh" "/tmp/remove-subscription-nag.sh"||exit 1
remote_exec "chmod +x /tmp/remove-subscription-nag.sh && /tmp/remove-subscription-nag.sh && rm -f /tmp/remove-subscription-nag.sh"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Removing Proxmox subscription notice" "Subscription notice removed"
fi
}
configure_tailscale(){
if [[ $INSTALL_TAILSCALE != "yes" ]];then
return 0
fi
run_remote "Starting Tailscale" '
        systemctl enable tailscaled
        systemctl start tailscaled
        # Wait for tailscaled socket to be ready (up to 3s)
        for i in {1..3}; do
          tailscale status &>/dev/null && break
          sleep 1
        done
    ' "Tailscale started"
if [[ -n $TAILSCALE_AUTH_KEY ]];then
local tmp_ip tmp_hostname
tmp_ip=$(mktemp)
tmp_hostname=$(mktemp)
trap "rm -f '$tmp_ip' '$tmp_hostname'" RETURN
(if
[[ $TAILSCALE_SSH == "yes" ]]
then
remote_exec "tailscale up --authkey='$TAILSCALE_AUTH_KEY' --ssh"||exit 1
else
remote_exec "tailscale up --authkey='$TAILSCALE_AUTH_KEY'"||exit 1
fi
remote_exec "tailscale status --json | jq -r '[(.Self.TailscaleIPs[0] // \"pending\"), (.Self.DNSName // \"\" | rtrimstr(\".\"))] | @tsv'" 2>/dev/null|{
IFS=$'\t' read -r ip hostname
echo "$ip" >"$tmp_ip"
echo "$hostname" >"$tmp_hostname"
}||true) > \
/dev/null 2>&1&
show_progress $! "Authenticating Tailscale"
TAILSCALE_IP=$(cat "$tmp_ip" 2>/dev/null||echo "pending")
TAILSCALE_HOSTNAME=$(cat "$tmp_hostname" 2>/dev/null||echo "")
printf "\033[1A\r%s✓ Tailscale authenticated. IP: %s%s                              \n" "$CLR_CYAN" "$TAILSCALE_IP" "$CLR_RESET"
if [[ $TAILSCALE_WEBUI == "yes" ]];then
remote_exec "tailscale serve --bg --https=443 https://127.0.0.1:8006" >/dev/null 2>&1&
show_progress $! "Configuring Tailscale Serve" "Proxmox Web UI available via Tailscale Serve"
fi
if [[ ${FIREWALL_MODE:-standard} == "stealth" ]];then
log "Deploying disable-openssh.service (FIREWALL_MODE=$FIREWALL_MODE)"
(log "Using pre-downloaded disable-openssh.service, size: $(wc -c <./templates/disable-openssh.service 2>/dev/null||echo 'failed')"
remote_copy "templates/disable-openssh.service" "/etc/systemd/system/disable-openssh.service"||exit 1
log "Copied disable-openssh.service to VM"
remote_exec "systemctl daemon-reload && systemctl enable disable-openssh.service" >/dev/null 2>&1||exit 1
log "Enabled disable-openssh.service") \
&
show_progress $! "Configuring OpenSSH disable on boot" "OpenSSH disable configured"
else
log "Skipping disable-openssh.service (FIREWALL_MODE=${FIREWALL_MODE:-standard})"
fi
else
TAILSCALE_IP="not authenticated"
TAILSCALE_HOSTNAME=""
add_log "$CLR_GRAY├─$CLR_RESET $CLR_YELLOW⚠️$CLR_RESET Tailscale installed but not authenticated"
add_log "$CLR_GRAY│$CLR_RESET   ${CLR_GRAY}After reboot: tailscale up --ssh$CLR_RESET"
fi
}
_generate_port_rules(){
local mode="$1"
local rules=""
case "$mode" in
stealth)rules="# Stealth mode: all public ports blocked
        # Access only via Tailscale VPN or VM bridges"
;;
strict)rules="# SSH access (port 22)
        tcp dport 22 ct state new accept"
;;
standard)rules="# SSH access (port 22)
        tcp dport 22 ct state new accept

        # Proxmox Web UI (port 8006)
        tcp dport 8006 ct state new accept"
;;
*)log "WARNING: Unknown firewall mode: $mode, using standard"
rules="# SSH access (port 22)
        tcp dport 22 ct state new accept

        # Proxmox Web UI (port 8006)
        tcp dport 8006 ct state new accept"
esac
echo "$rules"
}
_generate_bridge_input_rules(){
local mode="${BRIDGE_MODE:-internal}"
local rules=""
case "$mode" in
internal)rules='# Allow traffic from internal bridge (vmbr0 - private NAT network)
        iifname "vmbr0" accept'
;;
external)rules='# Allow traffic from external bridge (vmbr1 - public IPs)
        iifname "vmbr1" accept'
;;
both)rules='# Allow traffic from internal bridge (vmbr0 - private NAT network)
        iifname "vmbr0" accept

        # Allow traffic from external bridge (vmbr1 - public IPs)
        iifname "vmbr1" accept'
;;
*)log "WARNING: Unknown bridge mode: $mode, using internal"
rules='# Allow traffic from internal bridge (vmbr0 - private NAT network)
        iifname "vmbr0" accept'
esac
echo "$rules"
}
_generate_bridge_forward_rules(){
local mode="${BRIDGE_MODE:-internal}"
local rules=""
case "$mode" in
internal)rules='# Allow forwarding for internal bridge (VM traffic)
        iifname "vmbr0" accept
        oifname "vmbr0" accept'
;;
external)rules='# Allow forwarding for external bridge (VM traffic)
        iifname "vmbr1" accept
        oifname "vmbr1" accept'
;;
both)rules='# Allow forwarding for both bridges (VM traffic)
        iifname "vmbr0" accept
        iifname "vmbr1" accept
        oifname "vmbr0" accept
        oifname "vmbr1" accept'
;;
*)rules='# Allow forwarding for internal bridge (VM traffic)
        iifname "vmbr0" accept
        oifname "vmbr0" accept'
esac
echo "$rules"
}
_generate_tailscale_rules(){
if [[ $INSTALL_TAILSCALE == "yes" ]];then
echo '# Allow Tailscale VPN interface
        iifname "tailscale0" accept'
else
echo "# Tailscale not installed"
fi
}
_generate_nat_rules(){
local mode="${BRIDGE_MODE:-internal}"
local subnet="${PRIVATE_SUBNET:-10.0.0.0/24}"
local rules=""
case "$mode" in
internal|both)rules="# Masquerade traffic from private subnet to internet
        oifname != \"lo\" ip saddr $subnet masquerade"
local subnet_base="${subnet%%.*}"
case "$subnet_base" in
10)
;;
172)
;;
192)
esac
;;
external)rules="# External mode: no NAT needed (VMs have public IPs)"
esac
echo "$rules"
}
_config_nftables(){
remote_exec '
    update-alternatives --set iptables /usr/sbin/iptables-nft 2>/dev/null || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-nft 2>/dev/null || true
  '||true
local template_content
template_content=$(cat "./templates/nftables.conf")
local port_rules bridge_input_rules bridge_forward_rules nat_rules tailscale_rules
port_rules=$(_generate_port_rules "$FIREWALL_MODE")
bridge_input_rules=$(_generate_bridge_input_rules)
bridge_forward_rules=$(_generate_bridge_forward_rules)
nat_rules=$(_generate_nat_rules)
tailscale_rules=$(_generate_tailscale_rules)
local nftables_conf="$template_content"
nftables_conf="${nftables_conf//\{\{BRIDGE_MODE\}\}/$BRIDGE_MODE}"
nftables_conf=$(echo "$nftables_conf"|sed "/# === FIREWALL_RULES_START ===/,/# === FIREWALL_RULES_END ===/c\\
        # === FIREWALL_RULES_START ===\\
$port_rules\\
        # === FIREWALL_RULES_END ===")
nftables_conf=$(echo "$nftables_conf"|sed "/# === BRIDGE_INPUT_RULES ===/c\\
$bridge_input_rules")
nftables_conf=$(echo "$nftables_conf"|sed "/# === TAILSCALE_RULES ===/c\\
$tailscale_rules")
nftables_conf=$(echo "$nftables_conf"|sed "/# === BRIDGE_FORWARD_RULES ===/c\\
$bridge_forward_rules")
nftables_conf=$(echo "$nftables_conf"|sed "/# === NAT_RULES ===/c\\
$nat_rules")
echo "$nftables_conf" >"./templates/nftables.conf.generated"
log "Generated nftables config:"
log "  Bridge mode: $BRIDGE_MODE"
log "  Firewall mode: $FIREWALL_MODE"
log "  Private subnet: ${PRIVATE_SUBNET:-N/A}"
remote_copy "templates/nftables.conf.generated" "/etc/nftables.conf"||return 1
remote_exec "nft -c -f /etc/nftables.conf"||{
log "ERROR: nftables config syntax validation failed"
return 1
}
remote_exec "systemctl enable nftables"||return 1
rm -f "./templates/nftables.conf.generated"
}
configure_firewall(){
if [[ $INSTALL_FIREWALL != "yes" ]];then
log "Skipping firewall configuration (INSTALL_FIREWALL=$INSTALL_FIREWALL)"
return 0
fi
log "Configuring nftables firewall (mode: $FIREWALL_MODE, bridge: $BRIDGE_MODE)"
(_config_nftables||exit 1) > \
/dev/null 2>&1&
local mode_display=""
case "$FIREWALL_MODE" in
stealth)mode_display="stealth (Tailscale only)";;
strict)mode_display="strict (SSH only)";;
standard)mode_display="standard (SSH + Web UI)";;
*)mode_display="$FIREWALL_MODE"
esac
show_progress $! "Configuring nftables firewall" "Firewall configured ($mode_display)"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Firewall setup failed"
return 0
fi
}
_config_fail2ban(){
apply_template_vars "./templates/fail2ban-jail.local" \
"EMAIL=$EMAIL" \
"HOSTNAME=$PVE_HOSTNAME"
remote_copy "templates/fail2ban-jail.local" "/etc/fail2ban/jail.local"||return 1
remote_copy "templates/fail2ban-proxmox.conf" "/etc/fail2ban/filter.d/proxmox.conf"||return 1
remote_exec "systemctl enable fail2ban"||return 1
}
_config_apparmor(){
remote_exec '
    if ! grep -q "Y" /sys/module/apparmor/parameters/enabled 2>/dev/null; then
      if ! grep -q "apparmor=1" /etc/default/grub 2>/dev/null; then
        mkdir -p /etc/default/grub.d
      fi
    fi
  '
remote_exec 'grep -q "Y" /sys/module/apparmor/parameters/enabled 2>/dev/null'||remote_copy "templates/apparmor-grub.cfg" "/etc/default/grub.d/apparmor.cfg"
remote_exec '
    # Update GRUB if config was added
    if [[ -f /etc/default/grub.d/apparmor.cfg ]]; then
      update-grub 2>/dev/null || true
    fi

    # Enable AppArmor to start on boot (will activate after reboot)
    systemctl enable apparmor.service
  '||return 1
}
_config_auditd(){
remote_copy "templates/auditd-rules" "/etc/audit/rules.d/proxmox.rules"||return 1
remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/audit

    # Configure auditd.conf for better log retention
    sed -i "s/^max_log_file = .*/max_log_file = 50/" /etc/audit/auditd.conf 2>/dev/null || true
    sed -i "s/^num_logs = .*/num_logs = 10/" /etc/audit/auditd.conf 2>/dev/null || true
    sed -i "s/^max_log_file_action = .*/max_log_file_action = ROTATE/" /etc/audit/auditd.conf 2>/dev/null || true

    # Load new rules
    augenrules --load 2>/dev/null || true

    # Enable auditd to start on boot (will activate after reboot)
    systemctl enable auditd
  '||return 1
}
_config_aide(){
remote_copy "templates/aide-check.service" "/etc/systemd/system/aide-check.service"||return 1
remote_copy "templates/aide-check.timer" "/etc/systemd/system/aide-check.timer"||return 1
remote_exec '
    # Initialize AIDE database (this takes a while)
    echo "Initializing AIDE database (this may take several minutes)..."
    aideinit -y -f 2>/dev/null || true

    # Move new database to active location
    if [[ -f /var/lib/aide/aide.db.new ]]; then
      mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi

    # Enable daily integrity check timer (will activate after reboot)
    systemctl daemon-reload
    systemctl enable aide-check.timer
  '||return 1
}
_config_chkrootkit(){
remote_copy "templates/chkrootkit-scan.service" "/etc/systemd/system/chkrootkit-scan.service"||return 1
remote_copy "templates/chkrootkit-scan.timer" "/etc/systemd/system/chkrootkit-scan.timer"||return 1
remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/chkrootkit

    # Enable weekly scan timer (will activate after reboot)
    systemctl daemon-reload
    systemctl enable chkrootkit-scan.timer
  '||return 1
}
_config_lynis(){
remote_copy "templates/lynis-audit.service" "/etc/systemd/system/lynis-audit.service"||return 1
remote_copy "templates/lynis-audit.timer" "/etc/systemd/system/lynis-audit.timer"||return 1
remote_exec '
    # Ensure log directory exists
    mkdir -p /var/log/lynis

    # Enable weekly audit timer (will activate after reboot)
    systemctl daemon-reload
    systemctl enable lynis-audit.timer
  '||return 1
}
_config_needrestart(){
remote_copy "templates/needrestart.conf" "/etc/needrestart/conf.d/50-autorestart.conf"||return 1
}
_config_ringbuffer(){
local ringbuffer_interface="${DEFAULT_INTERFACE:-eth0}"
apply_template_vars "templates/network-ringbuffer.service" "RINGBUFFER_INTERFACE=$ringbuffer_interface"
remote_copy "templates/network-ringbuffer.service" "/etc/systemd/system/network-ringbuffer.service"||return 1
remote_exec '
    # Enable service for boot (will activate after reboot)
    systemctl daemon-reload
    systemctl enable network-ringbuffer.service
  '||return 1
}
_config_vnstat(){
local iface="${INTERFACE_NAME:-eth0}"
apply_template_vars "templates/vnstat.conf" "INTERFACE_NAME=$iface"
remote_copy "templates/vnstat.conf" "/etc/vnstat.conf"||return 1
remote_exec "
    # Ensure database directory exists
    mkdir -p /var/lib/vnstat

    # Add main interface to monitor
    vnstat --add -i '$iface' 2>/dev/null || true

    # Also monitor bridge interfaces if they exist
    for bridge in vmbr0 vmbr1; do
      if ip link show \"\$bridge\" &>/dev/null; then
        vnstat --add -i \"\$bridge\" 2>/dev/null || true
      fi
    done

    # Enable vnstat to start on boot (don't start now - will activate after reboot)
    systemctl enable vnstat
  "||return 1
}
_config_prometheus(){
remote_exec '
    mkdir -p /var/lib/prometheus/node-exporter
    chown prometheus:prometheus /var/lib/prometheus/node-exporter
  '||return 1
remote_copy "templates/prometheus-node-exporter" "/etc/default/prometheus-node-exporter"||return 1
remote_copy "templates/proxmox-metrics.sh" "/usr/local/bin/proxmox-metrics.sh"||return 1
remote_exec "chmod +x /usr/local/bin/proxmox-metrics.sh"||return 1
remote_copy "templates/proxmox-metrics.cron" "/etc/cron.d/proxmox-metrics"||return 1
remote_exec "/usr/local/bin/proxmox-metrics.sh" >/dev/null 2>&1||log "WARNING: Initial metrics collection failed (non-fatal)"
remote_exec '
    systemctl daemon-reload
    systemctl enable prometheus-node-exporter
  '||return 1
log "Prometheus node exporter listening on :9100 with textfile collector"
}
_config_netdata(){
local bind_to="127.0.0.1"
if [[ $INSTALL_TAILSCALE == "yes" ]];then
bind_to="127.0.0.1 100.*"
fi
apply_template_vars "templates/netdata.conf" "NETDATA_BIND_TO=$bind_to"
remote_copy "templates/netdata.conf" "/etc/netdata/netdata.conf"||return 1
remote_exec '
    systemctl daemon-reload
    systemctl enable netdata
  '||return 1
}
configure_netdata(){
if [[ $INSTALL_NETDATA != "yes" ]];then
log "Skipping netdata (not requested)"
return 0
fi
log "Configuring netdata"
(_config_netdata||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring netdata" "netdata configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: netdata setup failed"
return 0
fi
}
_install_yazi(){
run_remote "Installing yazi" '
    set -e
    # Get latest yazi version and download
    YAZI_VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep "tag_name" | cut -d "\"" -f 4 | sed "s/^v//")
    curl -sL "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip

    # Extract and install
    unzip -q /tmp/yazi.zip -d /tmp/
    chmod +x /tmp/yazi-x86_64-unknown-linux-gnu/yazi
    mv /tmp/yazi-x86_64-unknown-linux-gnu/yazi /usr/local/bin/
    rm -rf /tmp/yazi.zip /tmp/yazi-x86_64-unknown-linux-gnu
  ' "Yazi installed"
}
_config_yazi(){
remote_exec 'mkdir -p /root/.config/yazi'||return 1
remote_copy "templates/yazi-theme.toml" "/root/.config/yazi/theme.toml"||return 1
}
configure_yazi(){
if [[ $INSTALL_YAZI != "yes" ]];then
log "Skipping yazi (not requested)"
return 0
fi
log "Installing and configuring yazi"
(_install_yazi||exit 1
_config_yazi||exit 1) > \
/dev/null 2>&1&
show_progress $! "Installing and configuring yazi" "Yazi configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Yazi setup failed"
return 0
fi
}
_config_nvim(){
remote_exec '
    update-alternatives --install /usr/bin/vi vi /usr/bin/nvim 60
    update-alternatives --install /usr/bin/vim vim /usr/bin/nvim 60
    update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 60

    # Set nvim as default
    update-alternatives --set vi /usr/bin/nvim
    update-alternatives --set vim /usr/bin/nvim
    update-alternatives --set editor /usr/bin/nvim
  '||return 1
}
configure_ssl_certificate(){
log "configure_ssl_certificate: SSL_TYPE=$SSL_TYPE"
if [[ $SSL_TYPE != "letsencrypt" ]];then
log "configure_ssl_certificate: skipping (self-signed)"
return 0
fi
local cert_domain="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
log "configure_ssl_certificate: domain=$cert_domain, email=$EMAIL"
if ! apply_template_vars "./templates/letsencrypt-firstboot.sh" \
"CERT_DOMAIN=$cert_domain" \
"CERT_EMAIL=$EMAIL";then
log "ERROR: Failed to apply template variables to letsencrypt-firstboot.sh"
exit 1
fi
if ! remote_copy "./templates/letsencrypt-deploy-hook.sh" "/tmp/letsencrypt-deploy-hook.sh";then
log "ERROR: Failed to copy letsencrypt-deploy-hook.sh"
exit 1
fi
if ! remote_copy "./templates/letsencrypt-firstboot.sh" "/tmp/letsencrypt-firstboot.sh";then
log "ERROR: Failed to copy letsencrypt-firstboot.sh"
exit 1
fi
if ! remote_copy "./templates/letsencrypt-firstboot.service" "/tmp/letsencrypt-firstboot.service";then
log "ERROR: Failed to copy letsencrypt-firstboot.service"
exit 1
fi
run_remote "Configuring Let's Encrypt templates" '
        set -e
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy

        # Install deploy hook for renewals
        mv /tmp/letsencrypt-deploy-hook.sh /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/proxmox.sh

        # Install first-boot script (already has substituted values)
        mv /tmp/letsencrypt-firstboot.sh /usr/local/bin/obtain-letsencrypt-cert.sh
        chmod +x /usr/local/bin/obtain-letsencrypt-cert.sh

        # Install and enable systemd service
        mv /tmp/letsencrypt-firstboot.service /etc/systemd/system/letsencrypt-firstboot.service
        systemctl daemon-reload
        systemctl enable letsencrypt-firstboot.service
    ' "First-boot certificate service configured"
LETSENCRYPT_DOMAIN="$cert_domain"
LETSENCRYPT_FIRSTBOOT=true
}
create_api_token(){
[[ $INSTALL_API_TOKEN != "yes" ]]&&return 0
log "INFO: Creating Proxmox API token: $API_TOKEN_NAME"
local existing
existing=$(remote_exec "pveum user token list root@pam 2>/dev/null | grep -q '$API_TOKEN_NAME' && echo 'exists' || echo ''"||true)
if [[ $existing == "exists" ]];then
log "WARNING: Token $API_TOKEN_NAME exists, removing first"
remote_exec "pveum user token remove root@pam $API_TOKEN_NAME"||true
fi
local output
output=$(remote_exec "pveum user token add root@pam $API_TOKEN_NAME --privsep 0 --expire 0 --output-format json 2>&1"||true)
if [[ -z $output ]];then
log "ERROR: Failed to create API token - empty output"
return 1
fi
local json_output
json_output=$(echo "$output"|grep -v "^perl:"|grep -v "^warning:"|grep -E '^\{|"value"'|head -1)
local token_value
token_value=$(echo "$json_output"|jq -r '.value // empty' 2>/dev/null||true)
if [[ -z $token_value ]];then
log "ERROR: Failed to extract token value from pveum output"
log "DEBUG: pveum output: $output"
return 1
fi
API_TOKEN_VALUE="$token_value"
API_TOKEN_ID="root@pam!$API_TOKEN_NAME"
(umask 0077
cat >/tmp/pve-install-api-token.env <<EOF
API_TOKEN_VALUE=$token_value
API_TOKEN_ID=$API_TOKEN_ID
API_TOKEN_NAME=$API_TOKEN_NAME
EOF
)
log "INFO: API token created successfully: $API_TOKEN_ID"
return 0
}
configure_zfs_arc(){
log "INFO: Configuring ZFS ARC memory allocation (mode: $ZFS_ARC_MODE)"
local total_ram_mb
total_ram_mb=$(free -m|awk 'NR==2 {print $2}')
local arc_max_mb
case "$ZFS_ARC_MODE" in
vm-focused)arc_max_mb=4096
;;
balanced)if
[[ $total_ram_mb -lt 16384 ]]
then
arc_max_mb=$((total_ram_mb*25/100))
elif [[ $total_ram_mb -lt 65536 ]];then
arc_max_mb=$((total_ram_mb*40/100))
else
arc_max_mb=$((total_ram_mb/2))
fi
;;
storage-focused)arc_max_mb=$((total_ram_mb/2))
;;
*)log "ERROR: Invalid ZFS_ARC_MODE: $ZFS_ARC_MODE"
return 1
esac
local arc_max_bytes=$((arc_max_mb*1024*1024))
log "INFO: ZFS ARC: ${arc_max_mb}MB (Total RAM: ${total_ram_mb}MB, Mode: $ZFS_ARC_MODE)"
run_remote "Configuring ZFS ARC memory" "
    # Set ZFS ARC limit in modprobe config (persistent across reboots)
    echo 'options zfs zfs_arc_max=$arc_max_bytes' >/etc/modprobe.d/zfs.conf

    # Apply limit to currently running kernel module (if ZFS loaded)
    if [[ -f /sys/module/zfs/parameters/zfs_arc_max ]]; then
      echo '$arc_max_bytes' >/sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || true
    fi
  "
log "INFO: ZFS ARC memory limit configured: ${arc_max_mb}MB"
}
configure_zfs_scrub(){
log "INFO: Configuring ZFS scrub schedule"
remote_copy "templates/zfs-scrub.service" "/etc/systemd/system/zfs-scrub@.service"||return 1
remote_copy "templates/zfs-scrub.timer" "/etc/systemd/system/zfs-scrub@.timer"||return 1
run_remote "Enabling ZFS scrub timers" "
    systemctl daemon-reload

    # Enable scrub timer for rpool (boot/system pool)
    if zpool list rpool &>/dev/null; then
      systemctl enable --now zfs-scrub@rpool.timer
      echo 'Enabled scrub timer for rpool'
    fi

    # Enable scrub timer for tank (data pool) if exists
    if zpool list tank &>/dev/null; then
      systemctl enable --now zfs-scrub@tank.timer
      echo 'Enabled scrub timer for tank'
    fi
  "
log "INFO: ZFS scrub schedule configured (monthly, 1st Sunday at 2:00 AM)"
}
configure_zfs_pool(){
if [[ -z $BOOT_DISK ]];then
log "INFO: BOOT_DISK not set, skipping separate ZFS pool creation (all-ZFS mode)"
return 0
fi
log "INFO: Creating separate ZFS pool 'tank' from pool disks"
if ! load_virtio_mapping;then
log "ERROR: Failed to load virtio mapping"
return 1
fi
local vdevs_str
vdevs_str=$(map_disks_to_virtio "space_separated" "${ZFS_POOL_DISKS[@]}")
if [[ -z $vdevs_str ]];then
log "ERROR: Failed to map pool disks to virtio devices"
return 1
fi
read -ra vdevs <<<"$vdevs_str"
log "INFO: Pool disks: ${vdevs[*]} (RAID: $ZFS_RAID)"
local pool_cmd
pool_cmd=$(build_zpool_command "tank" "$ZFS_RAID" "${vdevs[@]}")
if [[ -z $pool_cmd ]];then
log "ERROR: Failed to build zpool create command"
return 1
fi
log "INFO: ZFS pool command: $pool_cmd"
if ! run_remote "Creating ZFS pool 'tank'" "
    set -e

    # Create ZFS pool with specified RAID configuration
    $pool_cmd

    # Set recommended ZFS properties
    zfs set compression=lz4 tank
    zfs set atime=off tank
    zfs set relatime=on tank
    zfs set xattr=sa tank
    zfs set dnodesize=auto tank

    # Create dataset for VM disks
    zfs create tank/vm-disks

    # Add tank pool to Proxmox storage config
    pvesm add zfspool tank --pool tank/vm-disks --content images,rootdir

    # Configure local storage (boot disk ext4) for ISO/templates/backups
    pvesm set local --content iso,vztmpl,backup,snippets

    # Verify pool was created
    if ! zpool list | grep -q '^tank '; then
      echo 'ERROR: ZFS pool tank not found after creation'
      exit 1
    fi
  " "ZFS pool 'tank' created";then
log "ERROR: Failed to create ZFS pool 'tank'"
return 1
fi
log "INFO: ZFS pool 'tank' created successfully"
log "INFO: Proxmox storage configured: tank (VMs), local (ISO/templates/backups)"
return 0
}
configure_ssh_hardening(){
(remote_copy "templates/sshd_config" "/etc/ssh/sshd_config"||exit 1
remote_exec "chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Deploying SSH hardening" "Security hardening configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: SSH hardening failed - system may be insecure"
exit 1
fi
}
validate_installation(){
log "Generating validation script from template..."
local validation_script
validation_script=$(apply_template_vars "./templates/validation.sh" \
"INSTALL_TAILSCALE=${INSTALL_TAILSCALE:-no}" \
"INSTALL_FIREWALL=${INSTALL_FIREWALL:-no}" \
"FIREWALL_MODE=${FIREWALL_MODE:-standard}" \
"INSTALL_APPARMOR=${INSTALL_APPARMOR:-no}" \
"INSTALL_AUDITD=${INSTALL_AUDITD:-no}" \
"INSTALL_AIDE=${INSTALL_AIDE:-no}" \
"INSTALL_CHKROOTKIT=${INSTALL_CHKROOTKIT:-no}" \
"INSTALL_LYNIS=${INSTALL_LYNIS:-no}" \
"INSTALL_NEEDRESTART=${INSTALL_NEEDRESTART:-no}" \
"INSTALL_VNSTAT=${INSTALL_VNSTAT:-no}" \
"INSTALL_PROMETHEUS=${INSTALL_PROMETHEUS:-no}" \
"INSTALL_NETDATA=${INSTALL_NETDATA:-no}" \
"INSTALL_YAZI=${INSTALL_YAZI:-no}" \
"INSTALL_NVIM=${INSTALL_NVIM:-no}" \
"INSTALL_RINGBUFFER=${INSTALL_RINGBUFFER:-no}" \
"SHELL_TYPE=${SHELL_TYPE:-bash}" \
"SSL_TYPE=${SSL_TYPE:-self-signed}")
log "Validation script generated"
echo "$validation_script" >>"$LOG_FILE"
(echo "$validation_script"|remote_exec 'bash -s' 2>&1|tee -a "$LOG_FILE"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Validating installation" "Installation validated"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: Installation validation failed"
print_error "Installation validation failed - check $LOG_FILE for details"
exit 1
fi
}
finalize_vm(){
remote_exec "poweroff" >/dev/null 2>&1&
show_progress $! "Powering off the VM"
(local timeout=120
local elapsed=0
while ((elapsed<timeout));do
if ! kill -0 "$QEMU_PID" 2>/dev/null;then
exit 0
fi
sleep 1
((elapsed+=1))
done
exit 1) \
&
local wait_pid=$!
show_progress $wait_pid "Waiting for QEMU process to exit" "QEMU process exited"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: QEMU process did not exit cleanly within 120 seconds"
kill -9 "$QEMU_PID" 2>/dev/null||true
fi
}
_parallel_config_apparmor(){
[[ ${INSTALL_APPARMOR:-} != "yes" ]]&&return 0
_config_apparmor
}
_parallel_config_fail2ban(){
[[ ${INSTALL_FIREWALL:-} != "yes" || ${FIREWALL_MODE:-standard} == "stealth" ]]&&return 0
_config_fail2ban
}
_parallel_config_auditd(){
[[ ${INSTALL_AUDITD:-} != "yes" ]]&&return 0
_config_auditd
}
_parallel_config_aide(){
[[ ${INSTALL_AIDE:-} != "yes" ]]&&return 0
_config_aide
}
_parallel_config_chkrootkit(){
[[ ${INSTALL_CHKROOTKIT:-} != "yes" ]]&&return 0
_config_chkrootkit
}
_parallel_config_lynis(){
[[ ${INSTALL_LYNIS:-} != "yes" ]]&&return 0
_config_lynis
}
_parallel_config_needrestart(){
[[ ${INSTALL_NEEDRESTART:-} != "yes" ]]&&return 0
_config_needrestart
}
_parallel_config_prometheus(){
[[ ${INSTALL_PROMETHEUS:-} != "yes" ]]&&return 0
_config_prometheus
}
_parallel_config_vnstat(){
[[ ${INSTALL_VNSTAT:-} != "yes" ]]&&return 0
_config_vnstat
}
_parallel_config_ringbuffer(){
[[ ${INSTALL_RINGBUFFER:-} != "yes" ]]&&return 0
_config_ringbuffer
}
_parallel_config_nvim(){
[[ ${INSTALL_NVIM:-} != "yes" ]]&&return 0
_config_nvim
}
configure_proxmox_via_ssh(){
log "Starting Proxmox configuration via SSH"
make_templates
configure_base_system
configure_shell
configure_system_services
configure_zfs_arc
configure_zfs_pool
configure_zfs_scrub
configure_tailscale
configure_firewall
batch_install_packages
run_parallel_group "Configuring security" "Security features configured" \
_parallel_config_apparmor \
_parallel_config_fail2ban \
_parallel_config_auditd \
_parallel_config_aide \
_parallel_config_chkrootkit \
_parallel_config_lynis \
_parallel_config_needrestart
(local pids=()
if [[ $INSTALL_NETDATA == "yes" ]];then
configure_netdata&
pids+=($!)
fi
if [[ $INSTALL_YAZI == "yes" ]];then
configure_yazi&
pids+=($!)
fi
for pid in "${pids[@]}";do wait "$pid" 2>/dev/null||true;done) > \
/dev/null 2>&1&
local special_pid=$!
run_parallel_group "Configuring tools" "Tools configured" \
_parallel_config_prometheus \
_parallel_config_vnstat \
_parallel_config_ringbuffer \
_parallel_config_nvim
wait $special_pid 2>/dev/null||true
configure_ssl_certificate
if [[ $INSTALL_API_TOKEN == "yes" ]];then
(create_api_token||exit 1) >/dev/null 2>&1&
show_progress $! "Creating API token" "API token created"
fi
configure_ssh_hardening
validate_installation
finalize_vm
}
_print_field(){
local label="$1" value="$2" note="${3:-}"
printf "$CLR_CYAN  %-9s$CLR_RESET %s" "$label:" "$value"
[[ -n $note ]]&&printf " $CLR_GRAY%s$CLR_RESET" "$note"
printf "\n"
}
_show_credentials_info(){
echo ""
echo "$CLR_YELLOW${CLR_BOLD}Access Credentials$CLR_RESET $CLR_RED(SAVE THIS!)$CLR_RESET"
echo ""
print_section "Root Access:"
_print_field "Hostname" "$PVE_HOSTNAME.$DOMAIN_SUFFIX"
_print_field "Username" "root"
_print_field "Password" "$NEW_ROOT_PASSWORD"
local has_tailscale=""
[[ -n $TAILSCALE_IP && $TAILSCALE_IP != "pending" && $TAILSCALE_IP != "not authenticated" ]]&&has_tailscale="yes"
case "${FIREWALL_MODE:-standard}" in
stealth)if
[[ $has_tailscale == "yes" ]]
then
_print_field "Web UI" "https://$TAILSCALE_IP:8006" "(Tailscale only)"
else
_print_field "Web UI" "${CLR_YELLOW}blocked$CLR_RESET" "(stealth mode, no Tailscale)"
fi
;;
strict)if
[[ $has_tailscale == "yes" ]]
then
_print_field "Web UI" "https://$TAILSCALE_IP:8006" "(Tailscale only)"
else
_print_field "Web UI" "${CLR_YELLOW}blocked$CLR_RESET" "(strict mode blocks :8006)"
fi
;;
*)_print_field "Web UI" "https://$MAIN_IPV4:8006"
if [[ $has_tailscale == "yes" ]];then
_print_field "" "https://$TAILSCALE_IP:8006" "(Tailscale)"
fi
esac
if [[ -f /tmp/pve-install-api-token.env ]];then
source /tmp/pve-install-api-token.env
if [[ -n $API_TOKEN_VALUE ]];then
echo ""
print_section "API Token:"
_print_field "Token ID" "$API_TOKEN_ID"
_print_field "Secret" "$API_TOKEN_VALUE"
fi
fi
echo ""
}
reboot_to_main_os(){
finish_live_installation
_wiz_start_edit
print_info "Installation completed successfully!"
_show_credentials_info
if gum confirm "Reboot the system now?" \
--affirmative "Yes" \
--negative "No" \
--default=true \
--prompt.foreground "#ff8700" \
--selected.background "#ff8700" \
--unselected.foreground "#585858";then
print_info "Rebooting the system..."
if ! reboot;then
log "ERROR: Failed to reboot - system may require manual restart"
print_error "Failed to reboot the system"
exit 1
fi
else
print_info "Exiting without reboot."
echo ""
print_info "You can reboot manually when ready with: ${CLR_CYAN}reboot$CLR_RESET"
exit 0
fi
}
log "=========================================="
log "Proxmox VE Automated Installer v$VERSION"
log "=========================================="
log "QEMU_RAM_OVERRIDE=$QEMU_RAM_OVERRIDE"
log "QEMU_CORES_OVERRIDE=$QEMU_CORES_OVERRIDE"
log "PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
log "SSL_TYPE=${SSL_TYPE:-self-signed}"
metrics_start
log "Step: collect_system_info"
show_banner_animated_start 0.1
SYSTEM_INFO_CACHE=$(mktemp)
{
collect_system_info
log "Step: prefetch_proxmox_iso_info"
prefetch_proxmox_iso_info
declare -p|grep -E "^declare -[^ ]* (PREFLIGHT_|DRIVE_|INTERFACE_|CURRENT_INTERFACE|PREDICTABLE_NAME|DEFAULT_INTERFACE|AVAILABLE_|MAC_ADDRESS|MAIN_IPV|IPV6_|FIRST_IPV6_|_ISO_|_CHECKSUM_|WIZ_TIMEZONES|WIZ_COUNTRIES|TZ_TO_COUNTRY)" >"$SYSTEM_INFO_CACHE"
} >/dev/null 2>&1&
wait $!
show_banner_animated_stop
if [[ -s $SYSTEM_INFO_CACHE ]];then
source "$SYSTEM_INFO_CACHE"
rm -f "$SYSTEM_INFO_CACHE"
fi
log "Step: show_system_status"
show_system_status
log_metric "system_info"
log "Step: show_gum_config_editor"
show_gum_config_editor
log_metric "config_wizard"
start_live_installation||{
log "WARNING: Failed to start live installation display, falling back to regular mode"
clear
show_banner
}
log "Step: prepare_packages"
prepare_packages
log_metric "packages"
log "Step: download_proxmox_iso"
download_proxmox_iso
log_metric "iso_download"
log "Step: make_answer_toml"
make_answer_toml
log "Step: make_autoinstall_iso"
make_autoinstall_iso
log_metric "autoinstall_prep"
log "Step: install_proxmox"
install_proxmox
log_metric "proxmox_install"
log "Step: boot_proxmox_with_port_forwarding"
boot_proxmox_with_port_forwarding||{
log "ERROR: Failed to boot Proxmox with port forwarding"
exit 1
}
log_metric "qemu_boot"
log "Step: configure_proxmox_via_ssh"
configure_proxmox_via_ssh
log_metric "system_config"
metrics_finish
INSTALL_COMPLETED=true
log "Step: reboot_to_main_os"
reboot_to_main_os
