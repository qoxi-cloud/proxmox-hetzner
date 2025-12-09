#!/usr/bin/env bash
cd /root||exit 1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
CLR_RED=$'\033[1;31m'
CLR_CYAN=$'\033[38;2;0;177;255m'
CLR_YELLOW=$'\033[1;33m'
CLR_ORANGE=$'\033[38;5;208m'
CLR_GRAY=$'\033[38;5;240m'
CLR_HETZNER=$'\033[38;5;160m'
CLR_RESET=$'\033[m'
MENU_BOX_WIDTH=60
VERSION="1.18.7-pr.19"
GITHUB_REPO="${GITHUB_REPO:-qoxi-cloud/proxmox-hetzner}"
GITHUB_BRANCH="${GITHUB_BRANCH:-feat/gum-table}"
GITHUB_BASE_URL="https://github.com/$GITHUB_REPO/raw/refs/heads/$GITHUB_BRANCH"
PROXMOX_ISO_BASE_URL="https://enterprise.proxmox.com/iso/"
PROXMOX_CHECKSUM_URL="https://enterprise.proxmox.com/iso/SHA256SUMS"
DNS_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="1.0.0.1"
DNS_TERTIARY="8.8.8.8"
DNS_QUATERNARY="8.8.4.4"
DNS6_PRIMARY="2606:4700:4700::1111"
DNS6_SECONDARY="2606:4700:4700::1001"
DNS6_TERTIARY="2001:4860:4860::8888"
DNS6_QUATERNARY="2001:4860:4860::8844"
MIN_DISK_SPACE_MB=3000
MIN_RAM_MB=4000
MIN_CPU_CORES=2
DEFAULT_QEMU_RAM=8192
MIN_QEMU_RAM=4096
MAX_QEMU_CORES=16
QEMU_LOW_RAM_THRESHOLD=16384
DOWNLOAD_RETRY_COUNT=3
DOWNLOAD_RETRY_DELAY=2
SSH_READY_TIMEOUT=120
SSH_CONNECT_TIMEOUT=10
QEMU_BOOT_TIMEOUT=300
DEFAULT_PASSWORD_LENGTH=16
QEMU_MIN_RAM_RESERVE=2048
DNS_LOOKUP_TIMEOUT=5
DNS_RETRY_DELAY=10
DEFAULT_HOSTNAME="pve"
DEFAULT_DOMAIN="local"
DEFAULT_TIMEZONE="Europe/Kyiv"
DEFAULT_EMAIL="admin@example.com"
DEFAULT_BRIDGE_MODE="internal"
DEFAULT_SUBNET="10.0.0.0/24"
DEFAULT_BRIDGE_MTU=9000
DEFAULT_SHELL=""
DEFAULT_REPO_TYPE="no-subscription"
DEFAULT_SSL_TYPE="self-signed"
DEFAULT_CPU_GOVERNOR="performance"
DEFAULT_IPV6_MODE="auto"
DEFAULT_IPV6_GATEWAY="fe80::1"
DEFAULT_IPV6_VM_PREFIX=80
SYSTEM_UTILITIES="btop iotop ncdu tmux pigz smartmontools jq bat fastfetch"
OPTIONAL_PACKAGES="libguestfs-tools"
LOG_FILE="/root/pve-install-$(date +%Y%m%d-%H%M%S).log"
INSTALL_COMPLETED=false
cleanup_temp_files(){
rm -f /tmp/tailscale_*.txt /tmp/iso_checksum.txt /tmp/*.tmp 2>/dev/null||true
if [[ $INSTALL_COMPLETED != "true" ]];then
rm -f /root/pve.iso /root/pve-autoinstall.iso /root/answer.toml /root/SHA256SUMS 2>/dev/null||true
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
echo ""
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
FAIL2BAN_INSTALLED=""
INSTALL_AUDITD=""
CPU_GOVERNOR=""
AUDITD_INSTALLED=""
INSTALL_VNSTAT=""
VNSTAT_INSTALLED=""
INSTALL_UNATTENDED_UPGRADES=""
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
log_debug(){
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >>"$LOG_FILE"
}
log_cmd(){
log_debug "Running: $*"
"$@" >>"$LOG_FILE" 2>&1
local exit_code=$?
log_debug "Exit code: $exit_code"
return $exit_code
}
run_logged(){
log_debug "Executing: $*"
"$@" >>"$LOG_FILE" 2>&1
local exit_code=$?
log_debug "Exit code: $exit_code"
return $exit_code
}
BANNER_LETTER_COUNT=7
ANSI_CURSOR_HIDE=$'\033[?25l'
ANSI_CURSOR_SHOW=$'\033[?25h'
show_banner(){
printf '%s\n' \
"" \
"$CLR_GRAY    _____                                             $CLR_RESET" \
"$CLR_GRAY   |  __ \\                                            $CLR_RESET" \
"$CLR_GRAY   | |__) | _ __   ___  ${CLR_ORANGE}__  __$CLR_GRAY  _ __ ___    ___  ${CLR_ORANGE}__  __$CLR_RESET" \
"$CLR_GRAY   |  ___/ | '__| / _ \\ $CLR_ORANGE\\ \\/ /$CLR_GRAY | '_ \` _ \\  / _ \\ $CLR_ORANGE\\ \\/ /$CLR_RESET" \
"$CLR_GRAY   | |     | |   | (_) |$CLR_ORANGE >  <$CLR_GRAY  | | | | | || (_) |$CLR_ORANGE >  <$CLR_RESET" \
"$CLR_GRAY   |_|     |_|    \\___/ $CLR_ORANGE/_/\\_\\$CLR_GRAY |_| |_| |_| \\___/ $CLR_ORANGE/_/\\_\\$CLR_RESET" \
"" \
"$CLR_HETZNER               Hetzner ${CLR_GRAY}Automated Installer$CLR_RESET" \
""
}
_show_banner_frame(){
local h="${1:--1}"
local M="$CLR_GRAY"
local A="$CLR_ORANGE"
local R="$CLR_RESET"
local line1="$M    "
[[ $h -eq 0 ]]&&line1+="${A}_____$M"||line1+="_____"
line1+="                                             $R"
local line2="$M   "
[[ $h -eq 0 ]]&&line2+="$A|  __ \\$M"||line2+='|  __ \'
line2+="                                            $R"
local line3="$M   "
[[ $h -eq 0 ]]&&line3+="$A| |__) |$M"||line3+="| |__) |"
[[ $h -eq 1 ]]&&line3+=" ${A}_ __$M"||line3+=" _ __"
[[ $h -eq 2 ]]&&line3+="   ${A}___$M"||line3+="   ___"
[[ $h -eq 3 ]]&&line3+="  ${A}__  __$M"||line3+="  __  __"
[[ $h -eq 4 ]]&&line3+="  ${A}_ __ ___$M"||line3+="  _ __ ___"
[[ $h -eq 5 ]]&&line3+="    ${A}___$M"||line3+="    ___"
[[ $h -eq 6 ]]&&line3+="  ${A}__  __$M"||line3+="  __  __"
line3+="$R"
local line4="$M   "
[[ $h -eq 0 ]]&&line4+="$A|  ___/ $M"||line4+="|  ___/ "
[[ $h -eq 1 ]]&&line4+="$A| '__|$M"||line4+="| '__|"
[[ $h -eq 2 ]]&&line4+=" $A/ _ \\$M"||line4+=' / _ \'
[[ $h -eq 3 ]]&&line4+=" $A\\ \\/ /$M"||line4+=' \ \/ /'
[[ $h -eq 4 ]]&&line4+=" $A| '_ \` _ \\$M"||line4+=" | '_ \` _ \\"
[[ $h -eq 5 ]]&&line4+="  $A/ _ \\$M"||line4+='  / _ \'
[[ $h -eq 6 ]]&&line4+=" $A\\ \\/ /$M"||line4+=' \ \/ /'
line4+="$R"
local line5="$M   "
[[ $h -eq 0 ]]&&line5+="$A| |     $M"||line5+="| |     "
[[ $h -eq 1 ]]&&line5+="$A| |$M"||line5+="| |"
[[ $h -eq 2 ]]&&line5+="   $A| (_) |$M"||line5+="   | (_) |"
[[ $h -eq 3 ]]&&line5+="$A >  <$M"||line5+=" >  <"
[[ $h -eq 4 ]]&&line5+="  $A| | | | | |$M"||line5+="  | | | | | |"
[[ $h -eq 5 ]]&&line5+="$A| (_) |$M"||line5+="| (_) |"
[[ $h -eq 6 ]]&&line5+="$A >  <$M"||line5+=" >  <"
line5+="$R"
local line6="$M   "
[[ $h -eq 0 ]]&&line6+="$A|_|     $M"||line6+="|_|     "
[[ $h -eq 1 ]]&&line6+="$A|_|$M"||line6+="|_|"
[[ $h -eq 2 ]]&&line6+="    $A\\___/$M"||line6+='    \___/'
[[ $h -eq 3 ]]&&line6+=" $A/_/\\_\\$M"||line6+=' /_/\_\'
[[ $h -eq 4 ]]&&line6+=" $A|_| |_| |_|$M"||line6+=" |_| |_| |_|"
[[ $h -eq 5 ]]&&line6+=" $A\\___/$M"||line6+=' \___/'
[[ $h -eq 6 ]]&&line6+=" $A/_/\\_\\$M"||line6+=' /_/\_\'
line6+="$R"
local line_hetzner="$CLR_HETZNER               Hetzner ${M}Automated Installer$R"
printf '\033[H'
printf '%s\n' \
"" \
"$line1" \
"$line2" \
"$line3" \
"$line4" \
"$line5" \
"$line6" \
"" \
"$line_hetzner" \
""
}
BANNER_ANIMATION_PID=""
show_banner_animated_start(){
local frame_delay="${1:-0.1}"
[[ ! -t 1 ]]&&return
show_banner_animated_stop 2>/dev/null
printf '%s' "$ANSI_CURSOR_HIDE"
clear
(local direction=1
local current_letter=0
trap 'exit 0' TERM INT
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
printf '%s' "$ANSI_CURSOR_SHOW"
}
display_box(){
local title="$1"
local content="$2"
local box_style="${3:-stone}"
echo -e "$CLR_GRAY"
{
echo "$title"
echo ""
echo "$content"
}|boxes -d "$box_style" -p a1
echo -e "$CLR_RESET"
}
display_info_table(){
local title="$1"
shift
local items=("$@")
local content=""
for item in "${items[@]}";do
local label="${item%%|*}"
local rest="${item#*|}"
local value="${rest%%|*}"
local status="${rest#*|}"
case "$status" in
ok)content+="[OK]     $label: $value"$'\n';;
warn)content+="[WARN]   $label: $value"$'\n';;
error)content+="[ERROR]  $label: $value"$'\n';;
*)content+="         $label: $value"$'\n'
esac
done
content="${content%$'\n'}"
echo ""
{
echo "=== $title ==="
echo ""
echo "$content"
}|boxes -d stone -p a1
echo ""
}
colorize_status(){
while IFS= read -r line;do
if [[ $line =~ ^\+[-+]+\+$ ]];then
echo "$CLR_GRAY$line$CLR_RESET"
elif [[ $line =~ ^(\|)(.*)\|$ ]];then
local content="${BASH_REMATCH[2]}"
content="${content//\[OK\]/$CLR_CYAN[OK]$CLR_RESET}"
content="${content//\[WARN\]/$CLR_YELLOW[WARN]$CLR_RESET}"
content="${content//\[ERROR\]/$CLR_RED[ERROR]$CLR_RESET}"
echo "$CLR_GRAY|$CLR_RESET$content$CLR_GRAY|$CLR_RESET"
else
echo "$line"
fi
done
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
apply_template_vars "$file" \
"MAIN_IPV4=${MAIN_IPV4:-}" \
"MAIN_IPV4_GW=${MAIN_IPV4_GW:-}" \
"MAIN_IPV6=${MAIN_IPV6:-}" \
"FIRST_IPV6_CIDR=${FIRST_IPV6_CIDR:-}" \
"IPV6_GATEWAY=${IPV6_GATEWAY:-${DEFAULT_IPV6_GATEWAY:-fe80::1}}" \
"FQDN=${FQDN:-}" \
"HOSTNAME=${PVE_HOSTNAME:-}" \
"INTERFACE_NAME=${INTERFACE_NAME:-}" \
"PRIVATE_IP_CIDR=${PRIVATE_IP_CIDR:-}" \
"PRIVATE_SUBNET=${PRIVATE_SUBNET:-}" \
"BRIDGE_MTU=${DEFAULT_BRIDGE_MTU:-9000}" \
"DNS_PRIMARY=${DNS_PRIMARY:-1.1.1.1}" \
"DNS_SECONDARY=${DNS_SECONDARY:-1.0.0.1}" \
"DNS_TERTIARY=${DNS_TERTIARY:-8.8.8.8}" \
"DNS_QUATERNARY=${DNS_QUATERNARY:-8.8.4.4}" \
"DNS6_PRIMARY=${DNS6_PRIMARY:-2606:4700:4700::1111}" \
"DNS6_SECONDARY=${DNS6_SECONDARY:-2606:4700:4700::1001}"
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
*.conf|*.sources|*.service)if
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
generate_password(){
local length="${1:-16}"
tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom|head -c "$length"
}
read_password(){
local prompt="$1"
local password=""
local char=""
echo -n "$prompt" >&2
while IFS= read -r -s -n1 char;do
if [[ -z $char ]];then
break
fi
if [[ $char == $'\x7f' || $char == $'\x08' ]];then
if [[ -n $password ]];then
password="${password%?}"
echo -ne "\b \b" >&2
fi
else
password+="$char"
echo -n "*" >&2
fi
done
echo "" >&2
echo "$password"
}
prompt_validated(){
local prompt="$1"
local default="$2"
local validator="$3"
local error_msg="$4"
local result=""
while true;do
read -r -e -p "$prompt" -i "$default" result
if $validator "$result";then
echo "$result"
return 0
fi
print_error "$error_msg"
done
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
wait_with_progress(){
local message="$1"
local timeout="$2"
local check_cmd="$3"
local interval="${4:-5}"
local done_message="${5:-$message}"
local result_file
result_file=$(mktemp)
echo "running" >"$result_file"
(local start_time
start_time=$(date +%s)
while true;do
local elapsed=$(($(date +%s)-start_time))
if eval "$check_cmd" 2>/dev/null;then
echo "success" >"$result_file"
exit 0
fi
if [ $elapsed -ge $timeout ];then
echo "timeout" >"$result_file"
exit 1
fi
sleep "$interval"
done) \
&
local wait_pid=$!
gum spin --spinner meter --spinner.foreground "#ff8700" --title "$message" -- bash -c "
    while kill -0 $wait_pid 2>/dev/null; do
      sleep 0.2
    done
  "
wait "$wait_pid" 2>/dev/null
local result
result=$(cat "$result_file")
rm -f "$result_file"
if [[ $result == "success" ]];then
printf "$CLR_CYAN✓$CLR_RESET %s\n" "$done_message"
return 0
else
printf "$CLR_RED✗$CLR_RESET %s timed out\n" "$message"
return 1
fi
}
show_timed_progress(){
local message="$1"
local duration="${2:-$((5+RANDOM%3))}"
local steps=20
local sleep_interval
sleep_interval=$(awk "BEGIN {printf \"%.2f\", $duration / $steps}")
local current=0
while [[ $current -le $steps ]];do
local pct=$((current*100/steps))
local filled=$current
local empty=$((steps-filled))
local bar_filled="" bar_empty=""
printf -v bar_filled '%*s' "$filled" ''
bar_filled="${bar_filled// /█}"
printf -v bar_empty '%*s' "$empty" ''
bar_empty="${bar_empty// /░}"
printf "\r$CLR_ORANGE%s [$CLR_ORANGE%s$CLR_RESET$CLR_GRAY%s$CLR_RESET$CLR_ORANGE] %3d%%$CLR_RESET" \
"$message" "$bar_filled" "$bar_empty" "$pct"
if [[ $current -lt $steps ]];then
sleep "$sleep_interval"
fi
current=$((current+1))
done
printf "\r\e[K"
}
format_duration(){
local seconds="$1"
local hours=$((seconds/3600))
local minutes=$(((seconds%3600)/60))
local secs=$((seconds%60))
if [[ $hours -gt 0 ]];then
echo "${hours}h ${minutes}m ${secs}s"
else
echo "${minutes}m ${secs}s"
fi
}
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10}"
SSH_PORT="5555"
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
create_passfile(){
local passfile
if [[ -d /dev/shm ]]&&[[ -w /dev/shm ]];then
passfile=$(mktemp --tmpdir=/dev/shm pve-passfile.XXXXXX 2>/dev/null||mktemp)
else
passfile=$(mktemp)
fi
echo "$NEW_ROOT_PASSWORD" >"$passfile"
chmod 600 "$passfile"
echo "$passfile"
}
secure_cleanup_passfile(){
local passfile="$1"
if [[ -f $passfile ]];then
if command -v shred &>/dev/null;then
shred -u -z "$passfile" 2>/dev/null||rm -f "$passfile"
else
if command -v dd &>/dev/null;then
local file_size
file_size=$(stat -c%s "$passfile" 2>/dev/null||echo 1024)
dd if=/dev/zero of="$passfile" bs=1 count="$file_size" 2>/dev/null||true
fi
rm -f "$passfile"
fi
fi
}
wait_for_ssh_ready(){
local timeout="${1:-120}"
ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:$SSH_PORT" 2>/dev/null||true
local port_check=0
for i in {1..10};do
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
passfile=$(create_passfile)
wait_with_progress "Waiting for SSH to be ready" "$timeout" \
"sshpass -f \"$passfile\" ssh -p \"$SSH_PORT\" $SSH_OPTS root@localhost 'echo ready' >/dev/null 2>&1" \
2 "SSH connection established"
local exit_code=$?
secure_cleanup_passfile "$passfile"
return $exit_code
}
remote_exec(){
local passfile
passfile=$(create_passfile)
local max_attempts=3
local attempt=0
local exit_code=1
while [[ $attempt -lt $max_attempts ]];do
attempt=$((attempt+1))
if sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost "$@";then
exit_code=0
break
fi
if [[ $attempt -lt $max_attempts ]];then
log "SSH attempt $attempt failed, retrying in 2 seconds..."
sleep 2
fi
done
secure_cleanup_passfile "$passfile"
if [[ $exit_code -ne 0 ]];then
log "ERROR: SSH command failed after $max_attempts attempts: $*"
fi
return $exit_code
}
remote_exec_script(){
local passfile
passfile=$(create_passfile)
sshpass -f "$passfile" ssh -p "$SSH_PORT" $SSH_OPTS root@localhost 'bash -s'
local exit_code=$?
secure_cleanup_passfile "$passfile"
return $exit_code
}
remote_exec_with_progress(){
local message="$1"
local script="$2"
local done_message="${3:-$message}"
log "remote_exec_with_progress: $message"
log "--- Script start ---"
echo "$script" >>"$LOG_FILE"
log "--- Script end ---"
local passfile
passfile=$(create_passfile)
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
secure_cleanup_passfile "$passfile"
if [[ $exit_code -ne 0 ]];then
log "remote_exec_with_progress: FAILED with exit code $exit_code"
else
log "remote_exec_with_progress: completed successfully"
fi
return $exit_code
}
run_remote(){
local message="$1"
local script="$2"
local done_message="${3:-$message}"
if ! remote_exec_with_progress "$message" "$script" "$done_message";then
log "ERROR: $message failed"
exit 1
fi
}
remote_copy(){
local src="$1"
local dst="$2"
local passfile
passfile=$(create_passfile)
sshpass -f "$passfile" scp -P "$SSH_PORT" $SSH_OPTS "$src" "root@localhost:$dst"
local exit_code=$?
secure_cleanup_passfile "$passfile"
return $exit_code
}
parse_ssh_key(){
local key="$1"
SSH_KEY_TYPE=""
SSH_KEY_DATA=""
SSH_KEY_COMMENT=""
SSH_KEY_SHORT=""
if [[ -z $key ]];then
return 1
fi
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
validate_ssh_key(){
local key="$1"
[[ $key =~ ^ssh-(rsa|ed25519|ecdsa)[[:space:]] ]]
}
get_rescue_ssh_key(){
if [[ -f /root/.ssh/authorized_keys ]];then
grep -E "^ssh-(rsa|ed25519|ecdsa)" /root/.ssh/authorized_keys 2>/dev/null|head -1
fi
}
MENU_BOX_WIDTH=60
_wrap_text(){
local text="$1"
local prefix="$2"
local max_width="$3"
local result=""
local line=""
local first_line=true
for word in $text;do
if [[ -z $line ]];then
line="$word"
elif [[ $((${#line}+1+${#word})) -le $max_width ]];then
line+=" $word"
else
if [[ $first_line == true ]];then
result+="$line"$'\n'
first_line=false
else
result+="$prefix$line"$'\n'
fi
line="$word"
fi
done
if [[ -n $line ]];then
if [[ $first_line == true ]];then
result+="$line"
else
result+="$prefix$line"
fi
fi
echo "$result"
}
radio_menu(){
local title="$1"
local header="$2"
shift 2
local items=("$@")
local -a labels=()
local -a descriptions=()
for item in "${items[@]}";do
labels+=("${item%%|*}")
descriptions+=("${item#*|}")
done
local selected=0
local key=""
local box_lines=0
local num_options=${#labels[@]}
_draw_menu(){
local content=""
local desc_max_width=47
local desc_prefix="       "
if [[ -n $header ]];then
content+="$header"$'\n'
fi
for i in "${!labels[@]}";do
if [ $i -eq $selected ];then
content+="[*] ${labels[$i]}"$'\n'
if [[ -n ${descriptions[$i]} ]];then
local wrapped_desc
wrapped_desc=$(_wrap_text "${descriptions[$i]}" "$desc_prefix" "$desc_max_width")
content+="    └─ $wrapped_desc"$'\n'
fi
else
content+="[ ] ${labels[$i]}"$'\n'
if [[ -n ${descriptions[$i]} ]];then
local wrapped_desc
wrapped_desc=$(_wrap_text "${descriptions[$i]}" "$desc_prefix" "$desc_max_width")
content+="    └─ $wrapped_desc"$'\n'
fi
fi
done
content="${content%$'\n'}"
{
echo "$title"
echo "$content"
}|boxes -d stone -p a1 -s $MENU_BOX_WIDTH
}
tput civis
box_lines=$(_draw_menu|wc -l)
_colorize_menu(){
while IFS= read -r line;do
if [[ $line =~ ^\+[-+]+\+$ ]];then
echo "$CLR_GRAY$line$CLR_RESET"
elif [[ $line =~ ^(\|)(.*)\|$ ]];then
local content="${BASH_REMATCH[2]}"
if [[ $content == *"! "* ]];then
content="${content//! /$CLR_YELLOW⚠️ }"
content="${content% }"
content="$content$CLR_RESET"
fi
if [[ $content =~ ^(.*)\ \ -\ (.*)$ ]];then
local prefix="${BASH_REMATCH[1]}"
local rest="${BASH_REMATCH[2]}"
content="$prefix$CLR_YELLOW  - $rest$CLR_RESET"
fi
content="${content//Detected key from Rescue System:/${CLR_YELLOW}Detected key from Rescue System:$CLR_RESET}"
content="${content//Type:/${CLR_YELLOW}Type:$CLR_RESET}"
content="${content//Key:/${CLR_YELLOW}Key:$CLR_RESET}"
content="${content//Comment:/${CLR_YELLOW}Comment:$CLR_RESET}"
content="${content//\[\*\]/$CLR_ORANGE[●]$CLR_RESET}"
content="${content//\[ \]/$CLR_GRAY[○]$CLR_RESET}"
echo "$CLR_GRAY|$CLR_RESET$content$CLR_GRAY|$CLR_RESET"
else
echo "$line"
fi
done
}
_draw_menu|_colorize_menu
while true;do
IFS= read -rsn1 key
if [[ $key == $'\x1b' ]];then
read -rsn2 -t 0.1 key||true
case "$key" in
'[A')((selected--))||true
[ $selected -lt 0 ]&&selected=$((num_options-1))
;;
'[B')((selected++))||true
[ $selected -ge $num_options ]&&selected=0
esac
elif [[ $key == "" ]];then
break
elif [[ $key =~ ^[1-9]$ ]]&&[ "$key" -le "$num_options" ];then
selected=$((key-1))
break
fi
tput cuu $box_lines
for ((i=0; i<box_lines; i++));do
printf "\033[2K\n"
done
tput cuu $box_lines
_draw_menu|_colorize_menu
done
tput cnorm
tput cuu $box_lines
for ((i=0; i<box_lines; i++));do
printf "\033[2K\n"
done
tput cuu $box_lines
MENU_SELECTED=$selected
}
input_box(){
local title="$1"
local content="$2"
local prompt="$3"
local default="$4"
_colorize_input_box(){
while IFS= read -r line;do
if [[ $line =~ ^\+[-+]+\+$ ]];then
echo -e "$CLR_GRAY$line$CLR_RESET"
elif [[ $line =~ ^(\|)(.*)\|$ ]];then
local content="${BASH_REMATCH[2]}"
echo -e "$CLR_GRAY|$CLR_RESET$CLR_YELLOW$content$CLR_RESET$CLR_GRAY|$CLR_RESET"
else
echo "$line"
fi
done
}
local box_lines
box_lines=$({
echo "$title"
echo "$content"
}|boxes -d stone -p a1 -s $MENU_BOX_WIDTH|wc -l)
{
echo "$title"
echo "$content"
}|boxes -d stone -p a1 -s $MENU_BOX_WIDTH|_colorize_input_box
read -r -e -p "$prompt" -i "$default" INPUT_VALUE
tput cuu $((box_lines+1))
for ((i=0; i<box_lines+1; i++));do
printf "\033[2K\n"
done
tput cuu $((box_lines+1))
}
checkbox_menu(){
local title="$1"
local header="$2"
shift 2
local items=("$@")
local -a labels=()
local -a descriptions=()
local -a selected_states=()
for item in "${items[@]}";do
local label="${item%%|*}"
local rest="${item#*|}"
local desc="${rest%%|*}"
local default_state="${rest##*|}"
labels+=("$label")
descriptions+=("$desc")
selected_states+=("${default_state:-0}")
done
local cursor=0
local key=""
local box_lines=0
local num_options=${#labels[@]}
_draw_checkbox_menu(){
local content=""
local desc_max_width=44
local desc_prefix="          "
if [[ -n $header ]];then
content+="$header"$'\n'
fi
for i in "${!labels[@]}";do
local checkbox
if [[ ${selected_states[$i]} == "1" ]];then
checkbox="[x]"
else
checkbox="[ ]"
fi
if [ "$i" -eq "$cursor" ];then
content+="> $checkbox ${labels[$i]}"$'\n'
else
content+="  $checkbox ${labels[$i]}"$'\n'
fi
if [[ -n ${descriptions[$i]} ]];then
local wrapped_desc
wrapped_desc=$(_wrap_text "${descriptions[$i]}" "$desc_prefix" "$desc_max_width")
content+="       └─ $wrapped_desc"$'\n'
fi
done
content+=$'\n'"  Space: toggle, Enter: confirm"
{
echo "$title"
echo "$content"
}|boxes -d stone -p a1 -s $MENU_BOX_WIDTH
}
_colorize_checkbox_menu(){
while IFS= read -r line;do
if [[ $line =~ ^\+[-+]+\+$ ]];then
echo "$CLR_GRAY$line$CLR_RESET"
elif [[ $line =~ ^(\|)(.*)\|$ ]];then
local content="${BASH_REMATCH[2]}"
content="${content//> /$CLR_ORANGE› $CLR_RESET}"
content="${content//\[x\]/$CLR_ORANGE[●]$CLR_RESET}"
content="${content//\[ \]/$CLR_GRAY[○]$CLR_RESET}"
if [[ $content == *"Space:"* ]];then
content="$CLR_GRAY$content$CLR_RESET"
fi
echo "$CLR_GRAY|$CLR_RESET$content$CLR_GRAY|$CLR_RESET"
else
echo "$line"
fi
done
}
tput civis
box_lines=$(_draw_checkbox_menu|wc -l)
_draw_checkbox_menu|_colorize_checkbox_menu
while true;do
IFS= read -rsn1 key
if [[ $key == $'\x1b' ]];then
read -rsn2 -t 0.1 key||true
case "$key" in
'[A')((cursor--))||true
[ $cursor -lt 0 ]&&cursor=$((num_options-1))
;;
'[B')((cursor++))||true
[ "$cursor" -ge "$num_options" ]&&cursor=0
esac
elif [[ $key == " " ]];then
if [[ ${selected_states[cursor]} == "1" ]];then
selected_states[cursor]=0
else
selected_states[cursor]=1
fi
elif [[ $key == "" ]];then
break
fi
tput cuu "$box_lines"
for ((i=0; i<box_lines; i++));do
printf "\033[2K\n"
done
tput cuu "$box_lines"
_draw_checkbox_menu|_colorize_checkbox_menu
done
tput cnorm
tput cuu "$box_lines"
for ((i=0; i<box_lines; i++));do
printf "\033[2K\n"
done
tput cuu "$box_lines"
CHECKBOX_RESULTS=("${selected_states[@]}")
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
validate_password(){
local password="$1"
[[ ${#password} -ge 8 ]]&&is_ascii_printable "$password"
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
validate_password_with_error(){
local password="$1"
local error
error=$(get_password_error "$password")
if [[ -n $error ]];then
print_error "$error"
return 1
fi
return 0
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
validate_ipv6_prefix_length(){
local prefix="$1"
[[ ! $prefix =~ ^[0-9]+$ ]]&&return 1
[[ $prefix -lt 48 || $prefix -gt 128 ]]&&return 1
return 0
}
is_ipv6_link_local(){
local ipv6="$1"
[[ $ipv6 =~ ^[fF][eE]8[0-9a-fA-F]: ]]||[[ $ipv6 =~ ^[fF][eE][89aAbB][0-9a-fA-F]: ]]
}
is_ipv6_ula(){
local ipv6="$1"
[[ $ipv6 =~ ^[fF][cCdD] ]]
}
is_ipv6_global(){
local ipv6="$1"
[[ $ipv6 =~ ^[23] ]]
}
validate_timezone(){
local tz="$1"
if [[ -f "/usr/share/zoneinfo/$tz" ]];then
return 0
fi
if [[ $tz =~ ^[A-Za-z_]+/[A-Za-z_]+(/[A-Za-z_]+)?$ ]];then
print_warning "Cannot verify timezone in Rescue System, format looks valid."
return 0
fi
return 1
}
prompt_with_validation(){
local prompt="$1"
local default="$2"
local validator="$3"
local error_msg="$4"
local var_name="$5"
local confirm_label="${6:-$prompt}"
local result
while true;do
read -r -e -p "$prompt" -i "$default" result
if $validator "$result";then
printf "\033[A\r%s✓%s %s%s%s%s\033[K\n" "$CLR_CYAN" "$CLR_RESET" "$confirm_label" "$CLR_CYAN" "$result" "$CLR_RESET"
printf -v "$var_name" '%s' "$result"
return 0
fi
print_error "$error_msg"
done
}
validate_dns_resolution(){
local fqdn="$1"
local expected_ip="$2"
local resolved_ip=""
local dns_timeout="${DNS_LOOKUP_TIMEOUT:-5}"
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
if [[ -z $resolved_ip ]];then
DNS_RESOLVED_IP=""
return 1
fi
DNS_RESOLVED_IP="$resolved_ip"
if [[ $resolved_ip == "$expected_ip" ]];then
return 0
else
return 2
fi
}
prompt_password(){
local prompt="$1"
local var_name="$2"
local password
local error
password=$(read_password "$prompt")
error=$(get_password_error "$password")
while [[ -n $error ]];do
print_error "$error"
password=$(read_password "$prompt")
error=$(get_password_error "$password")
done
printf "\033[A\r%s✓%s %s********\033[K\n" "$CLR_CYAN" "$CLR_RESET" "$prompt"
printf -v "$var_name" '%s' "$password"
}
collect_system_info(){
local errors=0
local packages_to_install=""
local need_charm_repo=false
command -v boxes &>/dev/null||packages_to_install+=" boxes"
command -v column &>/dev/null||packages_to_install+=" bsdmainutils"
command -v ip &>/dev/null||packages_to_install+=" iproute2"
command -v udevadm &>/dev/null||packages_to_install+=" udev"
command -v timeout &>/dev/null||packages_to_install+=" coreutils"
command -v curl &>/dev/null||packages_to_install+=" curl"
command -v jq &>/dev/null||packages_to_install+=" jq"
command -v aria2c &>/dev/null||packages_to_install+=" aria2"
command -v findmnt &>/dev/null||packages_to_install+=" util-linux"
command -v gum &>/dev/null||{
need_charm_repo=true
packages_to_install+=" gum"
}
if [[ $need_charm_repo == true ]];then
mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key|gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" >/etc/apt/sources.list.d/charm.list
fi
if [[ -n $packages_to_install ]];then
apt-get update -qq >/dev/null 2>&1
apt-get install -qq -y $packages_to_install >/dev/null 2>&1
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
local free_space_mb
free_space_mb=$(df -m /root|awk 'NR==2 {print $4}')
if [[ $free_space_mb -ge $MIN_DISK_SPACE_MB ]];then
PREFLIGHT_DISK="$free_space_mb MB"
PREFLIGHT_DISK_STATUS="ok"
else
PREFLIGHT_DISK="$free_space_mb MB (need ${MIN_DISK_SPACE_MB}MB+)"
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
show_system_status(){
detect_drives
local no_drives=0
if [[ $DRIVE_COUNT -eq 0 ]];then
no_drives=1
fi
local table_data="Status,Check,Value"
add_row(){
local status="$1"
local label="$2"
local value="$3"
case "$status" in
ok)table_data+=$'\n'"[OK],$label,$value";;
warn)table_data+=$'\n'"[WARN],$label,$value";;
error)table_data+=$'\n'"[ERROR],$label,$value"
esac
}
add_row "ok" "Installer" "v$VERSION"
add_row "$PREFLIGHT_ROOT_STATUS" "Root Access" "$PREFLIGHT_ROOT"
add_row "$PREFLIGHT_NET_STATUS" "Internet" "$PREFLIGHT_NET"
add_row "$PREFLIGHT_DISK_STATUS" "Temp Space" "$PREFLIGHT_DISK"
add_row "$PREFLIGHT_RAM_STATUS" "RAM" "$PREFLIGHT_RAM"
add_row "$PREFLIGHT_CPU_STATUS" "CPU" "$PREFLIGHT_CPU"
add_row "$PREFLIGHT_KVM_STATUS" "KVM" "$PREFLIGHT_KVM"
if [[ $no_drives -eq 1 ]];then
table_data+=$'\n'"[ERROR],Storage,No drives detected!"
else
for i in "${!DRIVE_NAMES[@]}";do
table_data+=$'\n'"[OK],${DRIVE_NAMES[$i]},${DRIVE_SIZES[$i]} ${DRIVE_MODELS[$i]:0:25}"
done
fi
gum style --foreground "#ff8700" --bold "SYSTEM INFORMATION"
echo ""
echo "$table_data"|gum table --print \
--border "none" \
--cell.foreground "#888888" \
--header.foreground "#ff8700"
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
if ! gum confirm "Continue with installation?" \
--affirmative "Continue" \
--negative "Cancel" \
--default=true \
--prompt.foreground "#ff8700" \
--selected.background "#ff8700" \
--unselected.foreground "#585858";then
log "INFO: User cancelled installation"
print_info "Installation cancelled by user"
exit 0
fi
fi
}
detect_network_interface(){
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
PREDICTABLE_NAME=$(udevadm info "/sys/class/net/$CURRENT_INTERFACE" 2>/dev/null|grep "ID_NET_NAME_PATH="|cut -d'=' -f2)
if [[ -z $PREDICTABLE_NAME ]];then
PREDICTABLE_NAME=$(udevadm info "/sys/class/net/$CURRENT_INTERFACE" 2>/dev/null|grep "ID_NET_NAME_ONBOARD="|cut -d'=' -f2)
fi
if [[ -z $PREDICTABLE_NAME ]];then
PREDICTABLE_NAME=$(ip -d link show "$CURRENT_INTERFACE" 2>/dev/null|grep "altname"|awk '{print $2}'|head -1)
fi
fi
if [[ -n $PREDICTABLE_NAME ]];then
DEFAULT_INTERFACE="$PREDICTABLE_NAME"
print_success "Detected predictable interface name:" "$PREDICTABLE_NAME (current: $CURRENT_INTERFACE)"
else
DEFAULT_INTERFACE="$CURRENT_INTERFACE"
print_warning "Could not detect predictable interface name"
print_warning "Using current interface: $CURRENT_INTERFACE"
print_warning "Proxmox might use different interface name - check after installation"
fi
AVAILABLE_ALTNAMES=$(ip -d link show|grep -v "lo:"|grep -E '(^[0-9]+:|altname)'|awk '/^[0-9]+:/ {interface=$2; gsub(/:/, "", interface); printf "%s", interface} /altname/ {printf ", %s", $2} END {print ""}'|sed 's/, $//')
if [[ -z $INTERFACE_NAME ]];then
INTERFACE_NAME="$DEFAULT_INTERFACE"
fi
}
_get_ipv4_via_ip_json(){
MAIN_IPV4_CIDR=$(ip -j address show "$CURRENT_INTERFACE" 2>/dev/null|jq -r '.[0].addr_info[] | select(.family == "inet" and .scope == "global") | "\(.local)/\(.prefixlen)"'|head -n1)
MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
MAIN_IPV4_GW=$(ip -j route 2>/dev/null|jq -r '.[] | select(.dst == "default") | .gateway'|head -n1)
[[ -n $MAIN_IPV4 ]]&&[[ -n $MAIN_IPV4_GW ]]
}
_get_ipv4_via_ip_text(){
MAIN_IPV4_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null|grep global|grep "inet "|awk '{print $2}'|head -n1)
MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
MAIN_IPV4_GW=$(ip route 2>/dev/null|grep default|awk '{print $3}'|head -n1)
[[ -n $MAIN_IPV4 ]]&&[[ -n $MAIN_IPV4_GW ]]
}
_get_ipv4_via_ifconfig(){
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
[[ -n $MAIN_IPV4 ]]&&[[ -n $MAIN_IPV4_GW ]]
}
_get_mac_and_ipv6(){
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
}
_validate_network_config(){
local max_attempts="$1"
if [[ -z $MAIN_IPV4 ]]||[[ -z $MAIN_IPV4_GW ]];then
print_error "Failed to detect network configuration after $max_attempts attempts"
print_error ""
print_error "Detected values:"
print_error "  Interface: ${CURRENT_INTERFACE:-not detected}"
print_error "  IPv4:      ${MAIN_IPV4:-not detected}"
print_error "  Gateway:   ${MAIN_IPV4_GW:-not detected}"
print_error ""
print_error "Available network interfaces:"
if command -v ip &>/dev/null;then
ip -brief link show 2>/dev/null|awk '{print "  " $1 " (" $2 ")"}' >&2||true
elif command -v ifconfig &>/dev/null;then
ifconfig -a 2>/dev/null|awk '/^[a-z]/ {print "  " $1}'|tr -d ':' >&2||true
fi
print_error ""
print_error "Possible causes:"
print_error "  - Network interface is down or not configured"
print_error "  - Running in an environment without network access"
print_error "  - Interface name mismatch (expected: $CURRENT_INTERFACE)"
log "ERROR: Network detection failed - MAIN_IPV4=$MAIN_IPV4, MAIN_IPV4_GW=$MAIN_IPV4_GW, INTERFACE=$CURRENT_INTERFACE"
exit 1
fi
if ! [[ $MAIN_IPV4 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];then
print_error "Invalid IPv4 address format detected: '$MAIN_IPV4'"
print_error "Expected format: X.X.X.X (e.g., 192.168.1.100)"
print_error "This may indicate a parsing issue with the network configuration"
log "ERROR: Invalid IPv4 address format: '$MAIN_IPV4' on interface $CURRENT_INTERFACE"
exit 1
fi
if ! [[ $MAIN_IPV4_GW =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];then
print_error "Invalid gateway address format detected: '$MAIN_IPV4_GW'"
print_error "Expected format: X.X.X.X (e.g., 192.168.1.1)"
print_error "Check if default route is configured correctly"
log "ERROR: Invalid gateway address format: '$MAIN_IPV4_GW'"
exit 1
fi
if ! ping -c 1 -W 2 "$MAIN_IPV4_GW" >/dev/null 2>&1;then
print_warning "Gateway $MAIN_IPV4_GW is not reachable (may be normal in rescue mode)"
log "WARNING: Gateway $MAIN_IPV4_GW not reachable"
fi
}
_calculate_ipv6_prefix(){
if [[ -n $IPV6_CIDR ]];then
local ipv6_prefix="${MAIN_IPV6%%:*:*:*:*}"
if [[ $ipv6_prefix == "$MAIN_IPV6" ]]||[[ -z $ipv6_prefix ]];then
ipv6_prefix=$(printf '%s' "$MAIN_IPV6"|cut -d':' -f1-4)
fi
FIRST_IPV6_CIDR="$ipv6_prefix:1::1/80"
else
FIRST_IPV6_CIDR=""
fi
}
collect_network_info(){
local max_attempts=3
local attempt=0
while [[ $attempt -lt $max_attempts ]];do
attempt=$((attempt+1))
if command -v ip &>/dev/null&&command -v jq &>/dev/null;then
_get_ipv4_via_ip_json&&break
elif command -v ip &>/dev/null;then
_get_ipv4_via_ip_text&&break
elif command -v ifconfig &>/dev/null;then
_get_ipv4_via_ifconfig&&break
fi
if [[ $attempt -lt $max_attempts ]];then
log "Network info attempt $attempt failed, retrying in 2 seconds..."
sleep 2
fi
done
_get_mac_and_ipv6
_validate_network_config "$max_attempts"
_calculate_ipv6_prefix
}
get_inputs_interactive(){
print_warning "Use the predictable name (enp*, eno*) for bare metal, not eth0"
local iface_prompt="Interface name (options: $AVAILABLE_ALTNAMES): "
read -r -e -p "$iface_prompt" -i "$INTERFACE_NAME" INTERFACE_NAME
printf "\033[4A\033[J"
print_success "Interface:" "$INTERFACE_NAME"
if [[ -n $PVE_HOSTNAME ]];then
print_success "Hostname:" "$PVE_HOSTNAME (from env)"
else
prompt_with_validation \
"Enter your hostname (e.g., pve, proxmox): " \
"pve" \
"validate_hostname" \
"Invalid hostname. Use only letters, numbers, and hyphens (1-63 chars)." \
"PVE_HOSTNAME" \
"Hostname: "
fi
if [[ -n $DOMAIN_SUFFIX ]];then
print_success "Domain:" "$DOMAIN_SUFFIX (from env)"
else
local domain_prompt="Enter domain suffix: "
read -r -e -p "$domain_prompt" -i "local" DOMAIN_SUFFIX
printf "\033[A\033[2K"
print_success "Domain:" "$DOMAIN_SUFFIX"
fi
if [[ -n $EMAIL ]];then
print_success "Email:" "$EMAIL (from env)"
else
prompt_with_validation \
"Enter your email address: " \
"admin@qoxi.cloud" \
"validate_email" \
"Invalid email address format." \
"EMAIL" \
"Email: "
fi
if [[ -n $NEW_ROOT_PASSWORD ]];then
if ! validate_password_with_error "$NEW_ROOT_PASSWORD";then
exit 1
fi
print_success "Password:" "******** (from env)"
else
echo -n "Enter root password (or press Enter to auto-generate): "
local input_password
local password_error
input_password=$(read_password "")
printf "\033[A\033[A\r\033[K"
if [[ -z $input_password ]];then
NEW_ROOT_PASSWORD=$(generate_password "$DEFAULT_PASSWORD_LENGTH")
PASSWORD_GENERATED="yes"
print_success "Password:" "auto-generated (will be shown at the end)"
else
password_error=$(get_password_error "$input_password")
while [[ -n $password_error ]];do
print_error "$password_error"
input_password=$(read_password "Enter root password: ")
password_error=$(get_password_error "$input_password")
done
NEW_ROOT_PASSWORD="$input_password"
printf "\033[A\r\033[K"
print_success "Password:" "********"
fi
fi
if [[ -n $PROXMOX_ISO_VERSION ]];then
print_success "Proxmox ISO:" "$PROXMOX_ISO_VERSION (from env/cli)"
else
local iso_list
get_available_proxmox_isos 5 >/tmp/iso_list.tmp&
show_progress $! "Fetching available Proxmox versions" --silent
iso_list=$(cat /tmp/iso_list.tmp 2>/dev/null)
rm -f /tmp/iso_list.tmp
if [[ -z $iso_list ]];then
print_warning "Could not fetch ISO list, will use latest"
PROXMOX_ISO_VERSION=""
else
local -a iso_array
local -a iso_menu_items
local first=true
while IFS= read -r iso;do
iso_array+=("$iso")
local version
version=$(get_iso_version "$iso")
if [[ $first == true ]];then
iso_menu_items+=("Proxmox VE $version|Latest version (recommended)")
first=false
else
iso_menu_items+=("Proxmox VE $version|")
fi
done <<<"$iso_list"
radio_menu \
"Proxmox VE Version (↑/↓ select, Enter confirm)" \
"Select which Proxmox VE version to install"$'\n' \
"${iso_menu_items[@]}"
PROXMOX_ISO_VERSION="${iso_array[$MENU_SELECTED]}"
local selected_version
selected_version=$(get_iso_version "$PROXMOX_ISO_VERSION")
if [[ $MENU_SELECTED -eq 0 ]];then
print_success "Proxmox VE:" "$selected_version (latest)"
else
print_success "Proxmox VE:" "$selected_version"
fi
fi
fi
if [[ -n $TIMEZONE ]];then
print_success "Timezone:" "$TIMEZONE (from env)"
else
local tz_options=("Europe/Kyiv" "Europe/London" "Europe/Berlin" "America/New_York" "America/Los_Angeles" "Asia/Tokyo" "UTC" "custom")
radio_menu \
"Timezone (↑/↓ select, Enter confirm)" \
"Select your server timezone"$'\n' \
"Europe/Kyiv|Ukraine" \
"Europe/London|United Kingdom (GMT/BST)" \
"Europe/Berlin|Germany, Central Europe (CET/CEST)" \
"America/New_York|US Eastern Time (EST/EDT)" \
"America/Los_Angeles|US Pacific Time (PST/PDT)" \
"Asia/Tokyo|Japan Standard Time (JST)" \
"UTC|Coordinated Universal Time" \
"Custom|Enter timezone manually"
if [[ $MENU_SELECTED -eq 7 ]];then
prompt_with_validation \
"Enter your timezone: " \
"Europe/Kyiv" \
"validate_timezone" \
"Invalid timezone. Use format like: Europe/London, America/New_York" \
"TIMEZONE" \
"Timezone: "
else
TIMEZONE="${tz_options[$MENU_SELECTED]}"
print_success "Timezone:" "$TIMEZONE"
fi
fi
if [[ -n $BRIDGE_MODE ]];then
print_success "Bridge mode:" "$BRIDGE_MODE (from env)"
else
local bridge_options=("internal" "external" "both")
local bridge_header="Configure network bridges for VMs and containers"$'\n'
bridge_header+="vmbr0 = external (bridged to physical NIC)"$'\n'
bridge_header+="vmbr1 = internal (NAT with private subnet)"$'\n'
radio_menu \
"Network Bridge Mode (↑/↓ select, Enter confirm)" \
"$bridge_header" \
"Internal only (NAT)|VMs use private IPs with NAT" \
"External only (Bridged)|VMs get IPs from router/DHCP" \
"Both bridges|Internal NAT + External bridged"
BRIDGE_MODE="${bridge_options[$MENU_SELECTED]}"
case "$BRIDGE_MODE" in
internal)print_success "Bridge mode:" "Internal NAT only (vmbr0)";;
external)print_success "Bridge mode:" "External bridged only (vmbr0)";;
both)print_success "Bridge mode:" "Both (vmbr0=external, vmbr1=internal)"
esac
fi
if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]];then
if [[ -n $PRIVATE_SUBNET ]];then
print_success "Private subnet:" "$PRIVATE_SUBNET (from env)"
else
local subnet_options=("10.0.0.0/24" "192.168.1.0/24" "172.16.0.0/24" "custom")
radio_menu \
"Private Subnet (↑/↓ select, Enter confirm)" \
"Internal network for VMs and containers"$'\n' \
"10.0.0.0/24|Class A private (recommended)" \
"192.168.1.0/24|Class C private (common home network)" \
"172.16.0.0/24|Class B private" \
"Custom|Enter subnet manually"
if [[ $MENU_SELECTED -eq 3 ]];then
prompt_with_validation \
"Enter your private subnet: " \
"10.0.0.0/24" \
"validate_subnet" \
"Invalid subnet. Use CIDR format like: 10.0.0.0/24" \
"PRIVATE_SUBNET" \
"Private subnet: "
else
PRIVATE_SUBNET="${subnet_options[$MENU_SELECTED]}"
print_success "Private subnet:" "$PRIVATE_SUBNET"
fi
fi
fi
if [[ -n $IPV6_MODE ]];then
if [[ $IPV6_MODE == "disabled" ]];then
MAIN_IPV6=""
IPV6_GATEWAY=""
FIRST_IPV6_CIDR=""
print_success "IPv6:" "disabled (from env)"
elif [[ $IPV6_MODE == "manual" ]];then
IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
if [[ -n $IPV6_ADDRESS ]];then
MAIN_IPV6="${IPV6_ADDRESS%/*}"
fi
print_success "IPv6:" "${MAIN_IPV6:-auto} (gateway: $IPV6_GATEWAY, from env)"
else
IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
if [[ -n $MAIN_IPV6 ]];then
print_success "IPv6:" "$MAIN_IPV6 (gateway: $IPV6_GATEWAY, from env)"
else
print_warning "IPv6: not detected"
fi
fi
else
local ipv6_options=("auto" "manual" "disabled")
local ipv6_header="Configure IPv6 networking for dual-stack support."$'\n'
if [[ -n $MAIN_IPV6 ]];then
ipv6_header+="Detected: $MAIN_IPV6"$'\n'
else
ipv6_header+="No IPv6 address detected on interface."$'\n'
fi
radio_menu \
"IPv6 Configuration (↑/↓ select, Enter confirm)" \
"$ipv6_header" \
"Auto|Use detected IPv6 address (recommended)" \
"Manual|Enter IPv6 address and gateway manually" \
"Disabled|IPv4-only configuration"
IPV6_MODE="${ipv6_options[$MENU_SELECTED]}"
if [[ $IPV6_MODE == "disabled" ]];then
MAIN_IPV6=""
IPV6_GATEWAY=""
FIRST_IPV6_CIDR=""
print_success "IPv6:" "disabled"
elif [[ $IPV6_MODE == "manual" ]];then
local ipv6_content="Enter your IPv6 address in CIDR notation."$'\n'
ipv6_content+="Example: 2001:db8::1/64"
input_box "IPv6 Address" "$ipv6_content" "IPv6 Address: " "${MAIN_IPV6:+$MAIN_IPV6/64}"
while [[ -n $INPUT_VALUE ]]&&! validate_ipv6_cidr "$INPUT_VALUE";do
print_error "Invalid IPv6 CIDR notation. Use format like: 2001:db8::1/64"
input_box "IPv6 Address" "$ipv6_content" "IPv6 Address: " "$INPUT_VALUE"
done
if [[ -n $INPUT_VALUE ]];then
IPV6_ADDRESS="$INPUT_VALUE"
MAIN_IPV6="${INPUT_VALUE%/*}"
fi
local gw_content="Enter your IPv6 gateway address."$'\n'
gw_content+="Default for Hetzner: fe80::1 (link-local)"
input_box "IPv6 Gateway" "$gw_content" "Gateway: " "${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
while [[ -n $INPUT_VALUE ]]&&! validate_ipv6_gateway "$INPUT_VALUE";do
print_error "Invalid IPv6 gateway address."
input_box "IPv6 Gateway" "$gw_content" "Gateway: " "$INPUT_VALUE"
done
IPV6_GATEWAY="${INPUT_VALUE:-$DEFAULT_IPV6_GATEWAY}"
print_success "IPv6:" "${MAIN_IPV6:-none} (gateway: $IPV6_GATEWAY)"
else
IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
if [[ -n $MAIN_IPV6 ]];then
print_success "IPv6:" "$MAIN_IPV6 (gateway: $IPV6_GATEWAY)"
else
print_warning "IPv6: not detected (will be IPv4-only)"
fi
fi
fi
if [[ ${DRIVE_COUNT:-0} -ge 2 ]];then
if [[ -n $ZFS_RAID ]];then
print_success "ZFS mode:" "$ZFS_RAID (from env)"
else
local zfs_options=("raid1" "raid0" "single")
local zfs_labels=("RAID-1 (mirror) - Recommended" "RAID-0 (stripe) - No redundancy" "Single drive - No redundancy")
radio_menu \
"ZFS Storage Mode (↑/↓ select, Enter confirm)" \
"Select ZFS pool configuration for your drives"$'\n' \
"${zfs_labels[0]}|Survives 1 disk failure" \
"${zfs_labels[1]}|2x space & speed, no redundancy" \
"${zfs_labels[2]}|Uses first drive only"
ZFS_RAID="${zfs_options[$MENU_SELECTED]}"
print_success "ZFS mode:" "${zfs_labels[$MENU_SELECTED]}"
fi
else
if [[ -n $ZFS_RAID ]];then
print_success "ZFS mode:" "$ZFS_RAID (from env)"
else
ZFS_RAID="single"
print_success "ZFS mode:" "single (1 drive detected)"
fi
fi
if [[ -n $PVE_REPO_TYPE ]];then
print_success "Repository:" "$PVE_REPO_TYPE (from env)"
if [[ $PVE_REPO_TYPE == "enterprise" && -n $PVE_SUBSCRIPTION_KEY ]];then
print_success "Subscription key:" "configured"
fi
else
local repo_options=("no-subscription" "enterprise" "test")
radio_menu \
"Proxmox Repository (↑/↓ select, Enter confirm)" \
"Select which repository to use for updates"$'\n' \
"No-Subscription|Free community repository (default)" \
"Enterprise|Stable, requires subscription key" \
"Test|Latest packages, may be unstable"
PVE_REPO_TYPE="${repo_options[$MENU_SELECTED]}"
if [[ $PVE_REPO_TYPE == "enterprise" ]];then
local key_content="Enterprise repository requires a subscription key."$'\n'
key_content+="Get your key from:"$'\n'
key_content+="https://www.proxmox.com/proxmox-ve/pricing"$'\n'
key_content+=$'\n'
key_content+="Format: pve1c-XXXXXXXXXX or pve2c-XXXXXXXXXX"
input_box "Proxmox Subscription Key" "$key_content" "Key: " ""
PVE_SUBSCRIPTION_KEY="$INPUT_VALUE"
if [[ -n $PVE_SUBSCRIPTION_KEY ]];then
print_success "Repository:" "enterprise (key configured)"
else
print_warning "Repository:" "enterprise (no key - will show warning in UI)"
fi
else
PVE_SUBSCRIPTION_KEY=""
print_success "Repository:" "$PVE_REPO_TYPE"
fi
fi
local all_features_from_env=true
[[ -z $DEFAULT_SHELL ]]&&all_features_from_env=false
[[ -z $INSTALL_VNSTAT ]]&&all_features_from_env=false
[[ -z $INSTALL_AUDITD ]]&&all_features_from_env=false
[[ -z $INSTALL_UNATTENDED_UPGRADES ]]&&all_features_from_env=false
if [[ $all_features_from_env == true ]];then
print_success "Default shell:" "$DEFAULT_SHELL (from env)"
if [[ $INSTALL_VNSTAT == "yes" ]];then
print_success "Bandwidth monitoring:" "enabled (from env)"
else
print_success "Bandwidth monitoring:" "disabled (from env)"
fi
if [[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]];then
print_success "Auto security updates:" "enabled (from env)"
else
print_success "Auto security updates:" "disabled (from env)"
fi
if [[ $INSTALL_AUDITD == "yes" ]];then
print_success "Audit logging:" "enabled (from env)"
else
print_success "Audit logging:" "disabled (from env)"
fi
else
local features_header="Select optional features to install."$'\n'
features_header+="Use ↑/↓ to navigate, Space to toggle, Enter to confirm."$'\n'
local zsh_default=1
local vnstat_default=1
local unattended_default=1
local auditd_default=0
[[ $DEFAULT_SHELL == "bash" ]]&&zsh_default=0
[[ $INSTALL_VNSTAT == "no" ]]&&vnstat_default=0
[[ $INSTALL_UNATTENDED_UPGRADES == "no" ]]&&unattended_default=0
[[ $INSTALL_AUDITD == "yes" ]]&&auditd_default=1
checkbox_menu \
"Optional Features (↑/↓ navigate, Space toggle, Enter confirm)" \
"$features_header" \
"ZSH shell|Modern shell with autosuggestions and syntax highlighting|$zsh_default" \
"vnstat|Bandwidth monitoring for tracking Hetzner transfer usage|$vnstat_default" \
"Unattended upgrades|Automatic security updates|$unattended_default" \
"auditd|Audit logging for administrative action tracking|$auditd_default"
if [[ ${CHECKBOX_RESULTS[0]} == "1" ]];then
DEFAULT_SHELL="zsh"
print_success "Default shell:" "zsh"
else
DEFAULT_SHELL="bash"
print_success "Default shell:" "bash"
fi
if [[ ${CHECKBOX_RESULTS[1]} == "1" ]];then
INSTALL_VNSTAT="yes"
print_success "Bandwidth monitoring:" "enabled (vnstat)"
else
INSTALL_VNSTAT="no"
print_success "Bandwidth monitoring:" "disabled"
fi
if [[ ${CHECKBOX_RESULTS[2]} == "1" ]];then
INSTALL_UNATTENDED_UPGRADES="yes"
print_success "Auto security updates:" "enabled"
else
INSTALL_UNATTENDED_UPGRADES="no"
print_success "Auto security updates:" "disabled"
fi
if [[ ${CHECKBOX_RESULTS[3]} == "1" ]];then
INSTALL_AUDITD="yes"
print_success "Audit logging:" "enabled (auditd)"
else
INSTALL_AUDITD="no"
print_success "Audit logging:" "disabled"
fi
fi
if [[ -n $CPU_GOVERNOR ]];then
print_success "Power profile:" "$CPU_GOVERNOR (from env)"
else
local governor_options=("performance" "ondemand" "powersave" "schedutil" "conservative")
local governor_header="Select CPU frequency scaling governor (power profile)."$'\n'
governor_header+="Affects power consumption, heat, and performance."$'\n'
radio_menu \
"Power Profile (↑/↓ select, Enter confirm)" \
"$governor_header" \
"Performance|Max speed, highest power (recommended)" \
"On-demand|Scales frequency based on load" \
"Powersave|Min speed, lowest power consumption" \
"Schedutil|Kernel scheduler-driven scaling" \
"Conservative|Gradual frequency scaling"
CPU_GOVERNOR="${governor_options[$MENU_SELECTED]}"
print_success "Power profile:" "$CPU_GOVERNOR"
fi
if [[ -n $SSH_PUBLIC_KEY ]];then
parse_ssh_key "$SSH_PUBLIC_KEY"
print_success "SSH key:" "$SSH_KEY_TYPE (from env)"
else
local DETECTED_SSH_KEY
DETECTED_SSH_KEY=$(get_rescue_ssh_key)
if [[ -n $DETECTED_SSH_KEY ]];then
parse_ssh_key "$DETECTED_SSH_KEY"
local ssh_header="! Password authentication will be DISABLED"$'\n'
ssh_header+=$'\n'
ssh_header+="  Detected key from Rescue System:"$'\n'
ssh_header+="  Type:    $SSH_KEY_TYPE"$'\n'
ssh_header+="  Key:     $SSH_KEY_SHORT"
if [[ -n $SSH_KEY_COMMENT ]];then
ssh_header+=$'\n'"  Comment: $SSH_KEY_COMMENT"
fi
ssh_header+=$'\n'
radio_menu \
"SSH Public Key (↑/↓ select, Enter confirm)" \
"$ssh_header" \
"Use detected key|Already configured in Hetzner" \
"Enter different key|Paste your own SSH public key"
if [[ $MENU_SELECTED -eq 0 ]];then
SSH_PUBLIC_KEY="$DETECTED_SSH_KEY"
print_success "SSH key:" "configured ($SSH_KEY_TYPE)"
else
SSH_PUBLIC_KEY=""
fi
fi
if [[ -z $SSH_PUBLIC_KEY ]];then
local ssh_content="! Password authentication will be DISABLED"$'\n'
if [[ -z $DETECTED_SSH_KEY ]];then
ssh_content+=$'\n'"No SSH key detected in Rescue System."
fi
ssh_content+=$'\n'$'\n'"Paste your SSH public key below:"$'\n'
ssh_content+="(Usually from ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)"
input_box "SSH Public Key Configuration" "$ssh_content" "SSH Public Key: " ""
while [[ -z $INPUT_VALUE ]]||! validate_ssh_key "$INPUT_VALUE";do
if [[ -z $INPUT_VALUE ]];then
print_error "SSH public key is required for secure access!"
else
print_warning "SSH key format may be invalid. Continue anyway? (y/n): "
read -rsn1 confirm
echo ""
if [[ $confirm =~ ^[Yy]$ ]];then
break
fi
fi
input_box "SSH Public Key Configuration" "$ssh_content" "SSH Public Key: " ""
done
SSH_PUBLIC_KEY="$INPUT_VALUE"
parse_ssh_key "$SSH_PUBLIC_KEY"
print_success "SSH key:" "configured ($SSH_KEY_TYPE)"
fi
fi
if [[ -n $INSTALL_TAILSCALE ]];then
if [[ $INSTALL_TAILSCALE == "yes" ]];then
TAILSCALE_SSH="${TAILSCALE_SSH:-yes}"
TAILSCALE_WEBUI="${TAILSCALE_WEBUI:-yes}"
if [[ -n $TAILSCALE_AUTH_KEY ]];then
print_success "Tailscale:" "yes (auto-connect, from env)"
else
print_success "Tailscale:" "yes (manual auth, from env)"
fi
else
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH="no"
TAILSCALE_WEBUI="no"
print_success "Tailscale:" "skipped (from env)"
fi
else
local ts_header="Tailscale provides secure remote access to your server."$'\n'
ts_header+="Auth key: https://login.tailscale.com/admin/settings/keys"$'\n'
radio_menu \
"Tailscale VPN - Optional (↑/↓ select, Enter confirm)" \
"$ts_header" \
"Install Tailscale|Recommended for secure remote access" \
"Skip installation|Install Tailscale later if needed"
if [[ $MENU_SELECTED -eq 0 ]];then
INSTALL_TAILSCALE="yes"
TAILSCALE_SSH="yes"
TAILSCALE_WEBUI="yes"
TAILSCALE_DISABLE_SSH="no"
if [[ -z $TAILSCALE_AUTH_KEY ]];then
local auth_content="Auth key enables automatic configuration."$'\n'
auth_content+="Leave empty for manual auth after reboot."$'\n'
auth_content+=$'\n'
auth_content+="For unattended setup, use a reusable auth key"$'\n'
auth_content+="with tags and expiry for better security."
input_box "Tailscale Auth Key (optional)" "$auth_content" "Auth Key: " ""
TAILSCALE_AUTH_KEY="$INPUT_VALUE"
fi
if [[ -n $TAILSCALE_AUTH_KEY ]];then
TAILSCALE_DISABLE_SSH="yes"
STEALTH_MODE="yes"
print_success "Tailscale:" "will be installed (auto-connect)"
print_success "OpenSSH:" "will be disabled on first boot"
print_success "Stealth firewall:" "enabled (server hidden from internet)"
else
print_warning "Tailscale:" "enabled (no key - manual auth required)"
STEALTH_MODE="no"
fi
else
INSTALL_TAILSCALE="no"
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH="no"
TAILSCALE_WEBUI="no"
TAILSCALE_DISABLE_SSH="no"
STEALTH_MODE="no"
print_success "Tailscale:" "installation skipped"
fi
fi
if [[ $INSTALL_TAILSCALE != "yes" ]];then
if [[ -n $SSL_TYPE ]];then
print_success "SSL certificate:" "$SSL_TYPE (from env)"
else
local ssl_options=("self-signed" "letsencrypt")
local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
local ssl_header="Configure SSL certificate for Proxmox Web UI."$'\n'
ssl_header+=$'\n'
ssl_header+="! For Let's Encrypt, before continuing ensure:"$'\n'
ssl_header+="  - Domain $le_fqdn is registered"$'\n'
ssl_header+="  - DNS A record points to ${MAIN_IPV4_CIDR%/*}"$'\n'
ssl_header+="  - Port 80 is accessible from the internet"
radio_menu \
"SSL Certificate (↑/↓ select, Enter confirm)" \
"$ssl_header" \
"Self-signed|Default Proxmox certificate (recommended)" \
"Let's Encrypt|Requires domain pointing to this server"
SSL_TYPE="${ssl_options[$MENU_SELECTED]}"
if [[ $SSL_TYPE == "letsencrypt" ]];then
local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
local expected_ip="${MAIN_IPV4_CIDR%/*}"
local max_attempts=3
local attempt=1
local dns_result=1
local dns_tmp="/tmp/dns_check_$$"
while [[ $attempt -le $max_attempts ]];do
(resolved_ip=$(dig +short A "$le_fqdn" @1.1.1.1 2>/dev/null|grep -E '^[0-9]+\.'|head -1)
if [[ -z $resolved_ip ]];then
resolved_ip=$(dig +short A "$le_fqdn" @8.8.8.8 2>/dev/null|grep -E '^[0-9]+\.'|head -1)
fi
if [[ -z $resolved_ip ]];then
echo "1:" >"$dns_tmp"
elif [[ $resolved_ip == "$expected_ip" ]];then
echo "0:$resolved_ip" >"$dns_tmp"
else
echo "2:$resolved_ip" >"$dns_tmp"
fi) \
&
local check_pid=$!
show_progress $check_pid "Checking DNS: $le_fqdn → $expected_ip (attempt $attempt/$max_attempts)" --silent
if [[ -f $dns_tmp ]];then
dns_result=$(cut -d: -f1 <"$dns_tmp")
DNS_RESOLVED_IP=$(cut -d: -f2 <"$dns_tmp")
rm -f "$dns_tmp"
else
dns_result=1
fi
if [[ $dns_result -eq 0 ]];then
print_success "SSL:" "Let's Encrypt (DNS verified: $le_fqdn → $expected_ip)"
break
fi
if [[ $dns_result -eq 1 ]];then
print_error "DNS check failed: $le_fqdn does not resolve"
else
print_error "DNS mismatch: $le_fqdn → $DNS_RESOLVED_IP (expected: $expected_ip)"
fi
if [[ $attempt -lt $max_attempts ]];then
print_info "Retrying in $DNS_RETRY_DELAY seconds... (Press Ctrl+C to cancel)"
sleep "$DNS_RETRY_DELAY"
fi
((attempt++))
done
rm -f "$dns_tmp" 2>/dev/null
if [[ $dns_result -ne 0 ]];then
echo ""
print_error "DNS validation failed after $max_attempts attempts"
echo ""
print_info "To fix this:"
print_info "  1. Go to your DNS provider"
print_info "  2. Create/update A record: $le_fqdn → $expected_ip"
print_info "  3. Wait for DNS propagation (usually 1-5 minutes)"
print_info "  4. Run this installer again"
echo ""
exit 1
fi
else
print_success "SSL:" "Self-signed certificate"
fi
fi
else
SSL_TYPE="self-signed"
fi
}
get_system_inputs(){
detect_network_interface
collect_network_info
get_inputs_interactive
FQDN="$PVE_HOSTNAME.$DOMAIN_SUFFIX"
if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]];then
PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET"|cut -d'/' -f1|rev|cut -d'.' -f2-|rev)
PRIVATE_IP="$PRIVATE_CIDR.1"
SUBNET_MASK=$(echo "$PRIVATE_SUBNET"|cut -d'/' -f2)
PRIVATE_IP_CIDR="$PRIVATE_IP/$SUBNET_MASK"
fi
}
display_config_preview(){
local inner_width=$((MENU_BOX_WIDTH-6))
local content=""
content+="|--- Basic Settings ---|"$'\n'
content+="|Hostname|$PVE_HOSTNAME.$DOMAIN_SUFFIX"$'\n'
content+="|Email|$EMAIL"$'\n'
content+="|Password|$([ "$PASSWORD_GENERATED" == "yes" ]&&echo "auto-generated"||echo "********")"$'\n'
content+="|Timezone|$TIMEZONE"$'\n'
content+="|--- Network ---"$'\n'
content+="|Interface|$INTERFACE_NAME"$'\n'
content+="|IPv4|$MAIN_IPV4_CIDR"$'\n'
content+="|Gateway|$MAIN_IPV4_GW"$'\n'
case "$BRIDGE_MODE" in
internal)content+="|Bridge|Internal NAT (vmbr0)";;
external)content+="|Bridge|External bridged (vmbr0)";;
both)content+="|Bridge|Both (vmbr0=ext, vmbr1=int)"
esac
content+=$'\n'
if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]];then
content+="|Private subnet|$PRIVATE_SUBNET"$'\n'
fi
content+="|--- IPv6 ---"$'\n'
case "$IPV6_MODE" in
disabled)content+="|IPv6|Disabled"$'\n'
;;
manual)content+="|IPv6|${MAIN_IPV6:-not set}"$'\n'
content+="|IPv6 Gateway|$IPV6_GATEWAY"$'\n'
;;
auto|*)if
[[ -n $MAIN_IPV6 ]]
then
content+="|IPv6|$MAIN_IPV6 (auto)"$'\n'
content+="|IPv6 Gateway|${IPV6_GATEWAY:-fe80::1}"$'\n'
else
content+="|IPv6|Not detected"$'\n'
fi
esac
content+="|--- Storage ---"$'\n'
local zfs_desc
case "$ZFS_RAID" in
raid1)zfs_desc="RAID-1 (mirror)";;
raid0)zfs_desc="RAID-0 (stripe)";;
single)zfs_desc="Single drive";;
*)zfs_desc="$ZFS_RAID"
esac
content+="|ZFS Mode|$zfs_desc"$'\n'
content+="|Drives|${DRIVES[*]}"$'\n'
content+="|--- Proxmox ---"$'\n'
if [[ -n $PROXMOX_ISO_VERSION ]];then
local pve_version
pve_version=$(get_iso_version "$PROXMOX_ISO_VERSION" 2>/dev/null||echo "$PROXMOX_ISO_VERSION")
content+="|Version|$pve_version"$'\n'
else
content+="|Version|Latest"$'\n'
fi
content+="|Repository|${PVE_REPO_TYPE:-no-subscription}"$'\n'
content+="|--- SSL ---"$'\n'
if [[ $INSTALL_TAILSCALE == "yes" ]];then
content+="|SSL|Self-signed (Tailscale HTTPS)"$'\n'
else
content+="|SSL|${SSL_TYPE:-self-signed}"$'\n'
fi
content+="|--- VPN ---"$'\n'
if [[ $INSTALL_TAILSCALE == "yes" ]];then
if [[ -n $TAILSCALE_AUTH_KEY ]];then
content+="|Tailscale|Enabled (auto-connect)"$'\n'
else
content+="|Tailscale|Enabled (manual auth)"$'\n'
fi
if [[ $STEALTH_MODE == "yes" ]];then
content+="|Stealth mode|Enabled"$'\n'
fi
if [[ $TAILSCALE_DISABLE_SSH == "yes" ]];then
content+="|OpenSSH|Will be disabled"$'\n'
fi
else
content+="|Tailscale|Not installed"$'\n'
fi
content+="|--- Optional ---"$'\n'
content+="|Shell|${DEFAULT_SHELL:-bash}"$'\n'
content+="|Power profile|${CPU_GOVERNOR:-performance}"$'\n'
local features=""
[[ $INSTALL_VNSTAT == "yes" ]]&&features+="vnstat, "
[[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]]&&features+="auto-updates, "
[[ $INSTALL_AUDITD == "yes" ]]&&features+="auditd, "
if [[ -n $features ]];then
content+="|Features|${features%, }"$'\n'
else
content+="|Features|None"$'\n'
fi
content+="|--- SSH ---"$'\n'
if [[ -n $SSH_PUBLIC_KEY ]];then
parse_ssh_key "$SSH_PUBLIC_KEY"
content+="|SSH Key|$SSH_KEY_TYPE"
if [[ -n $SSH_KEY_COMMENT ]];then
content+=" ($SSH_KEY_COMMENT)"
fi
content+=$'\n'
else
content+="|SSH Key|Not configured"$'\n'
fi
content="${content%$'\n'}"
{
echo "Configuration Review"
echo "$content"|column -t -s '|'|while IFS= read -r line;do
printf "%-${inner_width}s\n" "$line"
done
echo ""
printf "%-${inner_width}s\n" "Press ENTER_KEY to start installation"
printf "%-${inner_width}s\n" "Press E_KEY to edit configuration"
printf "%-${inner_width}s\n" "Press Q_KEY to quit"
}|boxes -d stone -p a1 -s "$MENU_BOX_WIDTH"|_colorize_preview
}
_colorize_preview(){
local box_width=$MENU_BOX_WIDTH
local inner_width=$((box_width-1))
while IFS= read -r line;do
if [[ $line =~ ^\+[-+]+\+$ ]];then
echo "$CLR_GRAY$line$CLR_RESET"
elif [[ $line =~ ^(\|)(.*)\|$ ]];then
local content="${BASH_REMATCH[2]}"
local visible_content="$content"
if [[ $content == *"---"* ]];then
content="$CLR_CYAN$content$CLR_RESET"
fi
if [[ $visible_content == *"Press"* ]];then
visible_content="${visible_content//ENTER_KEY/Enter}"
visible_content="${visible_content//E_KEY/e}"
visible_content="${visible_content//Q_KEY/q}"
local visible_len=${#visible_content}
local padding=$((inner_width-visible_len))
content="${content//ENTER_KEY/${CLR_CYAN}Enter$CLR_GRAY}"
content="${content//E_KEY/${CLR_CYAN}e$CLR_GRAY}"
content="${content//Q_KEY/${CLR_CYAN}q$CLR_GRAY}"
content="$CLR_GRAY$content"
printf -v content "%s%${padding}s$CLR_RESET" "$content" ""
fi
echo "$CLR_GRAY|$CLR_RESET$content$CLR_GRAY|$CLR_RESET"
else
echo "$line"
fi
done
}
edit_configuration(){
local -a edit_sections=()
local -a edit_actions=()
edit_sections+=("Basic Settings|Hostname, domain, email, password, timezone")
edit_actions+=("_edit_basic_settings")
edit_sections+=("Network|Bridge mode, private subnet")
edit_actions+=("_edit_network_settings")
edit_sections+=("IPv6|IPv6 mode and settings")
edit_actions+=("_edit_ipv6_settings")
if [[ ${DRIVE_COUNT:-0} -ge 2 ]];then
edit_sections+=("Storage|ZFS RAID level ($DRIVE_COUNT drives)")
else
edit_sections+=("Storage|Single drive mode")
fi
edit_actions+=("_edit_storage_settings")
edit_sections+=("Proxmox|Version and repository")
edit_actions+=("_edit_proxmox_settings")
if [[ $INSTALL_TAILSCALE != "yes" ]];then
edit_sections+=("SSL|Certificate type")
edit_actions+=("_edit_ssl_settings")
fi
edit_sections+=("Tailscale|VPN configuration")
edit_actions+=("_edit_tailscale_settings")
edit_sections+=("Optional|Shell, packages, power profile")
edit_actions+=("_edit_optional_settings")
edit_sections+=("SSH Key|Public key for authentication")
edit_actions+=("_edit_ssh_settings")
edit_sections+=("Done|Return to configuration review")
edit_actions+=("return")
radio_menu \
"Edit Configuration (select section)" \
"Select which section to edit"$'\n' \
"${edit_sections[@]}"
local action="${edit_actions[$MENU_SELECTED]}"
if [[ $action == "return" ]];then
return 0
else
$action
fi
return 0
}
_edit_basic_settings(){
local hostname_content="Enter the short hostname for your server."$'\n'
hostname_content+="Example: pve, proxmox, server01"
input_box "Hostname" "$hostname_content" "Hostname: " "$PVE_HOSTNAME"
while [[ -n $INPUT_VALUE ]]&&! validate_hostname "$INPUT_VALUE";do
print_error "Invalid hostname. Use only letters, numbers, and hyphens (1-63 chars)."
input_box "Hostname" "$hostname_content" "Hostname: " "$INPUT_VALUE"
done
[[ -n $INPUT_VALUE ]]&&PVE_HOSTNAME="$INPUT_VALUE"
print_success "Hostname:" "$PVE_HOSTNAME"
local domain_content="Enter the domain suffix for your server."$'\n'
domain_content+="Example: local, example.com"
input_box "Domain" "$domain_content" "Domain: " "$DOMAIN_SUFFIX"
[[ -n $INPUT_VALUE ]]&&DOMAIN_SUFFIX="$INPUT_VALUE"
print_success "Domain:" "$DOMAIN_SUFFIX"
local email_content="Enter your email address for notifications."
input_box "Email" "$email_content" "Email: " "$EMAIL"
while [[ -n $INPUT_VALUE ]]&&! validate_email "$INPUT_VALUE";do
print_error "Invalid email address format."
input_box "Email" "$email_content" "Email: " "$INPUT_VALUE"
done
[[ -n $INPUT_VALUE ]]&&EMAIL="$INPUT_VALUE"
print_success "Email:" "$EMAIL"
local password_content="Enter new root password or leave empty to keep current."$'\n'
password_content+="Leave empty to auto-generate a new password."
input_box "Password" "$password_content" "Password: " ""
if [[ -n $INPUT_VALUE ]];then
local password_error
password_error=$(get_password_error "$INPUT_VALUE")
while [[ -n $password_error ]];do
print_error "$password_error"
input_box "Password" "$password_content" "Password: " ""
[[ -z $INPUT_VALUE ]]&&break
password_error=$(get_password_error "$INPUT_VALUE")
done
if [[ -n $INPUT_VALUE ]];then
NEW_ROOT_PASSWORD="$INPUT_VALUE"
PASSWORD_GENERATED="no"
print_success "Password:" "********"
fi
fi
local tz_options=("Europe/Kyiv" "Europe/London" "Europe/Berlin" "America/New_York" "America/Los_Angeles" "Asia/Tokyo" "UTC" "custom")
radio_menu \
"Timezone (select or choose Custom)" \
"Select your server timezone"$'\n' \
"Europe/Kyiv|Ukraine" \
"Europe/London|United Kingdom" \
"Europe/Berlin|Germany" \
"America/New_York|US Eastern" \
"America/Los_Angeles|US Pacific" \
"Asia/Tokyo|Japan" \
"UTC|Coordinated Universal Time" \
"Custom|Enter timezone manually"
if [[ $MENU_SELECTED -eq 7 ]];then
local tz_content="Enter your timezone in Region/City format."$'\n'
tz_content+="Example: Europe/London, America/New_York"
input_box "Timezone" "$tz_content" "Timezone: " "$TIMEZONE"
while [[ -n $INPUT_VALUE ]]&&! validate_timezone "$INPUT_VALUE";do
print_error "Invalid timezone format."
input_box "Timezone" "$tz_content" "Timezone: " "$INPUT_VALUE"
done
[[ -n $INPUT_VALUE ]]&&TIMEZONE="$INPUT_VALUE"
else
TIMEZONE="${tz_options[$MENU_SELECTED]}"
fi
print_success "Timezone:" "$TIMEZONE"
FQDN="$PVE_HOSTNAME.$DOMAIN_SUFFIX"
}
_edit_network_settings(){
local prev_bridge_mode="$BRIDGE_MODE"
local bridge_options=("internal" "external" "both")
local bridge_header="Configure network bridges for VMs"$'\n'
bridge_header+="vmbr0 = external (bridged to NIC)"$'\n'
bridge_header+="vmbr1 = internal (NAT)"
radio_menu \
"Network Bridge Mode" \
"$bridge_header" \
"Internal only (NAT)|VMs use private IPs" \
"External only (Bridged)|VMs get IPs from router" \
"Both bridges|Internal + External"
BRIDGE_MODE="${bridge_options[$MENU_SELECTED]}"
print_success "Bridge mode:" "$BRIDGE_MODE"
if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]];then
if [[ $prev_bridge_mode == "external" ]];then
echo ""
print_info "Internal bridge enabled - configuring private subnet..."
echo ""
fi
local subnet_options=("10.0.0.0/24" "192.168.1.0/24" "172.16.0.0/24" "custom")
radio_menu \
"Private Subnet" \
"Select private subnet for internal bridge"$'\n' \
"10.0.0.0/24|Class A private (recommended)" \
"192.168.1.0/24|Class C private" \
"172.16.0.0/24|Class B private" \
"Custom|Enter subnet manually"
if [[ $MENU_SELECTED -eq 3 ]];then
local subnet_content="Enter private subnet in CIDR notation."$'\n'
subnet_content+="Example: 10.0.0.0/24, 192.168.100.0/24"
input_box "Private Subnet" "$subnet_content" "Subnet: " "$PRIVATE_SUBNET"
while [[ -n $INPUT_VALUE ]]&&! validate_subnet "$INPUT_VALUE";do
print_error "Invalid subnet format."
input_box "Private Subnet" "$subnet_content" "Subnet: " "$INPUT_VALUE"
done
[[ -n $INPUT_VALUE ]]&&PRIVATE_SUBNET="$INPUT_VALUE"
else
PRIVATE_SUBNET="${subnet_options[$MENU_SELECTED]}"
fi
print_success "Private subnet:" "$PRIVATE_SUBNET"
PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET"|cut -d'/' -f1|rev|cut -d'.' -f2-|rev)
PRIVATE_IP="$PRIVATE_CIDR.1"
SUBNET_MASK=$(echo "$PRIVATE_SUBNET"|cut -d'/' -f2)
PRIVATE_IP_CIDR="$PRIVATE_IP/$SUBNET_MASK"
else
PRIVATE_SUBNET=""
PRIVATE_CIDR=""
PRIVATE_IP=""
PRIVATE_IP_CIDR=""
fi
}
_edit_ipv6_settings(){
local ipv6_options=("auto" "manual" "disabled")
local ipv6_header="Configure IPv6 networking."$'\n'
if [[ -n $MAIN_IPV6 ]];then
ipv6_header+="Current: $MAIN_IPV6"
else
ipv6_header+="No IPv6 detected on interface."
fi
radio_menu \
"IPv6 Configuration" \
"$ipv6_header" \
"Auto|Use detected IPv6" \
"Manual|Enter IPv6 manually" \
"Disabled|IPv4-only"
IPV6_MODE="${ipv6_options[$MENU_SELECTED]}"
if [[ $IPV6_MODE == "disabled" ]];then
MAIN_IPV6=""
IPV6_GATEWAY=""
FIRST_IPV6_CIDR=""
print_success "IPv6:" "disabled"
elif [[ $IPV6_MODE == "manual" ]];then
local ipv6_content="Enter IPv6 address in CIDR notation."$'\n'
ipv6_content+="Example: 2001:db8::1/64"
input_box "IPv6 Address" "$ipv6_content" "IPv6: " "${MAIN_IPV6:+$MAIN_IPV6/64}"
while [[ -n $INPUT_VALUE ]]&&! validate_ipv6_cidr "$INPUT_VALUE";do
print_error "Invalid IPv6 CIDR notation."
input_box "IPv6 Address" "$ipv6_content" "IPv6: " "$INPUT_VALUE"
done
if [[ -n $INPUT_VALUE ]];then
IPV6_ADDRESS="$INPUT_VALUE"
MAIN_IPV6="${INPUT_VALUE%/*}"
fi
local gw_content="Enter IPv6 gateway address."$'\n'
gw_content+="Default for Hetzner: fe80::1"
input_box "IPv6 Gateway" "$gw_content" "Gateway: " "${IPV6_GATEWAY:-fe80::1}"
while [[ -n $INPUT_VALUE ]]&&! validate_ipv6_gateway "$INPUT_VALUE";do
print_error "Invalid IPv6 gateway."
input_box "IPv6 Gateway" "$gw_content" "Gateway: " "$INPUT_VALUE"
done
IPV6_GATEWAY="${INPUT_VALUE:-fe80::1}"
print_success "IPv6:" "$MAIN_IPV6 (gateway: $IPV6_GATEWAY)"
else
IPV6_GATEWAY="${IPV6_GATEWAY:-fe80::1}"
if [[ -n $MAIN_IPV6 ]];then
print_success "IPv6:" "$MAIN_IPV6 (auto)"
else
print_warning "IPv6:" "not detected"
fi
fi
}
_edit_storage_settings(){
if [[ ${DRIVE_COUNT:-0} -lt 2 ]];then
print_warning "Only one drive detected - RAID options not available"
ZFS_RAID="single"
return
fi
local zfs_options=("raid1" "raid0" "single")
radio_menu \
"ZFS Storage Mode" \
"Select ZFS pool configuration"$'\n' \
"RAID-1 (mirror)|Survives 1 disk failure" \
"RAID-0 (stripe)|2x space, no redundancy" \
"Single drive|Uses first drive only"
ZFS_RAID="${zfs_options[$MENU_SELECTED]}"
print_success "ZFS mode:" "$ZFS_RAID"
}
_edit_proxmox_settings(){
local repo_options=("no-subscription" "enterprise" "test")
radio_menu \
"Proxmox Repository" \
"Select repository for updates"$'\n' \
"No-Subscription|Free community repository" \
"Enterprise|Stable, requires subscription" \
"Test|Latest, may be unstable"
PVE_REPO_TYPE="${repo_options[$MENU_SELECTED]}"
if [[ $PVE_REPO_TYPE == "enterprise" ]];then
local key_content="Enter Proxmox subscription key."$'\n'
key_content+="Format: pve1c-XXXXXXXXXX"
input_box "Subscription Key" "$key_content" "Key: " "$PVE_SUBSCRIPTION_KEY"
PVE_SUBSCRIPTION_KEY="$INPUT_VALUE"
else
PVE_SUBSCRIPTION_KEY=""
fi
print_success "Repository:" "$PVE_REPO_TYPE"
}
_edit_ssl_settings(){
if [[ $INSTALL_TAILSCALE == "yes" ]];then
print_info "SSL is managed by Tailscale when VPN is enabled"
SSL_TYPE="self-signed"
return
fi
local ssl_options=("self-signed" "letsencrypt")
radio_menu \
"SSL Certificate" \
"Select SSL certificate type"$'\n' \
"Self-signed|Default Proxmox certificate" \
"Let's Encrypt|Requires domain pointing to server"
SSL_TYPE="${ssl_options[$MENU_SELECTED]}"
if [[ $SSL_TYPE == "letsencrypt" ]];then
local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
local expected_ip="${MAIN_IPV4_CIDR%/*}"
print_info "Verifying DNS: $le_fqdn -> $expected_ip"
local resolved_ip
resolved_ip=$(dig +short A "$le_fqdn" @1.1.1.1 2>/dev/null|grep -E '^[0-9]+\.'|head -1)
if [[ $resolved_ip == "$expected_ip" ]];then
print_success "SSL:" "Let's Encrypt (DNS verified)"
else
print_error "DNS mismatch: $le_fqdn -> ${resolved_ip:-not found} (expected: $expected_ip)"
print_warning "Let's Encrypt may fail. Falling back to self-signed."
SSL_TYPE="self-signed"
fi
fi
print_success "SSL:" "$SSL_TYPE"
}
_edit_tailscale_settings(){
local ts_header="Tailscale provides secure remote access."
radio_menu \
"Tailscale VPN" \
"$ts_header" \
"Install Tailscale|Recommended for secure access" \
"Skip|Do not install Tailscale"
if [[ $MENU_SELECTED -eq 0 ]];then
INSTALL_TAILSCALE="yes"
TAILSCALE_SSH="yes"
TAILSCALE_WEBUI="yes"
local auth_content="Auth key enables automatic setup."$'\n'
auth_content+="Leave empty for manual auth after reboot."
input_box "Tailscale Auth Key (optional)" "$auth_content" "Auth Key: " "$TAILSCALE_AUTH_KEY"
TAILSCALE_AUTH_KEY="$INPUT_VALUE"
if [[ -n $TAILSCALE_AUTH_KEY ]];then
TAILSCALE_DISABLE_SSH="yes"
STEALTH_MODE="yes"
print_success "Tailscale:" "enabled (auto-connect)"
print_success "Stealth mode:" "enabled"
else
TAILSCALE_DISABLE_SSH="no"
STEALTH_MODE="no"
print_warning "Tailscale:" "enabled (manual auth required)"
fi
else
local was_tailscale_enabled="$INSTALL_TAILSCALE"
INSTALL_TAILSCALE="no"
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH="no"
TAILSCALE_WEBUI="no"
TAILSCALE_DISABLE_SSH="no"
STEALTH_MODE="no"
print_success "Tailscale:" "not installed"
if [[ $was_tailscale_enabled == "yes" ]];then
echo ""
print_info "Tailscale disabled - configuring SSL certificate..."
echo ""
_edit_ssl_settings
fi
fi
}
_edit_optional_settings(){
radio_menu \
"Default Shell" \
"Select default shell for root user"$'\n' \
"ZSH|Modern shell with plugins" \
"Bash|Standard shell"
DEFAULT_SHELL=$([ $MENU_SELECTED -eq 0 ]&&echo "zsh"||echo "bash")
print_success "Shell:" "$DEFAULT_SHELL"
local governor_options=("performance" "ondemand" "powersave" "schedutil" "conservative")
radio_menu \
"Power Profile" \
"Select CPU frequency scaling"$'\n' \
"Performance|Max speed" \
"On-demand|Scale based on load" \
"Powersave|Min speed" \
"Schedutil|Kernel scheduler-driven" \
"Conservative|Gradual scaling"
CPU_GOVERNOR="${governor_options[$MENU_SELECTED]}"
print_success "Power profile:" "$CPU_GOVERNOR"
local vnstat_default
local unattended_default
local auditd_default
vnstat_default=$([[ $INSTALL_VNSTAT == "yes" ]]&&echo "1"||echo "0")
unattended_default=$([[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]]&&echo "1"||echo "0")
auditd_default=$([[ $INSTALL_AUDITD == "yes" ]]&&echo "1"||echo "0")
checkbox_menu \
"Optional Packages" \
"Select additional packages to install"$'\n' \
"vnstat|Bandwidth monitoring|$vnstat_default" \
"Unattended upgrades|Automatic security updates|$unattended_default" \
"auditd|Audit logging|$auditd_default"
INSTALL_VNSTAT=$([[ ${CHECKBOX_RESULTS[0]} == "1" ]]&&echo "yes"||echo "no")
INSTALL_UNATTENDED_UPGRADES=$([[ ${CHECKBOX_RESULTS[1]} == "1" ]]&&echo "yes"||echo "no")
INSTALL_AUDITD=$([[ ${CHECKBOX_RESULTS[2]} == "1" ]]&&echo "yes"||echo "no")
print_success "vnstat:" "$INSTALL_VNSTAT"
print_success "Auto-updates:" "$INSTALL_UNATTENDED_UPGRADES"
print_success "auditd:" "$INSTALL_AUDITD"
}
_edit_ssh_settings(){
local ssh_content="Enter your SSH public key."$'\n'
ssh_content+="Usually from ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub"
local current_key=""
if [[ -n $SSH_PUBLIC_KEY ]];then
current_key="$SSH_PUBLIC_KEY"
fi
input_box "SSH Public Key" "$ssh_content" "SSH Key: " "$current_key"
if [[ -n $INPUT_VALUE ]];then
if validate_ssh_key "$INPUT_VALUE";then
SSH_PUBLIC_KEY="$INPUT_VALUE"
parse_ssh_key "$SSH_PUBLIC_KEY"
print_success "SSH key:" "$SSH_KEY_TYPE"
else
print_warning "SSH key format may be invalid"
echo -n "Use anyway? (y/n): "
read -rsn1 confirm
echo ""
if [[ $confirm =~ ^[Yy]$ ]];then
SSH_PUBLIC_KEY="$INPUT_VALUE"
parse_ssh_key "$SSH_PUBLIC_KEY"
print_success "SSH key:" "$SSH_KEY_TYPE"
fi
fi
fi
}
show_configuration_review(){
while true;do
clear
show_banner --no-info
display_config_preview
local action
IFS= read -rsn1 action
case "$action" in
""|" ")return 0
;;
e|E)clear
show_banner --no-info
edit_configuration
;;
q|Q)print_info "Installation cancelled by user"
exit 0
;;
*)
esac
done
}
prepare_packages(){
log "Starting package preparation"
log "Checking Proxmox repository availability"
if ! curl -fsSL --max-time 10 "https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg" >/dev/null 2>&1;then
print_error "Cannot reach Proxmox repository"
log "ERROR: Cannot reach Proxmox repository"
exit 1
fi
log "Adding Proxmox repository"
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >/etc/apt/sources.list.d/pve.list
log "Downloading Proxmox GPG key"
curl -fsSL -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg >>"$LOG_FILE" 2>&1&
show_progress $! "Downloading Proxmox GPG key" "Proxmox GPG key downloaded"
wait $!
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: Failed to download Proxmox GPG key"
exit 1
fi
log "Proxmox GPG key downloaded successfully"
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
}
_ISO_LIST_CACHE=""
_CHECKSUM_CACHE=""
_fetch_iso_list(){
if [[ -z $_ISO_LIST_CACHE ]];then
_ISO_LIST_CACHE=$(curl -s "$PROXMOX_ISO_BASE_URL"|grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso'|sort -uV)
fi
echo "$_ISO_LIST_CACHE"
}
prefetch_proxmox_iso_info(){
_ISO_LIST_CACHE=$(curl -s "$PROXMOX_ISO_BASE_URL" 2>/dev/null|grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso'|sort -uV)||true
_CHECKSUM_CACHE=$(curl -s "$PROXMOX_CHECKSUM_URL" 2>/dev/null)||true
}
get_available_proxmox_isos(){
local count="${1:-5}"
_fetch_iso_list|tail -n "$count"|tac
}
get_latest_proxmox_ve_iso(){
local latest_iso
latest_iso=$(_fetch_iso_list|tail -n1)
if [[ -n $latest_iso ]];then
echo "$PROXMOX_ISO_BASE_URL$latest_iso"
else
echo "No Proxmox VE ISO found." >&2
return 1
fi
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
log "Downloading with aria2c (2 connections, with retries)"
local aria2_args=(
-x 2
-s 2
-k 4M
--max-tries="$max_retries"
--retry-wait=5
--timeout=60
--connect-timeout=30
--max-connection-per-server=2
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
download_proxmox_iso(){
log "Starting Proxmox ISO download"
if [[ -f "pve.iso" ]];then
log "Proxmox ISO already exists, skipping download"
print_success "Proxmox ISO:" "already exists, skipping download"
return 0
fi
if [[ -n $PROXMOX_ISO_VERSION ]];then
log "Using user-selected ISO: $PROXMOX_ISO_VERSION"
PROXMOX_ISO_URL=$(get_proxmox_iso_url "$PROXMOX_ISO_VERSION")
else
log "Fetching latest Proxmox ISO URL"
PROXMOX_ISO_URL=$(get_latest_proxmox_ve_iso)
fi
if [[ -z $PROXMOX_ISO_URL ]];then
log "ERROR: Failed to retrieve Proxmox ISO URL"
exit 1
fi
log "Found ISO URL: $PROXMOX_ISO_URL"
ISO_FILENAME=$(basename "$PROXMOX_ISO_URL")
local expected_checksum=""
if [[ -n $_CHECKSUM_CACHE ]];then
log "Using cached checksum data"
expected_checksum=$(echo "$_CHECKSUM_CACHE"|grep "$ISO_FILENAME"|awk '{print $1}')
else
log "Downloading checksum file"
curl -sS -o SHA256SUMS "$PROXMOX_CHECKSUM_URL" >>"$LOG_FILE" 2>&1||true
if [[ -f "SHA256SUMS" ]];then
expected_checksum=$(grep "$ISO_FILENAME" SHA256SUMS|awk '{print $1}')
fi
fi
log "Expected checksum: $expected_checksum"
log "Downloading ISO: $ISO_FILENAME"
local download_success=false
local download_method=""
local exit_code
if command -v aria2c &>/dev/null;then
log "Attempting download with aria2c (conservative mode)"
_download_iso_aria2c "$PROXMOX_ISO_URL" "pve.iso" "$expected_checksum"&
show_progress $! "Downloading $ISO_FILENAME (aria2c)" "$ISO_FILENAME downloaded"
wait $!
exit_code=$?
if [[ $exit_code -eq 0 ]]&&[[ -s "pve.iso" ]];then
download_success=true
download_method="aria2c"
log "aria2c download successful"
else
log "aria2c failed (exit code: $exit_code), trying curl fallback"
rm -f pve.iso
fi
fi
if [[ $download_success != "true" ]];then
log "Attempting download with curl"
_download_iso_curl "$PROXMOX_ISO_URL" "pve.iso"&
show_progress $! "Downloading $ISO_FILENAME (curl)" "$ISO_FILENAME downloaded"
wait $!
exit_code=$?
if [[ $exit_code -eq 0 ]]&&[[ -s "pve.iso" ]];then
download_success=true
download_method="curl"
log "curl download successful"
else
log "curl failed (exit code: $exit_code), trying wget fallback"
rm -f pve.iso
fi
fi
if [[ $download_success != "true" ]]&&command -v wget &>/dev/null;then
log "Attempting download with wget"
_download_iso_wget "$PROXMOX_ISO_URL" "pve.iso"&
show_progress $! "Downloading $ISO_FILENAME (wget)" "$ISO_FILENAME downloaded"
wait $!
exit_code=$?
if [[ $exit_code -eq 0 ]]&&[[ -s "pve.iso" ]];then
download_success=true
download_method="wget"
log "wget download successful"
else
rm -f pve.iso
fi
fi
if [[ $download_success != "true" ]];then
log "ERROR: All download methods failed for Proxmox ISO"
rm -f pve.iso SHA256SUMS
exit 1
fi
local iso_size
iso_size=$(stat -c%s pve.iso 2>/dev/null)||iso_size=0
log "ISO file size: $(echo "$iso_size"|awk '{printf "%.1fG", $1/1024/1024/1024}')"
if [[ -n $expected_checksum ]];then
if [[ $download_method == "aria2c" ]];then
log "Checksum already verified by aria2c"
else
log "Verifying ISO checksum"
local actual_checksum
actual_checksum=$(sha256sum pve.iso|awk '{print $1}')
if [[ $actual_checksum != "$expected_checksum" ]];then
log "ERROR: Checksum mismatch! Expected: $expected_checksum, Got: $actual_checksum"
rm -f pve.iso SHA256SUMS
exit 1
fi
log "Checksum verification passed"
fi
else
log "WARNING: Could not find checksum for $ISO_FILENAME"
print_warning "Could not find checksum for $ISO_FILENAME"
fi
rm -f SHA256SUMS
}
validate_answer_toml(){
local file="$1"
local required_fields=("fqdn" "mailto" "timezone" "root_password")
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
return 0
}
make_answer_toml(){
log "Creating answer.toml for autoinstall"
log "ZFS_RAID=$ZFS_RAID, DRIVE_COUNT=$DRIVE_COUNT"
case "$ZFS_RAID" in
single)DISK_LIST='["/dev/vda"]'
;;
raid0|raid1)DISK_LIST='["/dev/vda", "/dev/vdb"]'
;;
*)DISK_LIST='["/dev/vda", "/dev/vdb"]'
esac
log "DISK_LIST=$DISK_LIST"
local zfs_raid_value
if [[ $DRIVE_COUNT -ge 2 && -n $ZFS_RAID && $ZFS_RAID != "single" ]];then
zfs_raid_value="$ZFS_RAID"
else
zfs_raid_value="raid0"
fi
log "Using ZFS raid: $zfs_raid_value"
if ! download_template "./answer.toml" "answer.toml";then
log "ERROR: Failed to download answer.toml template"
exit 1
fi
apply_template_vars "./answer.toml" \
"FQDN=$FQDN" \
"EMAIL=$EMAIL" \
"TIMEZONE=$TIMEZONE" \
"ROOT_PASSWORD=$NEW_ROOT_PASSWORD" \
"ZFS_RAID=$zfs_raid_value" \
"DISK_LIST=$DISK_LIST"
if ! validate_answer_toml "./answer.toml";then
log "ERROR: answer.toml validation failed"
exit 1
fi
log "answer.toml created and validated:"
cat answer.toml >>"$LOG_FILE"
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
wait $!
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
QEMU_CORES=$((available_cores/2))
[[ $QEMU_CORES -lt $MIN_CPU_CORES ]]&&QEMU_CORES=$MIN_CPU_CORES
[[ $QEMU_CORES -gt $available_cores ]]&&QEMU_CORES=$available_cores
[[ $QEMU_CORES -gt $MAX_QEMU_CORES ]]&&QEMU_CORES=$MAX_QEMU_CORES
fi
if [[ -n $QEMU_RAM_OVERRIDE ]];then
QEMU_RAM="$QEMU_RAM_OVERRIDE"
log "Using user-specified RAM: ${QEMU_RAM}MB"
if [[ $QEMU_RAM -gt $((available_ram_mb-QEMU_MIN_RAM_RESERVE)) ]];then
print_warning "Requested QEMU RAM (${QEMU_RAM}MB) may exceed safe limits (available: ${available_ram_mb}MB)"
fi
else
QEMU_RAM=$DEFAULT_QEMU_RAM
[[ $available_ram_mb -lt $QEMU_LOW_RAM_THRESHOLD ]]&&QEMU_RAM=$MIN_QEMU_RAM
fi
log "QEMU config: $QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM"
DRIVE_ARGS=""
for drive in "${DRIVES[@]}";do
DRIVE_ARGS="$DRIVE_ARGS -drive file=$drive,format=raw,media=disk,if=virtio"
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
setup_qemu_config
if [[ ! -f "./pve-autoinstall.iso" ]];then
print_error "Autoinstall ISO not found!"
exit 1
fi
local install_msg="Installing Proxmox VE ($QEMU_CORES vCPUs, ${QEMU_RAM}MB RAM)"
printf "$CLR_YELLOW%s %s$CLR_RESET" "${SPINNER_CHARS[0]}" "$install_msg"
release_drives
qemu-system-x86_64 $KVM_OPTS $UEFI_OPTS \
$CPU_OPTS -smp "$QEMU_CORES" -m "$QEMU_RAM" \
-boot d -cdrom ./pve-autoinstall.iso \
$DRIVE_ARGS -no-reboot -display none >qemu_install.log 2>&1&
local qemu_pid=$!
sleep 2
if ! kill -0 $qemu_pid 2>/dev/null;then
printf "\r\e[K"
log "ERROR: QEMU failed to start"
log "QEMU install log:"
cat qemu_install.log >>"$LOG_FILE" 2>&1
exit 1
fi
show_progress $qemu_pid "$install_msg" "Proxmox VE installed"
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
wait_with_progress "Booting installed Proxmox" 300 "(echo >/dev/tcp/localhost/5555)" 3 "Proxmox booted, port open"
wait_for_ssh_ready 120||{
log "ERROR: SSH connection failed"
log "QEMU output log:"
cat qemu_output.log >>"$LOG_FILE" 2>&1
return 1
}
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
(download_template "./templates/99-proxmox.conf"||exit 1
download_template "./templates/hosts"||exit 1
download_template "./templates/debian.sources"||exit 1
download_template "./templates/proxmox.sources" "$proxmox_sources_template"||exit 1
download_template "./templates/sshd_config"||exit 1
download_template "./templates/zshrc"||exit 1
download_template "./templates/p10k.zsh"||exit 1
download_template "./templates/chrony"||exit 1
download_template "./templates/50unattended-upgrades"||exit 1
download_template "./templates/20auto-upgrades"||exit 1
download_template "./templates/interfaces" "$interfaces_template"||exit 1
download_template "./templates/resolv.conf"||exit 1
download_template "./templates/configure-zfs-arc.sh"||exit 1
download_template "./templates/locale.sh"||exit 1
download_template "./templates/default-locale"||exit 1
download_template "./templates/environment"||exit 1
download_template "./templates/cpufrequtils"||exit 1
download_template "./templates/remove-subscription-nag.sh"||exit 1
download_template "./templates/letsencrypt-deploy-hook.sh"||exit 1
download_template "./templates/letsencrypt-firstboot.sh"||exit 1
download_template "./templates/letsencrypt-firstboot.service"||exit 1
download_template "./templates/fastfetch.sh"||exit 1) > \
/dev/null 2>&1&
if ! show_progress $! "Downloading template files";then
log "ERROR: Failed to download template files"
exit 1
fi
(apply_common_template_vars "./templates/hosts"
apply_common_template_vars "./templates/interfaces"
apply_common_template_vars "./templates/resolv.conf"
apply_template_vars "./templates/cpufrequtils" "CPU_GOVERNOR=${CPU_GOVERNOR:-performance}") \
&
show_progress $! "Modifying template files"
}
configure_base_system(){
remote_copy "templates/hosts" "/etc/hosts" >/dev/null 2>&1&
local pid1=$!
remote_copy "templates/interfaces" "/etc/network/interfaces" >/dev/null 2>&1&
local pid2=$!
remote_copy "templates/99-proxmox.conf" "/etc/sysctl.d/99-proxmox.conf" >/dev/null 2>&1&
local pid3=$!
remote_copy "templates/debian.sources" "/etc/apt/sources.list.d/debian.sources" >/dev/null 2>&1&
local pid4=$!
remote_copy "templates/proxmox.sources" "/etc/apt/sources.list.d/proxmox.sources" >/dev/null 2>&1&
local pid5=$!
remote_copy "templates/resolv.conf" "/etc/resolv.conf" >/dev/null 2>&1&
local pid6=$!
local exit_code=0
wait $pid1||exit_code=1
wait $pid2||exit_code=1
wait $pid3||exit_code=1
wait $pid4||exit_code=1
wait $pid5||exit_code=1
wait $pid6||exit_code=1
if [[ $exit_code -eq 0 ]];then
printf '\r\e[K%s✓ Configuration files copied%s\n' "$CLR_CYAN" "$CLR_RESET"
else
printf '\r\e[K%s✗ Copying configuration files%s\n' "$CLR_RED" "$CLR_RESET"
log "ERROR: Failed to copy some configuration files"
exit 1
fi
(remote_exec "[ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak"
remote_exec "echo '$PVE_HOSTNAME' > /etc/hostname"
remote_exec "systemctl disable --now rpcbind rpcbind.socket 2>/dev/null") > \
/dev/null 2>&1&
show_progress $! "Applying basic system settings" "Basic system settings applied"
(remote_copy "templates/configure-zfs-arc.sh" "/tmp/configure-zfs-arc.sh"
remote_exec "chmod +x /tmp/configure-zfs-arc.sh && /tmp/configure-zfs-arc.sh && rm -f /tmp/configure-zfs-arc.sh") > \
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
run_remote "Updating system packages" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get dist-upgrade -yqq
        apt-get autoremove -yqq
        apt-get clean
        pveupgrade 2>/dev/null || true
        pveam update 2>/dev/null || true
    ' "System packages updated"
local pkg_output
pkg_output=$(mktemp)
(remote_exec "
            export DEBIAN_FRONTEND=noninteractive
            failed_pkgs=''
            for pkg in $SYSTEM_UTILITIES; do
                if ! apt-get install -yqq \"\$pkg\" 2>&1; then
                    failed_pkgs=\"\${failed_pkgs} \$pkg\"
                fi
            done
            for pkg in $OPTIONAL_PACKAGES; do
                apt-get install -yqq \"\$pkg\" 2>/dev/null || true
            done
            if [[ -n \"\$failed_pkgs\" ]]; then
                echo \"FAILED_PACKAGES:\$failed_pkgs\"
            fi
        " 2>&1) > \
"$pkg_output"&
show_progress $! "Installing system utilities" "System utilities installed"
if grep -q "FAILED_PACKAGES:" "$pkg_output" 2>/dev/null;then
local failed_list
failed_list=$(grep "FAILED_PACKAGES:" "$pkg_output"|sed 's/FAILED_PACKAGES://')
print_warning "Some packages failed to install:$failed_list" true
log "WARNING: Failed to install packages:$failed_list"
fi
cat "$pkg_output" >>"$LOG_FILE"
rm -f "$pkg_output"
run_remote "Configuring UTF-8 locales" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq locales
        sed -i "s/# en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
        sed -i "s/# ru_RU.UTF-8/ru_RU.UTF-8/" /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    ' "UTF-8 locales configured"
(remote_copy "templates/locale.sh" "/etc/profile.d/locale.sh"
remote_exec "chmod +x /etc/profile.d/locale.sh"
remote_copy "templates/default-locale" "/etc/default/locale"
remote_copy "templates/environment" "/etc/environment") > \
/dev/null 2>&1&
show_progress $! "Installing locale configuration files" "Locale files installed"
(remote_copy "templates/fastfetch.sh" "/etc/profile.d/fastfetch.sh"
remote_exec "chmod +x /etc/profile.d/fastfetch.sh"
remote_exec "grep -q 'profile.d/fastfetch.sh' /etc/bash.bashrc || echo '[ -f /etc/profile.d/fastfetch.sh ] && . /etc/profile.d/fastfetch.sh' >> /etc/bash.bashrc") > \
/dev/null 2>&1&
show_progress $! "Configuring fastfetch" "Fastfetch configured"
}
configure_shell(){
if [[ $DEFAULT_SHELL == "zsh" ]];then
run_remote "Installing ZSH and Git" '
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -yqq zsh git curl
        ' "ZSH and Git installed"
run_remote "Installing Oh-My-Zsh" '
            export RUNZSH=no
            export CHSH=no
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        ' "Oh-My-Zsh installed"
run_remote "Installing Powerlevel10k theme" '
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/.oh-my-zsh/custom/themes/powerlevel10k
        ' "Powerlevel10k theme installed"
run_remote "Installing ZSH plugins" '
            git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions
            git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
        ' "ZSH plugins installed"
(remote_copy "templates/zshrc" "/root/.zshrc"
remote_copy "templates/p10k.zsh" "/root/.p10k.zsh"
remote_exec "chsh -s /bin/zsh root") > \
/dev/null 2>&1&
show_progress $! "Configuring ZSH" "ZSH with Powerlevel10k configured"
else
print_success "Default shell:" "Bash"
fi
}
configure_system_services(){
run_remote "Installing NTP (chrony)" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq chrony
        systemctl stop chrony
    ' "NTP (chrony) installed"
(remote_copy "templates/chrony" "/etc/chrony/chrony.conf"
remote_exec "systemctl enable chrony && systemctl start chrony") > \
/dev/null 2>&1&
show_progress $! "Configuring chrony" "Chrony configured"
run_remote "Installing Unattended Upgrades" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq unattended-upgrades apt-listchanges
    ' "Unattended Upgrades installed"
(remote_copy "templates/50unattended-upgrades" "/etc/apt/apt.conf.d/50unattended-upgrades"
remote_copy "templates/20auto-upgrades" "/etc/apt/apt.conf.d/20auto-upgrades"
remote_exec "systemctl enable unattended-upgrades") > \
/dev/null 2>&1&
show_progress $! "Configuring Unattended Upgrades" "Unattended Upgrades configured"
run_remote "Configuring nf_conntrack" '
        if ! grep -q "nf_conntrack" /etc/modules 2>/dev/null; then
            echo "nf_conntrack" >> /etc/modules
        fi

        if ! grep -q "nf_conntrack_max" /etc/sysctl.d/99-proxmox.conf 2>/dev/null; then
            echo "net.netfilter.nf_conntrack_max=1048576" >> /etc/sysctl.d/99-proxmox.conf
            echo "net.netfilter.nf_conntrack_tcp_timeout_established=28800" >> /etc/sysctl.d/99-proxmox.conf
        fi
    ' "nf_conntrack configured"
local governor="${CPU_GOVERNOR:-performance}"
(remote_copy "templates/cpufrequtils" "/tmp/cpufrequtils"
remote_exec "
            apt-get update -qq && apt-get install -yqq cpufrequtils 2>/dev/null || true
            mv /tmp/cpufrequtils /etc/default/cpufrequtils
            systemctl enable cpufrequtils 2>/dev/null || true
            if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
                for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                    [ -f \"\$cpu\" ] && echo '$governor' > \"\$cpu\" 2>/dev/null || true
                done
            fi
        ") > \
/dev/null 2>&1&
show_progress $! "Configuring CPU governor ($governor)" "CPU governor configured"
if [[ ${PVE_REPO_TYPE:-no-subscription} != "enterprise" ]];then
log "configure_system_services: removing subscription notice (non-enterprise)"
(remote_copy "templates/remove-subscription-nag.sh" "/tmp/remove-subscription-nag.sh"
remote_exec "chmod +x /tmp/remove-subscription-nag.sh && /tmp/remove-subscription-nag.sh && rm -f /tmp/remove-subscription-nag.sh") > \
/dev/null 2>&1&
show_progress $! "Removing Proxmox subscription notice" "Subscription notice removed"
fi
}
configure_tailscale(){
if [[ $INSTALL_TAILSCALE != "yes" ]];then
return 0
fi
run_remote "Installing Tailscale VPN" '
        curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
        apt-get update -qq
        apt-get install -yqq tailscale
        systemctl enable tailscaled
        systemctl start tailscaled
    ' "Tailscale VPN installed"
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
remote_exec "tailscale ip -4" >"$tmp_ip" 2>/dev/null||true
remote_exec "tailscale status --json | jq -r '.Self.DNSName // empty' | sed 's/\\.$//' " >"$tmp_hostname" 2>/dev/null||true) > \
/dev/null 2>&1&
show_progress $! "Authenticating Tailscale"
TAILSCALE_IP=$(cat "$tmp_ip" 2>/dev/null||echo "pending")
TAILSCALE_HOSTNAME=$(cat "$tmp_hostname" 2>/dev/null||echo "")
printf "\033[1A\r%s✓ Tailscale authenticated. IP: %s%s                              \n" "$CLR_CYAN" "$TAILSCALE_IP" "$CLR_RESET"
if [[ $TAILSCALE_WEBUI == "yes" ]];then
remote_exec "tailscale serve --bg --https=443 https://127.0.0.1:8006" >/dev/null 2>&1&
show_progress $! "Configuring Tailscale Serve" "Proxmox Web UI available via Tailscale Serve"
fi
if [[ $TAILSCALE_SSH == "yes" && $TAILSCALE_DISABLE_SSH == "yes" ]];then
log "Deploying disable-openssh.service (TAILSCALE_SSH=$TAILSCALE_SSH, TAILSCALE_DISABLE_SSH=$TAILSCALE_DISABLE_SSH)"
(download_template "./templates/disable-openssh.service"||exit 1
log "Downloaded disable-openssh.service, size: $(wc -c <./templates/disable-openssh.service 2>/dev/null||echo 'failed')"
remote_copy "templates/disable-openssh.service" "/etc/systemd/system/disable-openssh.service"||exit 1
log "Copied disable-openssh.service to VM"
remote_exec "systemctl daemon-reload && systemctl enable disable-openssh.service" >/dev/null 2>&1||exit 1
log "Enabled disable-openssh.service") \
&
show_progress $! "Configuring OpenSSH disable on boot" "OpenSSH disable configured"
else
log "Skipping disable-openssh.service (TAILSCALE_SSH=$TAILSCALE_SSH, TAILSCALE_DISABLE_SSH=$TAILSCALE_DISABLE_SSH)"
fi
if [[ $STEALTH_MODE == "yes" ]];then
log "Deploying stealth-firewall.service (STEALTH_MODE=$STEALTH_MODE)"
(download_template "./templates/stealth-firewall.service"||exit 1
log "Downloaded stealth-firewall.service, size: $(wc -c <./templates/stealth-firewall.service 2>/dev/null||echo 'failed')"
remote_copy "templates/stealth-firewall.service" "/etc/systemd/system/stealth-firewall.service"||exit 1
log "Copied stealth-firewall.service to VM"
remote_exec "systemctl daemon-reload && systemctl enable stealth-firewall.service" >/dev/null 2>&1||exit 1
log "Enabled stealth-firewall.service") \
&
show_progress $! "Configuring stealth firewall" "Stealth firewall configured"
else
log "Skipping stealth-firewall.service (STEALTH_MODE=$STEALTH_MODE)"
fi
else
TAILSCALE_IP="not authenticated"
TAILSCALE_HOSTNAME=""
print_warning "Tailscale installed but not authenticated."
print_info "After reboot, run these commands to enable SSH and Web UI:"
print_info "  tailscale up --ssh"
print_info "  tailscale serve --bg --https=443 https://127.0.0.1:8006"
fi
}
configure_fail2ban(){
if [[ $INSTALL_TAILSCALE == "yes" ]];then
log "Skipping Fail2Ban (Tailscale provides security)"
return 0
fi
log "Installing Fail2Ban (no Tailscale)"
run_remote "Installing Fail2Ban" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -yqq fail2ban
    ' "Fail2Ban installed"
(download_template "./templates/fail2ban-jail.local"||exit 1
download_template "./templates/fail2ban-proxmox.conf"||exit 1
apply_template_vars "./templates/fail2ban-jail.local" \
"EMAIL=$EMAIL" \
"HOSTNAME=$PVE_HOSTNAME"
remote_copy "templates/fail2ban-jail.local" "/etc/fail2ban/jail.local"||exit 1
remote_copy "templates/fail2ban-proxmox.conf" "/etc/fail2ban/filter.d/proxmox.conf"||exit 1
remote_exec "systemctl enable fail2ban && systemctl restart fail2ban"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring Fail2Ban" "Fail2Ban configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Fail2Ban configuration failed"
print_warning "Fail2Ban configuration failed - continuing without it"
return 0
fi
FAIL2BAN_INSTALLED="yes"
}
configure_auditd(){
if [[ $INSTALL_AUDITD != "yes" ]];then
log "Skipping auditd (not requested)"
return 0
fi
log "Installing and configuring auditd"
run_remote "Installing auditd" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -yqq auditd audispd-plugins
    ' "Auditd installed"
(download_template "./templates/auditd-rules"||exit 1
remote_copy "templates/auditd-rules" "/etc/audit/rules.d/proxmox.rules"||exit 1
remote_exec '
            # Ensure log directory exists
            mkdir -p /var/log/audit

            # Configure auditd.conf for better log retention
            sed -i "s/^max_log_file = .*/max_log_file = 50/" /etc/audit/auditd.conf 2>/dev/null || true
            sed -i "s/^num_logs = .*/num_logs = 10/" /etc/audit/auditd.conf 2>/dev/null || true
            sed -i "s/^max_log_file_action = .*/max_log_file_action = ROTATE/" /etc/audit/auditd.conf 2>/dev/null || true

            # Load new rules
            augenrules --load 2>/dev/null || true

            # Enable and restart auditd
            systemctl enable auditd
            systemctl restart auditd
        '||exit 1) > \
/dev/null 2>&1&
show_progress $! "Configuring auditd rules" "Auditd configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Auditd configuration failed"
print_warning "Auditd configuration failed - continuing without it"
return 0
fi
AUDITD_INSTALLED="yes"
}
configure_ssl_certificate(){
log "configure_ssl_certificate: SSL_TYPE=$SSL_TYPE"
if [[ $SSL_TYPE != "letsencrypt" ]];then
log "configure_ssl_certificate: skipping (self-signed)"
return 0
fi
local cert_domain="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
log "configure_ssl_certificate: domain=$cert_domain, email=$EMAIL"
run_remote "Installing Certbot" '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -yqq certbot
    ' "Certbot installed"
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
configure_ssh_hardening(){
local escaped_ssh_key="${SSH_PUBLIC_KEY//\'/\'\\\'\'}"
(remote_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh"||exit 1
remote_exec "echo '$escaped_ssh_key' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"||exit 1
remote_copy "templates/sshd_config" "/etc/ssh/sshd_config"||exit 1) > \
/dev/null 2>&1&
show_progress $! "Deploying SSH hardening" "Security hardening configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: SSH hardening failed - system may be insecure"
exit 1
fi
}
finalize_vm(){
remote_exec "poweroff" >/dev/null 2>&1&
show_progress $! "Powering off the VM"
wait_with_progress "Waiting for QEMU process to exit" 120 "! kill -0 $QEMU_PID 2>/dev/null" 1 "QEMU process exited"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: QEMU process did not exit cleanly within 120 seconds"
kill -9 "$QEMU_PID" 2>/dev/null||true
fi
}
configure_proxmox_via_ssh(){
log "Starting Proxmox configuration via SSH"
make_templates
configure_base_system
configure_shell
configure_system_services
configure_tailscale
configure_fail2ban
configure_auditd
configure_ssl_certificate
configure_ssh_hardening
validate_installation
finalize_vm
}
VALIDATION_PASSED=0
VALIDATION_FAILED=0
VALIDATION_WARNINGS=0
declare -a VALIDATION_RESULTS=()
_add_validation_result(){
local status="$1"
local check_name="$2"
local details="${3:-}"
case "$status" in
pass)VALIDATION_PASSED=$((VALIDATION_PASSED+1))
VALIDATION_RESULTS+=("[OK]|$check_name|$details")
;;
fail)VALIDATION_FAILED=$((VALIDATION_FAILED+1))
VALIDATION_RESULTS+=("[ERROR]|$check_name|$details")
;;
warn)VALIDATION_WARNINGS=$((VALIDATION_WARNINGS+1))
VALIDATION_RESULTS+=("[WARN]|$check_name|$details")
esac
}
_validate_ssh(){
local ssh_status
ssh_status=$(remote_exec "systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null" 2>/dev/null)
if [[ $ssh_status == "active" ]];then
_add_validation_result "pass" "SSH service" "running"
else
_add_validation_result "fail" "SSH service" "not running"
fi
local key_check
key_check=$(remote_exec "test -f /root/.ssh/authorized_keys && grep -c 'ssh-' /root/.ssh/authorized_keys 2>/dev/null || echo 0" 2>/dev/null)
if [[ $key_check -gt 0 ]];then
_add_validation_result "pass" "SSH public key" "deployed"
else
_add_validation_result "fail" "SSH public key" "not found"
fi
local pass_auth
pass_auth=$(remote_exec "grep -E '^PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
if [[ $pass_auth == "no" ]];then
_add_validation_result "pass" "Password auth" "DISABLED"
else
_add_validation_result "warn" "Password auth" "enabled"
fi
}
_validate_zfs(){
local pool_health
pool_health=$(remote_exec "zpool status rpool 2>/dev/null | grep 'state:' | awk '{print \$2}'" 2>/dev/null)
if [[ $pool_health == "ONLINE" ]];then
_add_validation_result "pass" "ZFS rpool" "ONLINE"
elif [[ -n $pool_health ]];then
_add_validation_result "warn" "ZFS rpool" "$pool_health"
else
_add_validation_result "fail" "ZFS rpool" "not found"
fi
local arc_max
arc_max=$(remote_exec "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null" 2>/dev/null)
if [[ -n $arc_max && $arc_max -gt 0 ]];then
local arc_max_gb
arc_max_gb=$(echo "scale=1; $arc_max / 1073741824"|bc 2>/dev/null||echo "N/A")
_add_validation_result "pass" "ZFS ARC limit" "${arc_max_gb}GB"
else
_add_validation_result "warn" "ZFS ARC limit" "not set"
fi
}
_validate_network(){
local ipv4_ping
ipv4_ping=$(remote_exec "ping -c 1 -W 2 $MAIN_IPV4_GW >/dev/null 2>&1 && echo ok || echo fail" 2>/dev/null)
if [[ $ipv4_ping == "ok" ]];then
_add_validation_result "pass" "IPv4 gateway" "reachable"
else
_add_validation_result "fail" "IPv4 gateway" "unreachable"
fi
local dns_check
dns_check=$(remote_exec "host -W 2 google.com >/dev/null 2>&1 && echo ok || echo fail" 2>/dev/null)
if [[ $dns_check == "ok" ]];then
_add_validation_result "pass" "DNS resolution" "working"
else
_add_validation_result "warn" "DNS resolution" "failed"
fi
if [[ ${IPV6_MODE:-disabled} != "disabled" && -n ${MAIN_IPV6:-} ]];then
local ipv6_addr
ipv6_addr=$(remote_exec "ip -6 addr show scope global 2>/dev/null | grep -c 'inet6'" 2>/dev/null)
if [[ $ipv6_addr -gt 0 ]];then
_add_validation_result "pass" "IPv6 address" "configured"
else
_add_validation_result "warn" "IPv6 address" "not found"
fi
fi
}
_validate_services(){
local services=("pve-cluster" "pvedaemon" "pveproxy" "pvestatd")
local all_running=true
for svc in "${services[@]}";do
local svc_status
svc_status=$(remote_exec "systemctl is-active $svc 2>/dev/null" 2>/dev/null)
if [[ $svc_status != "active" ]];then
all_running=false
_add_validation_result "fail" "$svc" "not running"
fi
done
if [[ $all_running == "true" ]];then
_add_validation_result "pass" "Proxmox services" "all running"
fi
local ntp_status
ntp_status=$(remote_exec "systemctl is-active chrony 2>/dev/null" 2>/dev/null)
if [[ $ntp_status == "active" ]];then
_add_validation_result "pass" "NTP sync" "chrony running"
else
_add_validation_result "warn" "NTP sync" "not running"
fi
}
_validate_proxmox(){
local web_check
web_check=$(remote_exec "curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8006/ 2>/dev/null" 2>/dev/null)
if [[ $web_check == "200" || $web_check == "301" || $web_check == "302" ]];then
_add_validation_result "pass" "Web UI (8006)" "responding"
else
_add_validation_result "fail" "Web UI (8006)" "not responding"
fi
local pvesh_check
pvesh_check=$(remote_exec "pvesh get /version --output-format json 2>/dev/null | jq -r '.version' 2>/dev/null" 2>/dev/null)
if [[ -n $pvesh_check && $pvesh_check != "null" ]];then
_add_validation_result "pass" "Proxmox API" "v$pvesh_check"
else
_add_validation_result "warn" "Proxmox API" "check failed"
fi
}
_validate_ssl(){
local cert_info
cert_info=$(remote_exec "openssl x509 -enddate -noout -in /etc/pve/local/pve-ssl.pem 2>/dev/null | cut -d= -f2" 2>/dev/null)
if [[ -n $cert_info ]];then
local short_date
short_date=$(echo "$cert_info"|awk '{print $1, $2, $4}')
_add_validation_result "pass" "SSL certificate" "valid until $short_date"
else
_add_validation_result "fail" "SSL certificate" "missing"
fi
}
validate_installation(){
log "Starting post-installation validation..."
VALIDATION_PASSED=0
VALIDATION_FAILED=0
VALIDATION_WARNINGS=0
VALIDATION_RESULTS=()
local results_file
results_file=$(mktemp)
trap 'rm -f "$results_file"' RETURN
(_validate_ssh
_validate_zfs
_validate_network
_validate_services
_validate_proxmox
_validate_ssl
{
echo "VALIDATION_PASSED=$VALIDATION_PASSED"
echo "VALIDATION_FAILED=$VALIDATION_FAILED"
echo "VALIDATION_WARNINGS=$VALIDATION_WARNINGS"
for result in "${VALIDATION_RESULTS[@]}";do
echo "RESULT:$result"
done
} >>"$results_file") 2> \
/dev/null&
show_progress $! "Validating installation" "Validation complete"
if [[ -f $results_file ]];then
while IFS= read -r line;do
case "$line" in
VALIDATION_PASSED=*)VALIDATION_PASSED="${line#VALIDATION_PASSED=}"
;;
VALIDATION_FAILED=*)VALIDATION_FAILED="${line#VALIDATION_FAILED=}"
;;
VALIDATION_WARNINGS=*)VALIDATION_WARNINGS="${line#VALIDATION_WARNINGS=}"
;;
RESULT:*)VALIDATION_RESULTS+=("${line#RESULT:}")
esac
done <"$results_file"
fi
log "Validation complete: $VALIDATION_PASSED passed, $VALIDATION_WARNINGS warnings, $VALIDATION_FAILED failed"
}
truncate_middle(){
local str="$1"
local max_len="${2:-25}"
local len=${#str}
if [[ $len -le $max_len ]];then
echo "$str"
return
fi
local keep_start=$(((max_len-3)*2/3))
local keep_end=$((max_len-3-keep_start))
echo "${str:0:keep_start}...${str: -$keep_end}"
}
reboot_to_main_os(){
local inner_width=$((MENU_BOX_WIDTH-6))
local summary=""
local end_time total_seconds duration
end_time=$(date +%s)
total_seconds=$((end_time-INSTALL_START_TIME))
duration=$(format_duration $total_seconds)
summary+="[OK]|Installation time|$duration"$'\n'
if [[ ${#VALIDATION_RESULTS[@]} -gt 0 ]];then
summary+="|--- System Checks ---|"$'\n'
for result in "${VALIDATION_RESULTS[@]}";do
summary+="$result"$'\n'
done
fi
summary+="|--- Configuration ---|"$'\n'
summary+="[OK]|CPU governor|${CPU_GOVERNOR:-performance}"$'\n'
summary+="[OK]|Kernel params|optimized"$'\n'
summary+="[OK]|nf_conntrack|optimized"$'\n'
summary+="[OK]|Security updates|unattended"$'\n'
summary+="[OK]|Monitoring tools|btop, iotop, ncdu..."$'\n'
case "${PVE_REPO_TYPE:-no-subscription}" in
enterprise)summary+="[OK]|Repository|enterprise"$'\n'
if [[ -n $PVE_SUBSCRIPTION_KEY ]];then
summary+="[OK]|Subscription|registered"$'\n'
else
summary+="[WARN]|Subscription|key not provided"$'\n'
fi
;;
test)summary+="[WARN]|Repository|test (unstable)"$'\n'
;;
*)summary+="[OK]|Repository|no-subscription"$'\n'
esac
if [[ $SSL_TYPE == "letsencrypt" ]];then
summary+="[OK]|SSL auto-renewal|enabled"$'\n'
fi
if [[ $INSTALL_TAILSCALE == "yes" ]];then
summary+="[OK]|Tailscale VPN|installed"$'\n'
if [[ -z $TAILSCALE_AUTH_KEY ]];then
summary+="[WARN]|Tailscale|needs auth after reboot"$'\n'
fi
else
if [[ $FAIL2BAN_INSTALLED == "yes" ]];then
summary+="[OK]|Fail2Ban|SSH + Proxmox protected"$'\n'
fi
fi
if [[ $AUDITD_INSTALLED == "yes" ]];then
summary+="[OK]|Audit logging|auditd enabled"$'\n'
fi
summary+="|--- Access ---|"$'\n'
if [[ $PASSWORD_GENERATED == "yes" ]];then
summary+="[WARN]|Root password|$NEW_ROOT_PASSWORD"$'\n'
fi
if [[ $STEALTH_MODE == "yes" ]];then
summary+="[WARN]|Public IP|BLOCKED (stealth mode)"$'\n'
if [[ $TAILSCALE_DISABLE_SSH == "yes" ]];then
summary+="[WARN]|OpenSSH|DISABLED after first boot"
fi
if [[ $INSTALL_TAILSCALE == "yes" && -n $TAILSCALE_AUTH_KEY && $TAILSCALE_IP != "pending" && $TAILSCALE_IP != "not authenticated" ]];then
summary+=$'\n'"[OK]|Tailscale SSH|root@$TAILSCALE_IP"
if [[ -n $TAILSCALE_HOSTNAME ]];then
summary+=$'\n'"[OK]|Tailscale Web|$(truncate_middle "$TAILSCALE_HOSTNAME" 25)"
else
summary+=$'\n'"[OK]|Tailscale Web|$TAILSCALE_IP:8006"
fi
fi
else
summary+="[OK]|Web UI|https://${MAIN_IPV4_CIDR%/*}:8006"$'\n'
summary+="[OK]|SSH|root@${MAIN_IPV4_CIDR%/*}"
if [[ $INSTALL_TAILSCALE == "yes" && -n $TAILSCALE_AUTH_KEY && $TAILSCALE_IP != "pending" && $TAILSCALE_IP != "not authenticated" ]];then
summary+=$'\n'"[OK]|Tailscale SSH|root@$TAILSCALE_IP"
if [[ -n $TAILSCALE_HOSTNAME ]];then
summary+=$'\n'"[OK]|Tailscale Web|$(truncate_middle "$TAILSCALE_HOSTNAME" 25)"
else
summary+=$'\n'"[OK]|Tailscale Web|$TAILSCALE_IP:8006"
fi
fi
fi
if [[ $VALIDATION_FAILED -gt 0 || $VALIDATION_WARNINGS -gt 0 ]];then
summary+=$'\n'"|--- Validation ---|"$'\n'
summary+="[OK]|Checks passed|$VALIDATION_PASSED"$'\n'
if [[ $VALIDATION_WARNINGS -gt 0 ]];then
summary+="[WARN]|Warnings|$VALIDATION_WARNINGS"$'\n'
fi
if [[ $VALIDATION_FAILED -gt 0 ]];then
summary+="[ERROR]|Failed|$VALIDATION_FAILED"$'\n'
fi
fi
echo ""
show_timed_progress "Summarizing..." 5
clear
show_banner --no-info
{
echo "INSTALLATION SUMMARY"
echo "$summary"|column -t -s '|'|while IFS= read -r line;do
printf "%-${inner_width}s\n" "$line"
done
}|boxes -d stone -p a1 -s $MENU_BOX_WIDTH|colorize_status
echo ""
if [[ $VALIDATION_FAILED -gt 0 ]];then
print_warning "Some validation checks failed. Review the summary above."
echo ""
fi
if [[ $INSTALL_TAILSCALE == "yes" && -z $TAILSCALE_AUTH_KEY ]];then
print_warning "Tailscale needs authentication after reboot:"
echo "    tailscale up --ssh"
echo "    tailscale serve --bg --https=443 https://127.0.0.1:8006"
echo ""
fi
read -r -e -p "Do you want to reboot the system? (y/n): " -i "y" REBOOT
if [[ $REBOOT == "y" ]];then
print_info "Rebooting the system..."
if ! reboot;then
log "ERROR: Failed to reboot - system may require manual restart"
print_error "Failed to reboot the system"
exit 1
fi
else
print_info "Exiting..."
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
log "Step: collect_system_info"
show_banner_animated_start 0.1
collect_system_info
log "Step: prefetch_proxmox_iso_info"
prefetch_proxmox_iso_info
show_banner_animated_stop
log "Step: show_system_status"
show_system_status
log "Step: get_system_inputs"
get_system_inputs
log "Step: show_configuration_review"
show_configuration_review
echo ""
show_timed_progress "Configuring..." 5
clear
show_banner
log "Step: prepare_packages"
prepare_packages
log "Step: download_proxmox_iso"
download_proxmox_iso
log "Step: make_answer_toml"
make_answer_toml
log "Step: make_autoinstall_iso"
make_autoinstall_iso
log "Step: install_proxmox"
install_proxmox
log "Step: boot_proxmox_with_port_forwarding"
boot_proxmox_with_port_forwarding||{
log "ERROR: Failed to boot Proxmox with port forwarding"
exit 1
}
log "Step: configure_proxmox_via_ssh"
configure_proxmox_via_ssh
INSTALL_COMPLETED=true
log "Step: reboot_to_main_os"
reboot_to_main_os
