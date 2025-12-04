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
SPINNER_CHARS=('○' '◔' '◑' '◕' '●' '◕' '◑' '◔')
VERSION="1.18.23-pr.14"
GITHUB_REPO="${GITHUB_REPO:-qoxi-cloud/proxmox-hetzner}"
GITHUB_BRANCH="${GITHUB_BRANCH:-feature/wizard}"
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
CONFIG_FILE=""
SAVE_CONFIG=""
VALIDATE_ONLY=false
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
  -c, --config FILE       Load configuration from file
  -s, --save-config FILE  Save configuration to file after input
  --validate              Validate configuration only, do not install
  --qemu-ram MB           Set QEMU RAM in MB (default: auto, 4096-8192)
  --qemu-cores N          Set QEMU CPU cores (default: auto, max 16)
  --iso-version FILE      Use specific Proxmox ISO (e.g., proxmox-ve_8.3-1.iso)
  -v, --version           Show version

Examples:
  $0                           # Run installation
  $0 -c proxmox.conf           # Load config from file
  $0 -s proxmox.conf           # Save config to file
  $0 -c proxmox.conf --validate  # Validate config without installing
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
-c|--config)CONFIG_FILE="$2"
shift 2
;;
-s|--save-config)SAVE_CONFIG="$2"
shift 2
;;
--validate)VALIDATE_ONLY=true
shift
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
validate_config(){
local has_errors=false
if [[ $NON_INTERACTIVE == true ]];then
if [[ -z $SSH_PUBLIC_KEY ]];then
log "WARNING: SSH_PUBLIC_KEY not set in config, will attempt auto-detection"
fi
fi
if [[ -n $BRIDGE_MODE ]]&&[[ ! $BRIDGE_MODE =~ ^(internal|external|both)$ ]];then
echo -e "${CLR_RED}Invalid BRIDGE_MODE: $BRIDGE_MODE (must be: internal, external, or both)$CLR_RESET"
has_errors=true
fi
if [[ -n $ZFS_RAID ]]&&[[ ! $ZFS_RAID =~ ^(single|raid0|raid1)$ ]];then
echo -e "${CLR_RED}Invalid ZFS_RAID: $ZFS_RAID (must be: single, raid0, or raid1)$CLR_RESET"
has_errors=true
fi
if [[ -n $PVE_REPO_TYPE ]]&&[[ ! $PVE_REPO_TYPE =~ ^(no-subscription|enterprise|test)$ ]];then
echo -e "${CLR_RED}Invalid PVE_REPO_TYPE: $PVE_REPO_TYPE (must be: no-subscription, enterprise, or test)$CLR_RESET"
has_errors=true
fi
if [[ -n $SSL_TYPE ]]&&[[ ! $SSL_TYPE =~ ^(self-signed|letsencrypt)$ ]];then
echo -e "${CLR_RED}Invalid SSL_TYPE: $SSL_TYPE (must be: self-signed or letsencrypt)$CLR_RESET"
has_errors=true
fi
if [[ -n $DEFAULT_SHELL ]]&&[[ ! $DEFAULT_SHELL =~ ^(bash|zsh)$ ]];then
echo -e "${CLR_RED}Invalid DEFAULT_SHELL: $DEFAULT_SHELL (must be: bash or zsh)$CLR_RESET"
has_errors=true
fi
if [[ -n $INSTALL_AUDITD ]]&&[[ ! $INSTALL_AUDITD =~ ^(yes|no)$ ]];then
echo -e "${CLR_RED}Invalid INSTALL_AUDITD: $INSTALL_AUDITD (must be: yes or no)$CLR_RESET"
has_errors=true
fi
if [[ -n $INSTALL_VNSTAT ]]&&[[ ! $INSTALL_VNSTAT =~ ^(yes|no)$ ]];then
echo -e "${CLR_RED}Invalid INSTALL_VNSTAT: $INSTALL_VNSTAT (must be: yes or no)$CLR_RESET"
has_errors=true
fi
if [[ -n $INSTALL_UNATTENDED_UPGRADES ]]&&[[ ! $INSTALL_UNATTENDED_UPGRADES =~ ^(yes|no)$ ]];then
echo -e "${CLR_RED}Invalid INSTALL_UNATTENDED_UPGRADES: $INSTALL_UNATTENDED_UPGRADES (must be: yes or no)$CLR_RESET"
has_errors=true
fi
if [[ -n $CPU_GOVERNOR ]]&&[[ ! $CPU_GOVERNOR =~ ^(performance|ondemand|powersave|schedutil|conservative)$ ]];then
echo -e "${CLR_RED}Invalid CPU_GOVERNOR: $CPU_GOVERNOR (must be: performance, ondemand, powersave, schedutil, or conservative)$CLR_RESET"
has_errors=true
fi
if [[ -n $IPV6_MODE ]]&&[[ ! $IPV6_MODE =~ ^(auto|manual|disabled)$ ]];then
echo -e "${CLR_RED}Invalid IPV6_MODE: $IPV6_MODE (must be: auto, manual, or disabled)$CLR_RESET"
has_errors=true
fi
if [[ -n $IPV6_GATEWAY ]]&&[[ $IPV6_GATEWAY != "auto" ]];then
if ! validate_ipv6_gateway "$IPV6_GATEWAY";then
echo -e "${CLR_RED}Invalid IPV6_GATEWAY: $IPV6_GATEWAY (must be a valid IPv6 address or 'auto')$CLR_RESET"
has_errors=true
fi
fi
if [[ -n $IPV6_ADDRESS ]]&&! validate_ipv6_cidr "$IPV6_ADDRESS";then
echo -e "${CLR_RED}Invalid IPV6_ADDRESS: $IPV6_ADDRESS (must be valid IPv6 CIDR notation)$CLR_RESET"
has_errors=true
fi
if [[ $has_errors == true ]];then
return 1
fi
return 0
}
load_config(){
local file="$1"
if [[ -f $file ]];then
echo -e "$CLR_CYAN✓ Loading configuration from: $file$CLR_RESET"
source "$file"
if ! validate_config;then
echo -e "${CLR_RED}Configuration validation failed$CLR_RESET"
return 1
fi
return 0
else
echo -e "${CLR_RED}Config file not found: $file$CLR_RESET"
return 1
fi
}
save_config(){
local file="$1"
cat >"$file" <<EOF
# Proxmox Installer Configuration
# Generated: $(date)

# Network
INTERFACE_NAME="$INTERFACE_NAME"

# System
PVE_HOSTNAME="$PVE_HOSTNAME"
DOMAIN_SUFFIX="$DOMAIN_SUFFIX"
TIMEZONE="$TIMEZONE"
EMAIL="$EMAIL"
BRIDGE_MODE="$BRIDGE_MODE"
PRIVATE_SUBNET="$PRIVATE_SUBNET"

# Password (consider using environment variable instead)
NEW_ROOT_PASSWORD="$NEW_ROOT_PASSWORD"
PASSWORD_GENERATED="no"  # Track if password was auto-generated

# SSH
SSH_PUBLIC_KEY="$SSH_PUBLIC_KEY"

# Tailscale
INSTALL_TAILSCALE="$INSTALL_TAILSCALE"
TAILSCALE_AUTH_KEY="$TAILSCALE_AUTH_KEY"
TAILSCALE_SSH="$TAILSCALE_SSH"
TAILSCALE_WEBUI="$TAILSCALE_WEBUI"

# ZFS RAID mode (single, raid0, raid1)
ZFS_RAID="$ZFS_RAID"

# Proxmox repository (no-subscription, enterprise, test)
PVE_REPO_TYPE="$PVE_REPO_TYPE"
PVE_SUBSCRIPTION_KEY="$PVE_SUBSCRIPTION_KEY"

# SSL certificate (self-signed, letsencrypt)
SSL_TYPE="$SSL_TYPE"

# Audit logging (yes, no)
INSTALL_AUDITD="$INSTALL_AUDITD"

# Bandwidth monitoring with vnstat (yes, no)
INSTALL_VNSTAT="$INSTALL_VNSTAT"

# Unattended upgrades for automatic security updates (yes, no)
INSTALL_UNATTENDED_UPGRADES="$INSTALL_UNATTENDED_UPGRADES"

# CPU governor / power profile (performance, ondemand, powersave, schedutil, conservative)
CPU_GOVERNOR="${CPU_GOVERNOR:-performance}"

# IPv6 configuration (auto, manual, disabled)
IPV6_MODE="${IPV6_MODE:-auto}"
IPV6_GATEWAY="$IPV6_GATEWAY"
IPV6_ADDRESS="$IPV6_ADDRESS"
EOF
chmod 600 "$file"
echo -e "$CLR_CYAN✓ Configuration saved to: $file$CLR_RESET"
}
if [[ -n $CONFIG_FILE ]];then
load_config "$CONFIG_FILE"||exit 1
fi
log(){
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
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
show_progress(){
local pid=$1
local message="${2:-Processing}"
local done_message="${3:-$message}"
local silent=false
[[ ${3:-} == "--silent" || ${4:-} == "--silent" ]]&&silent=true
[[ ${3:-} == "--silent" ]]&&done_message="$message"
local i=0
while kill -0 "$pid" 2>/dev/null;do
printf "\r\e[K$CLR_CYAN%s %s$CLR_RESET" "${SPINNER_CHARS[i++%${#SPINNER_CHARS[@]}]}" "$message"
sleep 0.2
done
wait "$pid" 2>/dev/null
local exit_code=$?
if [[ $exit_code -eq 0 ]];then
if [[ $silent == true ]];then
printf "\r\e[K"
else
printf "\r\e[K$CLR_CYAN✓$CLR_RESET %s\n" "$done_message"
fi
else
printf "\r\e[K$CLR_RED✗$CLR_RESET %s\n" "$message"
fi
return $exit_code
}
wait_with_progress(){
local message="$1"
local timeout="$2"
local check_cmd="$3"
local interval="${4:-5}"
local done_message="${5:-$message}"
local start_time
start_time=$(date +%s)
local i=0
while true;do
local elapsed=$(($(date +%s)-start_time))
if eval "$check_cmd" 2>/dev/null;then
printf "\r\e[K$CLR_CYAN✓$CLR_RESET %s\n" "$done_message"
return 0
fi
if [ $elapsed -ge $timeout ];then
printf "\r\e[K$CLR_RED✗$CLR_RESET %s timed out\n" "$message"
return 1
fi
printf "\r\e[K$CLR_CYAN%s %s$CLR_RESET" "${SPINNER_CHARS[i++%${#SPINNER_CHARS[@]}]}" "$message"
sleep "$interval"
done
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
WIZARD_WIDTH=60
WIZARD_TOTAL_STEPS=6
GUM_PRIMARY="#00B1FF"
GUM_ACCENT="#FF8700"
GUM_SUCCESS="#55FF55"
GUM_WARNING="#FFFF55"
GUM_ERROR="#FF5555"
GUM_MUTED="#585858"
GUM_BORDER="#444444"
GUM_HETZNER="#D70000"
ANSI_PRIMARY=$'\033[38;2;0;177;255m'
ANSI_ACCENT=$'\033[38;5;208m'
ANSI_SUCCESS=$'\033[38;2;85;255;85m'
ANSI_WARNING=$'\033[38;2;255;255;85m'
ANSI_ERROR=$'\033[38;2;255;85;85m'
ANSI_MUTED=$'\033[38;5;240m'
ANSI_HETZNER=$'\033[38;5;160m'
ANSI_RESET=$'\033[0m'
ANSI_CURSOR_HIDE=$'\033[?25l'
ANSI_CURSOR_SHOW=$'\033[?25h'
wiz_cursor_hide(){
printf '%s' "$ANSI_CURSOR_HIDE"
trap 'printf "%s" "$ANSI_CURSOR_SHOW"' EXIT INT TERM HUP
}
wiz_cursor_show(){
printf '%s' "$ANSI_CURSOR_SHOW"
}
BANNER_LETTER_COUNT=7
wiz_banner(){
printf '%s\n' \
"" \
"$ANSI_MUTED    _____                                             $ANSI_RESET" \
"$ANSI_MUTED   |  __ \\                                            $ANSI_RESET" \
"$ANSI_MUTED   | |__) | _ __   ___  ${ANSI_ACCENT}__  __$ANSI_MUTED  _ __ ___    ___  ${ANSI_ACCENT}__  __$ANSI_RESET" \
"$ANSI_MUTED   |  ___/ | '__| / _ \\ $ANSI_ACCENT\\ \\/ /$ANSI_MUTED | '_ \` _ \\  / _ \\ $ANSI_ACCENT\\ \\/ /$ANSI_RESET" \
"$ANSI_MUTED   | |     | |   | (_) |$ANSI_ACCENT >  <$ANSI_MUTED  | | | | | || (_) |$ANSI_ACCENT >  <$ANSI_RESET" \
"$ANSI_MUTED   |_|     |_|    \\___/ $ANSI_ACCENT/_/\\_\\$ANSI_MUTED |_| |_| |_| \\___/ $ANSI_ACCENT/_/\\_\\$ANSI_RESET" \
"" \
"$ANSI_HETZNER               Hetzner ${ANSI_MUTED}Automated Installer$ANSI_RESET" \
""
}
_wiz_banner_frame(){
local h="${1:--1}"
local M="$ANSI_MUTED"
local A="$ANSI_ACCENT"
local R="$ANSI_RESET"
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
local line_hetzner="$ANSI_HETZNER               Hetzner ${M}Automated Installer$R"
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
wiz_banner_animated(){
local duration="${1:-30}"
local frame_delay="${2:-0.1}"
local end_time=$((SECONDS+duration))
printf '%s' "$ANSI_CURSOR_HIDE"
clear
local direction=1
local current_letter=0
while [[ $SECONDS -lt $end_time ]];do
_wiz_banner_frame "$current_letter"
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
done
clear
wiz_banner
printf '%s' "$ANSI_CURSOR_SHOW"
}
WIZ_BANNER_PID=""
wiz_banner_animated_start(){
local frame_delay="${1:-0.1}"
wiz_banner_animated_stop 2>/dev/null
printf '%s' "$ANSI_CURSOR_HIDE"
clear
(local direction=1
local current_letter=0
trap 'exit 0' TERM INT
while true;do
_wiz_banner_frame "$current_letter"
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
WIZ_BANNER_PID=$!
}
wiz_banner_animated_stop(){
if [[ -n $WIZ_BANNER_PID ]];then
kill "$WIZ_BANNER_PID" 2>/dev/null
wait "$WIZ_BANNER_PID" 2>/dev/null
WIZ_BANNER_PID=""
fi
clear
printf '%s' "$ANSI_CURSOR_SHOW"
}
wiz_banner_intro(){
wiz_banner_animated 1 0.1
}
_wiz_progress_bar(){
local current="$1"
local total="$2"
local width="${3:-50}"
if [[ $total -le 0 ]];then
total=1
fi
if [[ $width -le 0 ]];then
width=50
fi
if [[ $current -lt 0 ]];then
current=0
elif [[ $current -gt $total ]];then
current=$total
fi
local filled=$((width*current/total))
if [[ $filled -lt 0 ]];then
filled=0
elif [[ $filled -gt $width ]];then
filled=$width
fi
local empty=$((width-filled))
local bar=""
for ((i=0; i<filled; i++));do bar+="█";done
for ((i=0; i<empty; i++));do bar+="░";done
printf "%s" "$bar"
}
_wiz_field(){
local label="$1"
local value="$2"
printf "%s %s %s" \
"$(gum style --foreground "$GUM_SUCCESS" "✓")" \
"$(gum style --foreground "$GUM_MUTED" "$label:")" \
"$(gum style --foreground "$GUM_PRIMARY" "$value")"
}
_wiz_field_pending(){
local label="$1"
printf "%s %s %s" \
"$(gum style --foreground "$GUM_MUTED" "○")" \
"$(gum style --foreground "$GUM_MUTED" "$label:")" \
"$(gum style --foreground "$GUM_MUTED" "...")"
}
wiz_box(){
local step="$1"
local title="$2"
local content="$3"
local show_back="${4:-true}"
local header
header="$(gum style --foreground "$GUM_PRIMARY" --bold "Step $step/$WIZARD_TOTAL_STEPS: $title")"
local progress
progress="$(gum style --foreground "$GUM_MUTED" "$(_wiz_progress_bar "$step" "$WIZARD_TOTAL_STEPS" 53)")"
local footer=""
if [[ $show_back == "true" && $step -gt 1 ]];then
footer+="$(gum style --foreground "$GUM_MUTED" "[B] Back")  "
fi
footer+="$(gum style --foreground "$GUM_ACCENT" "[Enter] Next")  "
footer+="$(gum style --foreground "$GUM_MUTED" "[Q] Quit")"
clear
wiz_banner
gum style \
--border rounded \
--border-foreground "$GUM_BORDER" \
--width "$WIZARD_WIDTH" \
--padding "0 1" \
"$header" \
"$progress" \
"" \
"$content" \
"" \
"$footer"
}
wiz_input(){
local prompt="$1"
local default="${2:-}"
local placeholder="${3:-$default}"
local password="${4:-false}"
local args=(
--prompt "$prompt "
--cursor.foreground "$GUM_ACCENT"
--prompt.foreground "$GUM_PRIMARY"
--placeholder.foreground "$GUM_MUTED"
--width "$((WIZARD_WIDTH-4))")
[[ -n $default ]]&&args+=(--value "$default")
[[ -n $placeholder ]]&&args+=(--placeholder "$placeholder")
[[ $password == "true" ]]&&args+=(--password)
gum input "${args[@]}"
}
wiz_choose(){
local header="$1"
shift
local options=("$@")
local result
result=$(gum choose \
--header "$header" \
--cursor "› " \
--cursor.foreground "$GUM_ACCENT" \
--selected.foreground "$GUM_PRIMARY" \
--header.foreground "$GUM_MUTED" \
--height 10 \
"${options[@]}")
WIZ_SELECTED_INDEX=0
for i in "${!options[@]}";do
if [[ ${options[$i]} == "$result" ]];then
WIZ_SELECTED_INDEX=$i
break
fi
done
printf "%s" "$result"
}
wiz_choose_multi(){
local header="$1"
shift
local options=("$@")
local result
result=$(gum choose \
--header "$header" \
--no-limit \
--cursor "› " \
--cursor.foreground "$GUM_ACCENT" \
--selected.foreground "$GUM_SUCCESS" \
--header.foreground "$GUM_MUTED" \
--height 12 \
"${options[@]}")
WIZ_SELECTED_INDICES=()
while IFS= read -r line;do
[[ -z $line ]]&&continue
for i in "${!options[@]}";do
if [[ ${options[$i]} == "$line" ]];then
WIZ_SELECTED_INDICES+=("$i")
break
fi
done
done <<<"$result"
printf "%s" "$result"
}
wiz_confirm(){
local question="$1"
gum confirm \
--prompt.foreground "$GUM_PRIMARY" \
--selected.background "$GUM_ACCENT" \
--selected.foreground "#000000" \
--unselected.background "$GUM_MUTED" \
--unselected.foreground "#FFFFFF" \
"$question"
}
wiz_spin(){
local title="$1"
shift
gum spin \
--spinner points \
--spinner.foreground "$GUM_ACCENT" \
--title "$title" \
--title.foreground "$GUM_PRIMARY" \
-- "$@"
}
wiz_msg(){
local type="$1"
local msg="$2"
local color icon
case "$type" in
error)color="$GUM_ERROR"
icon="✗"
;;
warning)color="$GUM_WARNING"
icon="⚠"
;;
success)color="$GUM_SUCCESS"
icon="✓"
;;
info)color="$GUM_PRIMARY"
icon="ℹ"
;;
*)color="$GUM_MUTED"
icon="•"
esac
gum style --foreground "$color" "$icon $msg"
}
wiz_get_timezones(){
cat <<'TIMEZONES'
Europe/Kyiv|Europe/London|Europe/Paris|Europe/Berlin|Europe/Amsterdam|Europe/Brussels|Europe/Vienna|Europe/Warsaw|Europe/Prague|Europe/Budapest|Europe/Rome|Europe/Madrid|Europe/Lisbon|Europe/Athens|Europe/Helsinki|Europe/Stockholm|Europe/Oslo|Europe/Copenhagen|Europe/Dublin|Europe/Zurich|Europe/Moscow|Europe/Istanbul|America/New_York|America/Chicago|America/Denver|America/Los_Angeles|America/Toronto|America/Vancouver|America/Mexico_City|America/Sao_Paulo|America/Buenos_Aires|America/Lima|America/Bogota|America/Santiago|Asia/Tokyo|Asia/Shanghai|Asia/Hong_Kong|Asia/Singapore|Asia/Seoul|Asia/Taipei|Asia/Bangkok|Asia/Jakarta|Asia/Manila|Asia/Kolkata|Asia/Mumbai|Asia/Dubai|Asia/Jerusalem|Asia/Riyadh|Australia/Sydney|Australia/Melbourne|Australia/Brisbane|Australia/Perth|Pacific/Auckland|Pacific/Fiji|Pacific/Honolulu|Africa/Cairo|Africa/Johannesburg|Africa/Lagos|Africa/Nairobi|UTC
TIMEZONES
}
wiz_wait_nav(){
local key
while true;do
if ! IFS= read -rsn1 -t 60 key;then
echo "quit"
return
fi
case "$key" in
""|$'\n')echo "next"
return
;;
"b"|"B")echo "back"
return
;;
"q"|"Q")echo "quit"
return
;;
$'\x1b')read -rsn2 -t 0.1 _||true
esac
done
}
wiz_handle_quit(){
echo ""
if wiz_confirm "Are you sure you want to quit?";then
clear
gum style --foreground "$GUM_ERROR" "Installation cancelled."
exit 1
fi
return 1
}
wiz_build_content(){
local content=""
for field in "$@";do
local label="${field%%|*}"
local value="${field#*|}"
if [[ -n $value ]];then
content+="$(_wiz_field "$label" "$value")"$'\n'
else
content+="$(_wiz_field_pending "$label")"$'\n'
fi
done
printf "%s" "${content%$'\n'}"
}
wiz_section(){
local title="$1"
gum style --foreground "$GUM_PRIMARY" --bold "$title"
}
declare -a WIZ_FIELD_LABELS=()
declare -a WIZ_FIELD_VALUES=()
declare -a WIZ_FIELD_TYPES=()
declare -a WIZ_FIELD_OPTIONS=()
declare -a WIZ_FIELD_DEFAULTS=()
declare -a WIZ_FIELD_VALIDATORS=()
WIZ_CURRENT_FIELD=0
_wiz_clear_fields(){
WIZ_FIELD_LABELS=()
WIZ_FIELD_VALUES=()
WIZ_FIELD_TYPES=()
WIZ_FIELD_OPTIONS=()
WIZ_FIELD_DEFAULTS=()
WIZ_FIELD_VALIDATORS=()
WIZ_CURRENT_FIELD=0
}
_wiz_add_field(){
local label="$1"
local type="$2"
local default_or_options="$3"
local validator="${4:-}"
WIZ_FIELD_LABELS+=("$label")
WIZ_FIELD_VALUES+=("")
WIZ_FIELD_TYPES+=("$type")
if [[ $type == "choose" || $type == "multi" ]];then
WIZ_FIELD_OPTIONS+=("$default_or_options")
WIZ_FIELD_DEFAULTS+=("")
else
WIZ_FIELD_OPTIONS+=("")
WIZ_FIELD_DEFAULTS+=("$default_or_options")
fi
WIZ_FIELD_VALIDATORS+=("$validator")
}
_wiz_build_fields_content(){
local cursor_idx="${1:--1}"
local edit_idx="${2:--1}"
local edit_buffer="${3:-}"
local edit_cursor="${4:-0}"
local select_idx="${5:--1}"
local select_cursor="${6:-0}"
local content=""
local i
for i in "${!WIZ_FIELD_LABELS[@]}";do
local label="${WIZ_FIELD_LABELS[$i]}"
local value="${WIZ_FIELD_VALUES[$i]}"
local type="${WIZ_FIELD_TYPES[$i]}"
local display_value="$value"
if [[ $type == "password" && -n $value ]];then
display_value="********"
fi
if [[ $i -eq $select_idx ]];then
content+="$ANSI_ACCENT› $ANSI_RESET"
content+="$ANSI_PRIMARY$label:$ANSI_RESET"
content+=$'\n'
local field_options="${WIZ_FIELD_OPTIONS[$i]}"
local -a opts
IFS='|' read -ra opts <<<"$field_options"
local opt_idx=0
for opt in "${opts[@]}";do
if [[ $opt_idx -eq $select_cursor ]];then
content+="$ANSI_ACCENT› $ANSI_PRIMARY$opt$ANSI_RESET"
else
content+="  $ANSI_MUTED$opt$ANSI_RESET"
fi
content+=$'\n'
((opt_idx++))
done
content="${content%$'\n'}"
elif [[ $i -eq $edit_idx ]];then
content+="$ANSI_ACCENT› $ANSI_RESET"
content+="$ANSI_PRIMARY$label: $ANSI_RESET"
if [[ $type == "password" ]];then
local before_cursor="" after_cursor=""
for ((j=0; j<edit_cursor; j++));do before_cursor+="*";done
for ((j=edit_cursor; j<${#edit_buffer}; j++));do after_cursor+="*";done
content+="$ANSI_SUCCESS$before_cursor$ANSI_ACCENT│$ANSI_SUCCESS$after_cursor$ANSI_RESET"
else
local before_cursor="${edit_buffer:0:edit_cursor}"
local after_cursor="${edit_buffer:edit_cursor}"
content+="$ANSI_SUCCESS$before_cursor$ANSI_ACCENT│$ANSI_SUCCESS$after_cursor$ANSI_RESET"
fi
elif [[ $i -eq $cursor_idx ]];then
if [[ -n $value ]];then
content+="$ANSI_ACCENT› $ANSI_RESET"
content+="$ANSI_MUTED$label: $ANSI_RESET"
content+="$ANSI_PRIMARY$display_value$ANSI_RESET"
else
content+="$ANSI_ACCENT› $ANSI_RESET"
content+="$ANSI_ACCENT$label: $ANSI_RESET"
content+="$ANSI_MUTED...$ANSI_RESET"
fi
else
if [[ -n $value ]];then
content+="$ANSI_SUCCESS✓ $ANSI_RESET"
content+="$ANSI_MUTED$label: $ANSI_RESET"
content+="$ANSI_PRIMARY$display_value$ANSI_RESET"
else
content+="$ANSI_MUTED○ $ANSI_RESET"
content+="$ANSI_MUTED$label: $ANSI_RESET"
content+="$ANSI_MUTED...$ANSI_RESET"
fi
fi
content+=$'\n'
done
printf "%s" "${content%$'\n'}"
}
_wiz_draw_box(){
local step="$1"
local title="$2"
local content="$3"
local footer="$4"
local header
header="${ANSI_PRIMARY}Step $step/$WIZARD_TOTAL_STEPS: $title$ANSI_RESET"
local progress
progress="$ANSI_MUTED$(_wiz_progress_bar "$step" "$WIZARD_TOTAL_STEPS" 53)$ANSI_RESET"
local box_content
box_content=$(gum style \
--border rounded \
--border-foreground "$GUM_BORDER" \
--width "$WIZARD_WIDTH" \
--padding "0 1" \
"$header" \
"$progress" \
"" \
"$content" \
"" \
"$footer")
local buffer=""
buffer+='\033[H'
buffer+='\033[J'
buffer+=$'\n'
buffer+="$ANSI_MUTED    _____                                             $ANSI_RESET"$'\n'
buffer+="$ANSI_MUTED   |  __ \\                                            $ANSI_RESET"$'\n'
buffer+="$ANSI_MUTED   | |__) | _ __   ___  ${ANSI_ACCENT}__  __$ANSI_MUTED  _ __ ___    ___  ${ANSI_ACCENT}__  __$ANSI_RESET"$'\n'
buffer+="$ANSI_MUTED   |  ___/ | '__| / _ \\ $ANSI_ACCENT\\ \\/ /$ANSI_MUTED | '_ \` _ \\  / _ \\ $ANSI_ACCENT\\ \\/ /$ANSI_RESET"$'\n'
buffer+="$ANSI_MUTED   | |     | |   | (_) |$ANSI_ACCENT >  <$ANSI_MUTED  | | | | | || (_) |$ANSI_ACCENT >  <$ANSI_RESET"$'\n'
buffer+="$ANSI_MUTED   |_|     |_|    \\___/ $ANSI_ACCENT/_/\\_\\$ANSI_MUTED |_| |_| |_| \\___/ $ANSI_ACCENT/_/\\_\\$ANSI_RESET"$'\n'
buffer+=$'\n'
buffer+="$ANSI_HETZNER               Hetzner ${ANSI_MUTED}Automated Installer$ANSI_RESET"$'\n'
buffer+=$'\n'
buffer+="$box_content"
printf '%b' "$buffer"
}
wiz_step_interactive(){
local step="$1"
local title="$2"
local num_fields=${#WIZ_FIELD_LABELS[@]}
local show_back="true"
[[ $step -eq 1 ]]&&show_back="false"
WIZ_CURRENT_FIELD=0
for i in "${!WIZ_FIELD_VALUES[@]}";do
if [[ -z ${WIZ_FIELD_VALUES[$i]} ]];then
WIZ_CURRENT_FIELD=$i
break
fi
done
local edit_mode=false
local edit_buffer=""
local edit_cursor=0
local select_mode=false
local select_cursor=0
local select_opts_count=0
while true;do
local footer=""
local all_filled=true
for val in "${WIZ_FIELD_VALUES[@]}";do
[[ -z $val ]]&&all_filled=false&&break
done
if [[ $select_mode == "true" ]];then
footer+="$ANSI_MUTED[$ANSI_ACCENT↑/↓$ANSI_MUTED] Select$ANSI_RESET  "
footer+="$ANSI_ACCENT[Enter] Confirm$ANSI_RESET  "
footer+="$ANSI_MUTED[Esc] Cancel$ANSI_RESET"
elif [[ $edit_mode == "true" ]];then
local current_type="${WIZ_FIELD_TYPES[$WIZ_CURRENT_FIELD]}"
footer+="$ANSI_MUTED[$ANSI_ACCENT←/→$ANSI_MUTED] Move$ANSI_RESET  "
if [[ $current_type == "password" ]];then
footer+="$ANSI_ACCENT[G] Generate$ANSI_RESET  "
fi
footer+="$ANSI_ACCENT[Enter] Save$ANSI_RESET  "
footer+="$ANSI_MUTED[Esc] Cancel$ANSI_RESET"
else
if [[ $show_back == "true" ]];then
footer+="$ANSI_MUTED[B] Back$ANSI_RESET  "
fi
footer+="$ANSI_MUTED[$ANSI_ACCENT↑/↓$ANSI_MUTED] Navigate$ANSI_RESET  "
footer+="$ANSI_ACCENT[Enter] Edit$ANSI_RESET  "
if [[ $all_filled == "true" ]];then
footer+="$ANSI_ACCENT[N] Next$ANSI_RESET  "
fi
footer+="$ANSI_MUTED[${ANSI_ACCENT}Q$ANSI_MUTED] Quit$ANSI_RESET"
fi
local content
if [[ $select_mode == "true" ]];then
content=$(_wiz_build_fields_content "-1" "-1" "" "0" "$WIZ_CURRENT_FIELD" "$select_cursor")
elif [[ $edit_mode == "true" ]];then
content=$(_wiz_build_fields_content "-1" "$WIZ_CURRENT_FIELD" "$edit_buffer" "$edit_cursor" "-1" "0")
else
content=$(_wiz_build_fields_content "$WIZ_CURRENT_FIELD" "-1" "" "0" "-1" "0")
fi
_wiz_draw_box "$step" "$title" "$content" "$footer"
printf '%s' "$ANSI_CURSOR_HIDE"
local key
IFS= read -rsn1 key
if [[ $select_mode == "true" ]];then
case "$key" in
$'\e')local seq=""
read -rsn2 -t 0.1 seq||true
case "$seq" in
'[A')((select_cursor>0))&&((select_cursor--))
;;
'[B')((select_cursor<select_opts_count-1))&&((select_cursor++))
;;
'')select_mode=false
select_cursor=0
esac
;;
"")local field_options="${WIZ_FIELD_OPTIONS[$WIZ_CURRENT_FIELD]}"
local -a opts
IFS='|' read -ra opts <<<"$field_options"
WIZ_FIELD_VALUES[WIZ_CURRENT_FIELD]="${opts[$select_cursor]}"
select_mode=false
select_cursor=0
for ((i=WIZ_CURRENT_FIELD+1; i<num_fields; i++));do
if [[ -z ${WIZ_FIELD_VALUES[$i]} ]];then
WIZ_CURRENT_FIELD=$i
break
fi
done
;;
"j")((select_cursor<select_opts_count-1))&&((select_cursor++));;
"k")((select_cursor>0))&&((select_cursor--))
esac
elif [[ $edit_mode == "true" ]];then
case "$key" in
$'\e')local seq=""
read -rsn2 -t 0.1 seq||true
case "$seq" in
'[D')((edit_cursor>0))&&((edit_cursor--))
;;
'[C')((edit_cursor<${#edit_buffer}))&&((edit_cursor++))
;;
'[H')edit_cursor=0
;;
'[F')edit_cursor=${#edit_buffer}
;;
'[3')read -rsn1 _
if [[ $edit_cursor -lt ${#edit_buffer} ]];then
edit_buffer="${edit_buffer:0:edit_cursor}${edit_buffer:edit_cursor+1}"
fi
;;
'[1')read -rsn1 _
edit_cursor=0
;;
'[4')read -rsn1 _
edit_cursor=${#edit_buffer}
;;
'')edit_mode=false
edit_buffer=""
edit_cursor=0
esac
;;
"")local validator="${WIZ_FIELD_VALIDATORS[$WIZ_CURRENT_FIELD]}"
if [[ -n $validator && -n $edit_buffer ]];then
if ! "$validator" "$edit_buffer" 2>/dev/null;then
continue
fi
fi
WIZ_FIELD_VALUES[WIZ_CURRENT_FIELD]="$edit_buffer"
edit_mode=false
edit_buffer=""
edit_cursor=0
for ((i=WIZ_CURRENT_FIELD+1; i<num_fields; i++));do
if [[ -z ${WIZ_FIELD_VALUES[$i]} ]];then
WIZ_CURRENT_FIELD=$i
break
fi
done
;;
$'\x7f'|$'\b')if
[[ $edit_cursor -gt 0 ]]
then
edit_buffer="${edit_buffer:0:edit_cursor-1}${edit_buffer:edit_cursor}"
((edit_cursor--))
fi
;;
"g"|"G")local current_type="${WIZ_FIELD_TYPES[$WIZ_CURRENT_FIELD]}"
if [[ $current_type == "password" ]];then
edit_buffer=$(generate_password 16)
edit_cursor=${#edit_buffer}
else
edit_buffer="${edit_buffer:0:edit_cursor}$key${edit_buffer:edit_cursor}"
((edit_cursor++))
fi
;;
*)if
[[ $key =~ ^[[:print:]]$ || $key == " " ]]
then
edit_buffer="${edit_buffer:0:edit_cursor}$key${edit_buffer:edit_cursor}"
((edit_cursor++))
fi
esac
else
case "$key" in
$'\e')read -rsn2 -t 0.1 key 2>/dev/null||true
case "$key" in
'[A')((WIZ_CURRENT_FIELD>0))&&((WIZ_CURRENT_FIELD--));;
'[B')((WIZ_CURRENT_FIELD<num_fields-1))&&((WIZ_CURRENT_FIELD++))
esac
;;
""|$'\n')local field_type="${WIZ_FIELD_TYPES[$WIZ_CURRENT_FIELD]}"
if [[ $field_type == "filter" ]];then
local field_options="${WIZ_FIELD_OPTIONS[$WIZ_CURRENT_FIELD]}"
local label="${WIZ_FIELD_LABELS[$WIZ_CURRENT_FIELD]}"
local current_val="${WIZ_FIELD_VALUES[$WIZ_CURRENT_FIELD]}"
local new_value
printf '%s' "$ANSI_CURSOR_SHOW"
clear
wiz_banner
local opts_newline="${field_options//|/$'\n'}"
new_value=$(gum filter \
--height 10 \
--header "Select $label:" \
--header.foreground "$GUM_MUTED" \
--indicator "› " \
--indicator.foreground "$GUM_ACCENT" \
--match.foreground "$GUM_PRIMARY" \
--prompt "Search: " \
--prompt.foreground "$GUM_ACCENT" \
--placeholder "Type to filter..." <<< \
"$opts_newline" 2>/dev/null)||true
printf '%s' "$ANSI_CURSOR_HIDE"
if [[ -n $new_value ]];then
WIZ_FIELD_VALUES[WIZ_CURRENT_FIELD]="$new_value"
for ((i=WIZ_CURRENT_FIELD+1; i<num_fields; i++));do
if [[ -z ${WIZ_FIELD_VALUES[$i]} ]];then
WIZ_CURRENT_FIELD=$i
break
fi
done
fi
elif [[ $field_type == "choose" || $field_type == "multi" ]];then
select_mode=true
select_cursor=0
local field_options="${WIZ_FIELD_OPTIONS[$WIZ_CURRENT_FIELD]}"
local -a opts
IFS='|' read -ra opts <<<"$field_options"
select_opts_count=${#opts[@]}
local current_val="${WIZ_FIELD_VALUES[$WIZ_CURRENT_FIELD]}"
if [[ -n $current_val ]];then
for idx in "${!opts[@]}";do
if [[ ${opts[$idx]} == "$current_val" ]];then
select_cursor=$idx
break
fi
done
fi
else
edit_mode=true
edit_buffer="${WIZ_FIELD_VALUES[$WIZ_CURRENT_FIELD]:-${WIZ_FIELD_DEFAULTS[$WIZ_CURRENT_FIELD]}}"
edit_cursor=${#edit_buffer}
fi
;;
"j")((WIZ_CURRENT_FIELD<num_fields-1))&&((WIZ_CURRENT_FIELD++));;
"k")((WIZ_CURRENT_FIELD>0))&&((WIZ_CURRENT_FIELD--));;
"n"|"N")if
[[ $all_filled == "true" ]]
then
echo "next"
return
fi
;;
"b"|"B")if
[[ $show_back == "true" ]]
then
echo "back"
return
fi
;;
"q"|"Q")echo ""
if wiz_confirm "Are you sure you want to quit?";then
clear
printf '%s\n' "${ANSI_ERROR}Installation cancelled.$ANSI_RESET"
exit 1
fi
esac
fi
done
}
wiz_demo(){
wiz_cursor_hide
local content
content=$(wiz_build_content \
"Interface|enp0s31f6" \
"Bridge|Internal NAT (vmbr0)" \
"Private subnet|10.0.0.0/24" \
"IPv6|2a01:4f8::1 (auto)")
wiz_box 2 "Network" "$content"
echo ""
echo "--- Demo: waiting for navigation ---"
local nav
nav=$(wiz_wait_nav)
echo "Navigation: $nav"
echo ""
echo "--- Demo: interactive step ---"
_wiz_clear_fields
_wiz_add_field "Hostname" "input" "pve"
_wiz_add_field "Domain" "input" "local"
_wiz_add_field "Email" "input" "admin@example.com"
_wiz_add_field "Password" "password" ""
_wiz_add_field "Timezone" "choose" "Europe/Kyiv|Europe/London|America/New_York|UTC"
local result
result=$(wiz_step_interactive 1 "System")
echo "Step result: $result"
echo "Values:"
for i in "${!WIZ_FIELD_LABELS[@]}";do
local display="${WIZ_FIELD_VALUES[$i]}"
[[ ${WIZ_FIELD_TYPES[$i]} == "password" ]]&&display="********"
echo "  ${WIZ_FIELD_LABELS[$i]}: $display"
done
wiz_msg success "Demo complete!"
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
collect_system_info(){
local errors=0
wiz_banner_animated_start 0.1
local packages_to_install=""
local need_charm_repo=false
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
errors=$((errors+1))
fi
if ! ping -c 1 -W 3 "$DNS_PRIMARY" >/dev/null 2>&1;then
errors=$((errors+1))
fi
local free_space_mb
free_space_mb=$(df -m /root|awk 'NR==2 {print $4}')
if [[ $free_space_mb -lt $MIN_DISK_SPACE_MB ]];then
errors=$((errors+1))
fi
local total_ram_mb
total_ram_mb=$(free -m|awk '/^Mem:/{print $2}')
if [[ $total_ram_mb -lt $MIN_RAM_MB ]];then
errors=$((errors+1))
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
if [[ ! -e /dev/kvm ]];then
errors=$((errors+1))
fi
detect_drives
wiz_banner_animated_stop
if [[ $errors -gt 0 ]];then
log "ERROR: Pre-flight checks failed with $errors error(s)"
exit 1
fi
if [[ $DRIVE_COUNT -eq 0 ]];then
log "ERROR: No drives detected"
exit 1
fi
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
_collect_inputs(){
PVE_HOSTNAME="${PVE_HOSTNAME:-$DEFAULT_HOSTNAME}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-$DEFAULT_DOMAIN}"
TIMEZONE="${TIMEZONE:-$DEFAULT_TIMEZONE}"
EMAIL="${EMAIL:-$DEFAULT_EMAIL}"
BRIDGE_MODE="${BRIDGE_MODE:-$DEFAULT_BRIDGE_MODE}"
PRIVATE_SUBNET="${PRIVATE_SUBNET:-$DEFAULT_SUBNET}"
DEFAULT_SHELL="${DEFAULT_SHELL:-zsh}"
CPU_GOVERNOR="${CPU_GOVERNOR:-$DEFAULT_CPU_GOVERNOR}"
IPV6_MODE="${IPV6_MODE:-$DEFAULT_IPV6_MODE}"
if [[ $IPV6_MODE == "disabled" ]];then
MAIN_IPV6=""
IPV6_GATEWAY=""
FIRST_IPV6_CIDR=""
elif [[ $IPV6_MODE == "manual" ]];then
IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
if [[ -n $IPV6_ADDRESS ]];then
MAIN_IPV6="${IPV6_ADDRESS%/*}"
fi
else
IPV6_GATEWAY="${IPV6_GATEWAY:-$DEFAULT_IPV6_GATEWAY}"
fi
print_success "Hostname:" "$PVE_HOSTNAME"
print_success "Domain:" "$DOMAIN_SUFFIX"
print_success "Timezone:" "$TIMEZONE"
print_success "Email:" "$EMAIL"
print_success "Bridge mode:" "$BRIDGE_MODE"
if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]];then
print_success "Private subnet:" "$PRIVATE_SUBNET"
fi
print_success "Default shell:" "$DEFAULT_SHELL"
print_success "Power profile:" "$CPU_GOVERNOR"
if [[ $IPV6_MODE == "disabled" ]];then
print_success "IPv6:" "disabled"
elif [[ -n $MAIN_IPV6 ]];then
print_success "IPv6:" "$MAIN_IPV6 (gateway: $IPV6_GATEWAY)"
else
print_warning "IPv6: not detected"
fi
if [[ -z $ZFS_RAID ]];then
if [[ ${DRIVE_COUNT:-0} -ge 2 ]];then
ZFS_RAID="raid1"
else
ZFS_RAID="single"
fi
fi
print_success "ZFS mode:" "$ZFS_RAID"
if [[ -z $NEW_ROOT_PASSWORD ]];then
NEW_ROOT_PASSWORD=$(generate_password 16)
PASSWORD_GENERATED="yes"
print_success "Password:" "auto-generated (will be shown at the end)"
else
if ! validate_password_with_error "$NEW_ROOT_PASSWORD";then
exit 1
fi
print_success "Password:" "******** (from env)"
fi
if [[ -z $SSH_PUBLIC_KEY ]];then
SSH_PUBLIC_KEY=$(get_rescue_ssh_key)
fi
if [[ -z $SSH_PUBLIC_KEY ]];then
print_error "SSH_PUBLIC_KEY is required"
exit 1
fi
parse_ssh_key "$SSH_PUBLIC_KEY"
print_success "SSH key:" "configured ($SSH_KEY_TYPE)"
PVE_REPO_TYPE="${PVE_REPO_TYPE:-no-subscription}"
print_success "Repository:" "$PVE_REPO_TYPE"
if [[ $PVE_REPO_TYPE == "enterprise" && -n $PVE_SUBSCRIPTION_KEY ]];then
print_success "Subscription key:" "configured"
fi
SSL_TYPE="${SSL_TYPE:-self-signed}"
if [[ $SSL_TYPE == "letsencrypt" ]];then
local le_fqdn="${FQDN:-$PVE_HOSTNAME.$DOMAIN_SUFFIX}"
local expected_ip="${MAIN_IPV4_CIDR%/*}"
validate_dns_resolution "$le_fqdn" "$expected_ip"
local dns_result=$?
case $dns_result in
0)print_success "SSL certificate:" "letsencrypt (DNS verified: $le_fqdn → $expected_ip)"
;;
1)log "ERROR: DNS validation failed - $le_fqdn does not resolve"
print_error "SSL certificate: letsencrypt (DNS FAILED)"
print_error "$le_fqdn does not resolve"
echo ""
print_info "Let's Encrypt requires valid DNS configuration."
print_info "Create DNS A record: $le_fqdn → $expected_ip"
exit 1
;;
2)log "ERROR: DNS validation failed - $le_fqdn resolves to $DNS_RESOLVED_IP, expected $expected_ip"
print_error "SSL certificate: letsencrypt (DNS MISMATCH)"
print_error "$le_fqdn resolves to $DNS_RESOLVED_IP, expected $expected_ip"
echo ""
print_info "Update DNS A record: $le_fqdn → $expected_ip"
exit 1
esac
else
print_success "SSL certificate:" "$SSL_TYPE"
fi
INSTALL_AUDITD="${INSTALL_AUDITD:-no}"
if [[ $INSTALL_AUDITD == "yes" ]];then
print_success "Audit logging:" "enabled"
else
print_success "Audit logging:" "disabled"
fi
INSTALL_VNSTAT="${INSTALL_VNSTAT:-yes}"
if [[ $INSTALL_VNSTAT == "yes" ]];then
print_success "Bandwidth monitoring:" "enabled (vnstat)"
else
print_success "Bandwidth monitoring:" "disabled"
fi
INSTALL_UNATTENDED_UPGRADES="${INSTALL_UNATTENDED_UPGRADES:-yes}"
if [[ $INSTALL_UNATTENDED_UPGRADES == "yes" ]];then
print_success "Auto security updates:" "enabled"
else
print_success "Auto security updates:" "disabled"
fi
INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-no}"
if [[ $INSTALL_TAILSCALE == "yes" ]];then
TAILSCALE_SSH="${TAILSCALE_SSH:-yes}"
TAILSCALE_WEBUI="${TAILSCALE_WEBUI:-yes}"
TAILSCALE_DISABLE_SSH="${TAILSCALE_DISABLE_SSH:-no}"
if [[ -n $TAILSCALE_AUTH_KEY ]];then
print_success "Tailscale:" "will be installed (auto-connect)"
else
print_success "Tailscale:" "will be installed (manual auth required)"
fi
print_success "Tailscale SSH:" "$TAILSCALE_SSH"
print_success "Tailscale WebUI:" "$TAILSCALE_WEBUI"
if [[ $TAILSCALE_SSH == "yes" && $TAILSCALE_DISABLE_SSH == "yes" ]];then
print_success "OpenSSH:" "will be disabled on first boot"
STEALTH_MODE="${STEALTH_MODE:-yes}"
if [[ $STEALTH_MODE == "yes" ]];then
print_success "Stealth firewall:" "enabled"
fi
else
STEALTH_MODE="${STEALTH_MODE:-no}"
fi
else
STEALTH_MODE="${STEALTH_MODE:-no}"
print_success "Tailscale:" "skipped"
fi
}
get_system_inputs(){
detect_network_interface
collect_network_info
print_success "Network interface:" "$INTERFACE_NAME"
_collect_inputs
FQDN="$PVE_HOSTNAME.$DOMAIN_SUFFIX"
if [[ $BRIDGE_MODE == "internal" || $BRIDGE_MODE == "both" ]];then
PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET"|cut -d'/' -f1|rev|cut -d'.' -f2-|rev)
PRIVATE_IP="$PRIVATE_CIDR.1"
SUBNET_MASK=$(echo "$PRIVATE_SUBNET"|cut -d'/' -f2)
PRIVATE_IP_CIDR="$PRIVATE_IP/$SUBNET_MASK"
fi
if [[ -n $SAVE_CONFIG ]];then
save_config "$SAVE_CONFIG"
fi
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
_fetch_iso_list(){
if [[ -z $_ISO_LIST_CACHE ]];then
_ISO_LIST_CACHE=$(curl -s "$PROXMOX_ISO_BASE_URL"|grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso'|sort -uV)
fi
echo "$_ISO_LIST_CACHE"
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
log "Downloading checksum file"
curl -sS -o SHA256SUMS "$PROXMOX_CHECKSUM_URL" >>"$LOG_FILE" 2>&1||true
local expected_checksum=""
if [[ -f "SHA256SUMS" ]];then
expected_checksum=$(grep "$ISO_FILENAME" SHA256SUMS|awk '{print $1}')
log "Expected checksum: $expected_checksum"
fi
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
wiz_banner
echo -e "${CLR_CYAN}INSTALLATION SUMMARY$CLR_RESET"
echo ""
echo "$summary"|column -t -s '|'|while IFS= read -r line;do
line="${line//\[OK\]/$CLR_CYAN[OK]$CLR_RESET}"
line="${line//\[WARN\]/$CLR_YELLOW[WARN]$CLR_RESET}"
line="${line//\[ERROR\]/$CLR_RED[ERROR]$CLR_RESET}"
echo -e "  $line"
done
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
log "CONFIG_FILE=$CONFIG_FILE"
log "VALIDATE_ONLY=$VALIDATE_ONLY"
log "QEMU_RAM_OVERRIDE=$QEMU_RAM_OVERRIDE"
log "QEMU_CORES_OVERRIDE=$QEMU_CORES_OVERRIDE"
log "PVE_REPO_TYPE=${PVE_REPO_TYPE:-no-subscription}"
log "SSL_TYPE=${SSL_TYPE:-self-signed}"
log "Step: collect_system_info"
collect_system_info
wiz_cursor_hide
_wiz_clear_fields
_wiz_add_field "Hostname" "input" "pve"
_wiz_add_field "Domain" "input" "local"
_wiz_add_field "Email" "input" "admin@example.com"
_wiz_add_field "Password" "password" ""
_wiz_add_field "Timezone" "filter" "$(wiz_get_timezones)"
wiz_step_interactive 1 "System"
wiz_cursor_show
clear
wiz_banner
echo ""
echo -e "${CLR_CYAN}Wizard exited.$CLR_RESET"
echo ""
exit 0
: <<'DISABLED_INSTALLATION'
log "Step: get_system_inputs"
get_system_inputs

# If validate-only mode, show summary and exit
if [[ $VALIDATE_ONLY == true ]]; then
  log "Validate-only mode: showing configuration summary"
  echo ""
  echo -e "${CLR_CYAN}✓ Configuration validated successfully${CLR_RESET}"
  echo ""
  echo "Configuration Summary:"
  echo "  Hostname:     $HOSTNAME"
  echo "  FQDN:         $FQDN"
  echo "  Email:        $EMAIL"
  echo "  Timezone:     $TIMEZONE"
  echo "  IPv4:         $MAIN_IPV4_CIDR"
  echo "  Gateway:      $MAIN_IPV4_GW"
  echo "  Interface:    $INTERFACE_NAME"
  echo "  ZFS Mode:     $ZFS_RAID_MODE"
  echo "  Drives:       ${DRIVES[*]}"
  echo "  Bridge Mode:  $BRIDGE_MODE"
  if [[ $BRIDGE_MODE != "external" ]]; then
    echo "  Private Net:  $PRIVATE_SUBNET"
  fi
  echo "  Tailscale:    $INSTALL_TAILSCALE"
  echo "  Auditd:       ${INSTALL_AUDITD:-no}"
  echo "  Repository:   ${PVE_REPO_TYPE:-no-subscription}"
  echo "  SSL:          ${SSL_TYPE:-self-signed}"
  if [[ -n $PROXMOX_ISO_VERSION ]]; then
    echo "  Proxmox ISO:  ${PROXMOX_ISO_VERSION}"
  else
    echo "  Proxmox ISO:  latest"
  fi
  if [[ -n $QEMU_RAM_OVERRIDE ]]; then
    echo "  QEMU RAM:     ${QEMU_RAM_OVERRIDE}MB (override)"
  fi
  if [[ -n $QEMU_CORES_OVERRIDE ]]; then
    echo "  QEMU Cores:   ${QEMU_CORES_OVERRIDE} (override)"
  fi
  echo ""
  echo -e "${CLR_GRAY}Run without --validate to start installation${CLR_RESET}"
  exit 0
fi

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

# Boot and configure via SSH
log "Step: boot_proxmox_with_port_forwarding"
boot_proxmox_with_port_forwarding || {
  log "ERROR: Failed to boot Proxmox with port forwarding"
  exit 1
}

# Configure Proxmox via SSH
log "Step: configure_proxmox_via_ssh"
configure_proxmox_via_ssh

# Mark installation as completed (disables error handler message)
INSTALL_COMPLETED=true

# Reboot to the main OS
log "Step: reboot_to_main_os"
reboot_to_main_os
DISABLED_INSTALLATION
