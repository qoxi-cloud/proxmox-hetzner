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
HEX_RED="#ff0000"
HEX_CYAN="#00b1ff"
HEX_YELLOW="#ffff00"
HEX_ORANGE="#ff8700"
HEX_GRAY="#585858"
HEX_HETZNER="#d70000"
HEX_GREEN="#00ff00"
HEX_WHITE="#ffffff"
HEX_NONE="7"
MENU_BOX_WIDTH=60
VERSION="2.0.237-pr.21"
GITHUB_REPO="${GITHUB_REPO:-qoxi-cloud/proxmox-hetzner}"
GITHUB_BRANCH="${GITHUB_BRANCH:-feat/interactive-config-table}"
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
MIN_DISK_SPACE_MB=6000
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
readonly WIZ_TIMEZONES="Africa/Abidjan
Africa/Accra
Africa/Addis_Ababa
Africa/Algiers
Africa/Asmara
Africa/Bamako
Africa/Bangui
Africa/Banjul
Africa/Bissau
Africa/Blantyre
Africa/Brazzaville
Africa/Bujumbura
Africa/Cairo
Africa/Casablanca
Africa/Ceuta
Africa/Conakry
Africa/Dakar
Africa/Dar_es_Salaam
Africa/Djibouti
Africa/Douala
Africa/El_Aaiun
Africa/Freetown
Africa/Gaborone
Africa/Harare
Africa/Johannesburg
Africa/Juba
Africa/Kampala
Africa/Khartoum
Africa/Kigali
Africa/Kinshasa
Africa/Lagos
Africa/Libreville
Africa/Lome
Africa/Luanda
Africa/Lubumbashi
Africa/Lusaka
Africa/Malabo
Africa/Maputo
Africa/Maseru
Africa/Mbabane
Africa/Mogadishu
Africa/Monrovia
Africa/Nairobi
Africa/Ndjamena
Africa/Niamey
Africa/Nouakchott
Africa/Ouagadougou
Africa/Porto-Novo
Africa/Sao_Tome
Africa/Tripoli
Africa/Tunis
Africa/Windhoek
America/Adak
America/Anchorage
America/Anguilla
America/Antigua
America/Araguaina
America/Argentina/Buenos_Aires
America/Argentina/Catamarca
America/Argentina/Cordoba
America/Argentina/Jujuy
America/Argentina/La_Rioja
America/Argentina/Mendoza
America/Argentina/Rio_Gallegos
America/Argentina/Salta
America/Argentina/San_Juan
America/Argentina/San_Luis
America/Argentina/Tucuman
America/Argentina/Ushuaia
America/Aruba
America/Asuncion
America/Atikokan
America/Bahia
America/Bahia_Banderas
America/Barbados
America/Belem
America/Belize
America/Blanc-Sablon
America/Boa_Vista
America/Bogota
America/Boise
America/Cambridge_Bay
America/Campo_Grande
America/Cancun
America/Caracas
America/Cayenne
America/Cayman
America/Chicago
America/Chihuahua
America/Ciudad_Juarez
America/Costa_Rica
America/Creston
America/Cuiaba
America/Curacao
America/Danmarkshavn
America/Dawson
America/Dawson_Creek
America/Denver
America/Detroit
America/Dominica
America/Edmonton
America/Eirunepe
America/El_Salvador
America/Fort_Nelson
America/Fortaleza
America/Glace_Bay
America/Goose_Bay
America/Grand_Turk
America/Grenada
America/Guadeloupe
America/Guatemala
America/Guayaquil
America/Guyana
America/Halifax
America/Havana
America/Hermosillo
America/Indiana/Indianapolis
America/Indiana/Knox
America/Indiana/Marengo
America/Indiana/Petersburg
America/Indiana/Tell_City
America/Indiana/Vevay
America/Indiana/Vincennes
America/Indiana/Winamac
America/Inuvik
America/Iqaluit
America/Jamaica
America/Juneau
America/Kentucky/Louisville
America/Kentucky/Monticello
America/Kralendijk
America/La_Paz
America/Lima
America/Los_Angeles
America/Lower_Princes
America/Maceio
America/Managua
America/Manaus
America/Marigot
America/Martinique
America/Matamoros
America/Mazatlan
America/Menominee
America/Merida
America/Metlakatla
America/Mexico_City
America/Miquelon
America/Moncton
America/Monterrey
America/Montevideo
America/Montserrat
America/Nassau
America/New_York
America/Nome
America/Noronha
America/North_Dakota/Beulah
America/North_Dakota/Center
America/North_Dakota/New_Salem
America/Nuuk
America/Ojinaga
America/Panama
America/Paramaribo
America/Phoenix
America/Port-au-Prince
America/Port_of_Spain
America/Porto_Velho
America/Puerto_Rico
America/Punta_Arenas
America/Rankin_Inlet
America/Recife
America/Regina
America/Resolute
America/Rio_Branco
America/Santarem
America/Santiago
America/Santo_Domingo
America/Sao_Paulo
America/Scoresbysund
America/Sitka
America/St_Barthelemy
America/St_Johns
America/St_Kitts
America/St_Lucia
America/St_Thomas
America/St_Vincent
America/Swift_Current
America/Tegucigalpa
America/Thule
America/Tijuana
America/Toronto
America/Tortola
America/Vancouver
America/Whitehorse
America/Winnipeg
America/Yakutat
Antarctica/Casey
Antarctica/Davis
Antarctica/DumontDUrville
Antarctica/Macquarie
Antarctica/Mawson
Antarctica/McMurdo
Antarctica/Palmer
Antarctica/Rothera
Antarctica/Syowa
Antarctica/Troll
Antarctica/Vostok
Arctic/Longyearbyen
Asia/Aden
Asia/Almaty
Asia/Amman
Asia/Anadyr
Asia/Aqtau
Asia/Aqtobe
Asia/Ashgabat
Asia/Atyrau
Asia/Baghdad
Asia/Bahrain
Asia/Baku
Asia/Bangkok
Asia/Barnaul
Asia/Beirut
Asia/Bishkek
Asia/Brunei
Asia/Chita
Asia/Choibalsan
Asia/Colombo
Asia/Damascus
Asia/Dhaka
Asia/Dili
Asia/Dubai
Asia/Dushanbe
Asia/Famagusta
Asia/Gaza
Asia/Hebron
Asia/Ho_Chi_Minh
Asia/Hong_Kong
Asia/Hovd
Asia/Irkutsk
Asia/Istanbul
Asia/Jakarta
Asia/Jayapura
Asia/Jerusalem
Asia/Kabul
Asia/Kamchatka
Asia/Karachi
Asia/Kathmandu
Asia/Khandyga
Asia/Kolkata
Asia/Krasnoyarsk
Asia/Kuala_Lumpur
Asia/Kuching
Asia/Kuwait
Asia/Macau
Asia/Magadan
Asia/Makassar
Asia/Manila
Asia/Muscat
Asia/Nicosia
Asia/Novokuznetsk
Asia/Novosibirsk
Asia/Omsk
Asia/Oral
Asia/Phnom_Penh
Asia/Pontianak
Asia/Pyongyang
Asia/Qatar
Asia/Qostanay
Asia/Qyzylorda
Asia/Riyadh
Asia/Sakhalin
Asia/Samarkand
Asia/Seoul
Asia/Shanghai
Asia/Singapore
Asia/Srednekolymsk
Asia/Taipei
Asia/Tashkent
Asia/Tbilisi
Asia/Tehran
Asia/Thimphu
Asia/Tokyo
Asia/Tomsk
Asia/Ulaanbaatar
Asia/Urumqi
Asia/Ust-Nera
Asia/Vientiane
Asia/Vladivostok
Asia/Yakutsk
Asia/Yangon
Asia/Yekaterinburg
Asia/Yerevan
Atlantic/Azores
Atlantic/Bermuda
Atlantic/Canary
Atlantic/Cape_Verde
Atlantic/Faroe
Atlantic/Madeira
Atlantic/Reykjavik
Atlantic/South_Georgia
Atlantic/St_Helena
Atlantic/Stanley
Australia/Adelaide
Australia/Brisbane
Australia/Broken_Hill
Australia/Darwin
Australia/Eucla
Australia/Hobart
Australia/Lindeman
Australia/Lord_Howe
Australia/Melbourne
Australia/Perth
Australia/Sydney
Europe/Amsterdam
Europe/Andorra
Europe/Astrakhan
Europe/Athens
Europe/Belgrade
Europe/Berlin
Europe/Bratislava
Europe/Brussels
Europe/Bucharest
Europe/Budapest
Europe/Busingen
Europe/Chisinau
Europe/Copenhagen
Europe/Dublin
Europe/Gibraltar
Europe/Guernsey
Europe/Helsinki
Europe/Isle_of_Man
Europe/Istanbul
Europe/Jersey
Europe/Kaliningrad
Europe/Kirov
Europe/Kyiv
Europe/Lisbon
Europe/Ljubljana
Europe/London
Europe/Luxembourg
Europe/Madrid
Europe/Malta
Europe/Mariehamn
Europe/Minsk
Europe/Monaco
Europe/Moscow
Europe/Oslo
Europe/Paris
Europe/Podgorica
Europe/Prague
Europe/Riga
Europe/Rome
Europe/Samara
Europe/San_Marino
Europe/Sarajevo
Europe/Saratov
Europe/Simferopol
Europe/Skopje
Europe/Sofia
Europe/Stockholm
Europe/Tallinn
Europe/Tirane
Europe/Ulyanovsk
Europe/Vaduz
Europe/Vatican
Europe/Vienna
Europe/Vilnius
Europe/Volgograd
Europe/Warsaw
Europe/Zagreb
Europe/Zurich
Indian/Antananarivo
Indian/Chagos
Indian/Christmas
Indian/Cocos
Indian/Comoro
Indian/Kerguelen
Indian/Mahe
Indian/Maldives
Indian/Mauritius
Indian/Mayotte
Indian/Reunion
Pacific/Apia
Pacific/Auckland
Pacific/Bougainville
Pacific/Chatham
Pacific/Chuuk
Pacific/Easter
Pacific/Efate
Pacific/Fakaofo
Pacific/Fiji
Pacific/Funafuti
Pacific/Galapagos
Pacific/Gambier
Pacific/Guadalcanal
Pacific/Guam
Pacific/Honolulu
Pacific/Kanton
Pacific/Kiritimati
Pacific/Kosrae
Pacific/Kwajalein
Pacific/Majuro
Pacific/Marquesas
Pacific/Midway
Pacific/Nauru
Pacific/Niue
Pacific/Norfolk
Pacific/Noumea
Pacific/Pago_Pago
Pacific/Palau
Pacific/Pitcairn
Pacific/Pohnpei
Pacific/Port_Moresby
Pacific/Rarotonga
Pacific/Saipan
Pacific/Tahiti
Pacific/Tarawa
Pacific/Tongatapu
Pacific/Wake
Pacific/Wallis
UTC"
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
readonly WIZ_COUNTRIES="ad
ae
af
ag
ai
al
am
ao
aq
ar
as
at
au
aw
ax
az
ba
bb
bd
be
bf
bg
bh
bi
bj
bl
bm
bn
bo
bq
br
bs
bt
bv
bw
by
bz
ca
cc
cd
cf
cg
ch
ci
ck
cl
cm
cn
co
cr
cu
cv
cw
cx
cy
cz
de
dj
dk
dm
do
dz
ec
ee
eg
eh
er
es
et
fi
fj
fk
fm
fo
fr
ga
gb
gd
ge
gf
gg
gh
gi
gl
gm
gn
gp
gq
gr
gs
gt
gu
gw
gy
hk
hm
hn
hr
ht
hu
id
ie
il
im
in
io
iq
ir
is
it
je
jm
jo
jp
ke
kg
kh
ki
km
kn
kp
kr
kw
ky
kz
la
lb
lc
li
lk
lr
ls
lt
lu
lv
ly
ma
mc
md
me
mf
mg
mh
mk
ml
mm
mn
mo
mp
mq
mr
ms
mt
mu
mv
mw
mx
my
mz
na
nc
ne
nf
ng
ni
nl
no
np
nr
nu
nz
om
pa
pe
pf
pg
ph
pk
pl
pm
pn
pr
ps
pt
pw
py
qa
re
ro
rs
ru
rw
sa
sb
sc
sd
se
sg
sh
si
sj
sk
sl
sm
sn
so
sr
ss
st
sv
sx
sy
sz
tc
td
tf
tg
th
tj
tk
tl
tm
tn
to
tr
tt
tv
tw
tz
ua
ug
um
us
uy
uz
va
vc
ve
vg
vi
vn
vu
wf
ws
ye
yt
za
zm
zw"
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
readonly WIZ_CPU_GOVERNORS="Performance
Balanced
Power saving
Adaptive
Conservative"
readonly WIZ_OPTIONAL_FEATURES="vnstat (network stats)
apparmor (mandatory access control)
auditd (audit logging)
prometheus (metrics exporter)
yazi (file manager)
nvim (text editor)"
BOOT_DISK=""
ZFS_POOL_DISKS=()
SYSTEM_UTILITIES="btop iotop ncdu tmux pigz smartmontools jq bat fastfetch aide chkrootkit sysstat nethogs ethtool"
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
FAIL2BAN_INSTALLED=""
INSTALL_AUDITD=""
INSTALL_APPARMOR=""
CPU_GOVERNOR=""
ZFS_ARC_MODE=""
AUDITD_INSTALLED=""
APPARMOR_INSTALLED=""
INSTALL_VNSTAT=""
VNSTAT_INSTALLED=""
INSTALL_PROMETHEUS=""
PROMETHEUS_INSTALLED=""
INSTALL_YAZI=""
YAZI_INSTALLED=""
INSTALL_NVIM=""
NVIM_INSTALLED=""
INSTALL_UNATTENDED_UPGRADES=""
INSTALL_TAILSCALE=""
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH=""
TAILSCALE_WEBUI=""
TAILSCALE_DISABLE_SSH=""
STEALTH_MODE=""
BRIDGE_MTU=""
INSTALL_API_TOKEN=""
API_TOKEN_NAME="automation"
API_TOKEN_VALUE=""
API_TOKEN_ID=""
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
show_banner(){
printf '%s\n' \
"$CLR_GRAY _____                                             $CLR_RESET" \
"$CLR_GRAY|  __ \\                                            $CLR_RESET" \
"$CLR_GRAY| |__) | _ __   ___  ${CLR_ORANGE}__  __$CLR_GRAY  _ __ ___    ___  ${CLR_ORANGE}__  __$CLR_RESET" \
"$CLR_GRAY|  ___/ | '__| / _ \\ $CLR_ORANGE\\ \\/ /$CLR_GRAY | '_ \` _ \\  / _ \\ $CLR_ORANGE\\ \\/ /$CLR_RESET" \
"$CLR_GRAY| |     | |   | (_) |$CLR_ORANGE >  <$CLR_GRAY  | | | | | || (_) |$CLR_ORANGE >  <$CLR_RESET" \
"$CLR_GRAY|_|     |_|    \\___/ $CLR_ORANGE/_/\\_\\$CLR_GRAY |_| |_| |_| \\___/ $CLR_ORANGE/_/\\_\\$CLR_RESET" \
"" \
"$CLR_HETZNER            Hetzner ${CLR_GRAY}Automated Installer$CLR_RESET"
}
_show_banner_frame(){
local h="${1:--1}"
local M="$CLR_GRAY"
local A="$CLR_ORANGE"
local R="$CLR_RESET"
local line1="$M "
[[ $h -eq 0 ]]&&line1+="${A}_____$M"||line1+="_____"
line1+="                                             $R"
local line2="$M"
[[ $h -eq 0 ]]&&line2+="$A|  __ \\$M"||line2+='|  __ \'
line2+="                                            $R"
local line3="$M"
[[ $h -eq 0 ]]&&line3+="$A| |__) |$M"||line3+="| |__) |"
[[ $h -eq 1 ]]&&line3+=" ${A}_ __$M"||line3+=" _ __"
[[ $h -eq 2 ]]&&line3+="   ${A}___$M"||line3+="   ___"
[[ $h -eq 3 ]]&&line3+="  ${A}__  __$M"||line3+="  __  __"
[[ $h -eq 4 ]]&&line3+="  ${A}_ __ ___$M"||line3+="  _ __ ___"
[[ $h -eq 5 ]]&&line3+="    ${A}___$M"||line3+="    ___"
[[ $h -eq 6 ]]&&line3+="  ${A}__  __$M"||line3+="  __  __"
line3+="$R"
local line4="$M"
[[ $h -eq 0 ]]&&line4+="$A|  ___/ $M"||line4+="|  ___/ "
[[ $h -eq 1 ]]&&line4+="$A| '__|$M"||line4+="| '__|"
[[ $h -eq 2 ]]&&line4+=" $A/ _ \\$M"||line4+=' / _ \'
[[ $h -eq 3 ]]&&line4+=" $A\\ \\/ /$M"||line4+=' \ \/ /'
[[ $h -eq 4 ]]&&line4+=" $A| '_ \` _ \\$M"||line4+=" | '_ \` _ \\"
[[ $h -eq 5 ]]&&line4+="  $A/ _ \\$M"||line4+='  / _ \'
[[ $h -eq 6 ]]&&line4+=" $A\\ \\/ /$M"||line4+=' \ \/ /'
line4+="$R"
local line5="$M"
[[ $h -eq 0 ]]&&line5+="$A| |     $M"||line5+="| |     "
[[ $h -eq 1 ]]&&line5+="$A| |$M"||line5+="| |"
[[ $h -eq 2 ]]&&line5+="   $A| (_) |$M"||line5+="   | (_) |"
[[ $h -eq 3 ]]&&line5+="$A >  <$M"||line5+=" >  <"
[[ $h -eq 4 ]]&&line5+="  $A| | | | | |$M"||line5+="  | | | | | |"
[[ $h -eq 5 ]]&&line5+="$A| (_) |$M"||line5+="| (_) |"
[[ $h -eq 6 ]]&&line5+="$A >  <$M"||line5+=" >  <"
line5+="$R"
local line6="$M"
[[ $h -eq 0 ]]&&line6+="$A|_|     $M"||line6+="|_|     "
[[ $h -eq 1 ]]&&line6+="$A|_|$M"||line6+="|_|"
[[ $h -eq 2 ]]&&line6+="    $A\\___/$M"||line6+='    \___/'
[[ $h -eq 3 ]]&&line6+=" $A/_/\\_\\$M"||line6+=' /_/\_\'
[[ $h -eq 4 ]]&&line6+=" $A|_| |_| |_|$M"||line6+=" |_| |_| |_|"
[[ $h -eq 5 ]]&&line6+=" $A\\___/$M"||line6+=' \___/'
[[ $h -eq 6 ]]&&line6+=" $A/_/\\_\\$M"||line6+=' /_/\_\'
line6+="$R"
local line_hetzner="$CLR_HETZNER            Hetzner ${M}Automated Installer$R"
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
"DNS_TERTIARY=${DNS_TERTIARY:-8.8.8.8}" \
"DNS_QUATERNARY=${DNS_QUATERNARY:-8.8.4.4}" \
"DNS6_PRIMARY=${DNS6_PRIMARY:-2606:4700:4700::1111}" \
"DNS6_SECONDARY=${DNS6_SECONDARY:-2606:4700:4700::1001}"
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
get_rescue_ssh_key(){
if [[ -f /root/.ssh/authorized_keys ]];then
grep -E "^ssh-(rsa|ed25519|ecdsa)" /root/.ssh/authorized_keys 2>/dev/null|head -1
fi
}
retry_command(){
local max_retries="${1:-3}"
local delay="${2:-2}"
shift 2
local retry_count=0
while [ "$retry_count" -lt "$max_retries" ];do
if "$@";then
return 0
fi
retry_count=$((retry_count+1))
if [ "$retry_count" -lt "$max_retries" ];then
log "Retry $retry_count/$max_retries after ${delay}s delay"
sleep "$delay"
delay=$((delay*2))
fi
done
log "ERROR: Command failed after $max_retries attempts"
return 1
}
run_with_progress(){
local message="$1"
local done_message="$2"
shift 2
"$@" >>"$LOG_FILE" 2>&1&
local pid=$!
show_progress "$pid" "$message" "$done_message"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: $message failed with exit code $exit_code"
return 1
fi
return 0
}
run_parallel(){
local -a pids=()
local exit_code=0
for cmd in "$@";do
eval "$cmd"&
pids+=($!)
done
for pid in "${pids[@]}";do
if ! wait "$pid";then
exit_code=1
fi
done
return $exit_code
}
install_optional_feature(){
local feature_name="$1"
local install_var="$2"
local install_func="$3"
local config_func="$4"
local installed_var="${5:-}"
if [[ ${!install_var} != "yes" ]];then
log "Skipping $feature_name (not requested)"
return 0
fi
if ! "$install_func";then
log "ERROR: $feature_name installation failed"
print_error "$feature_name installation failed"
exit 1
fi
if ! "$config_func";then
log "WARNING: $feature_name configuration failed"
print_warning "$feature_name configuration failed - continuing without it"
return 0
fi
if [[ -n $installed_var ]];then
eval "$installed_var=yes"
log "$feature_name installed and configured successfully"
fi
return 0
}
deploy_template(){
local template_name="$1"
local dest_path="$2"
shift 2
local -a vars=("$@")
local local_template="./templates/$template_name"
if ! download_template "$local_template";then
log "ERROR: Failed to download template: $template_name"
return 1
fi
if [[ ${#vars[@]} -gt 0 ]];then
if ! apply_template_vars "$local_template" "${vars[@]}";then
log "ERROR: Failed to apply variables to template: $template_name"
return 1
fi
else
if ! apply_common_template_vars "$local_template";then
log "ERROR: Failed to apply common variables to template: $template_name"
return 1
fi
fi
if ! validate_template_vars "$local_template";then
log "ERROR: Template has unfilled variables: $template_name"
return 1
fi
if ! remote_copy "$local_template" "$dest_path";then
log "ERROR: Failed to copy template to remote: $template_name → $dest_path"
return 1
fi
log "Template deployed successfully: $template_name → $dest_path"
return 0
}
deploy_templates(){
local -a cmds=()
while [[ $# -gt 0 ]];do
local template="$1"
local dest="$2"
shift 2
cmds+=("deploy_template '$template' '$dest'")
done
run_parallel "${cmds[@]}"
}
remote_apt_install(){
local packages="$*"
if [[ -z $packages ]];then
log "ERROR: No packages specified for installation"
return 1
fi
run_remote "Installing packages: $packages" "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || exit 1
    apt-get install -yqq $packages || exit 1
  " "Packages installed: $packages"
}
remote_exec_retry(){
local max_retries="${1:-3}"
local message="$2"
local command="$3"
local done_message="${4:-$message}"
retry_command "$max_retries" 2 remote_exec "$message" "$command" "$done_message"
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
validate_zfs_raid_disk_count(){
local raid_type="$1"
local disk_count="$2"
case "$raid_type" in
single)if
[[ $disk_count -ne 1 ]]
then
log "WARNING: Single disk RAID expects 1 disk, have $disk_count"
return 2
fi
;;
raid0)
;;
raid1)if
[[ $disk_count -lt 2 ]]
then
log "ERROR: RAID1 requires at least 2 disks, have $disk_count"
return 1
fi
;;
raidz1)if
[[ $disk_count -lt 3 ]]
then
log "WARNING: RAIDZ1 recommended for 3+ disks, have $disk_count"
return 2
fi
;;
raidz2)if
[[ $disk_count -lt 4 ]]
then
log "WARNING: RAIDZ2 recommended for 4+ disks, have $disk_count"
return 2
fi
;;
raidz3)if
[[ $disk_count -lt 5 ]]
then
log "WARNING: RAIDZ3 recommended for 5+ disks, have $disk_count"
return 2
fi
;;
raid10)if
[[ $disk_count -lt 4 ]]||[[ $((disk_count%2)) -ne 0 ]]
then
log "ERROR: RAID10 requires even number of disks (min 4), have $disk_count"
return 1
fi
;;
*)log "ERROR: Unknown RAID type: $raid_type"
return 1
esac
return 0
}
create_virtio_mapping(){
declare -A VIRTIO_MAP
local virtio_idx=0
local vdev_letters=(a b c d e f g h i j k l m n o p q r s t u v w x y z)
if [[ -n $BOOT_DISK ]];then
local vdev="vd${vdev_letters[$virtio_idx]}"
VIRTIO_MAP["$BOOT_DISK"]="$vdev"
log "Virtio mapping: $BOOT_DISK → /dev/$vdev (boot)"
((virtio_idx++))
fi
for drive in "${ZFS_POOL_DISKS[@]}";do
local vdev="vd${vdev_letters[$virtio_idx]}"
VIRTIO_MAP["$drive"]="$vdev"
log "Virtio mapping: $drive → /dev/$vdev (pool)"
((virtio_idx++))
done
declare -p VIRTIO_MAP >/tmp/virtio_map.env
log "Virtio mapping saved to /tmp/virtio_map.env"
}
load_virtio_mapping(){
declare -g -A VIRTIO_MAP
if [[ ! -f /tmp/virtio_map.env ]];then
create_virtio_mapping
fi
if [[ -f /tmp/virtio_map.env ]];then
source /tmp/virtio_map.env
return 0
else
log "ERROR: Failed to create virtio mapping"
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
validate_with_error(){
local validator="$1"
local value="$2"
local error_message="$3"
if ! "$validator" "$value";then
show_validation_error "$error_message"
return 1
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
collect_system_info(){
local errors=0
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
LOGO_HEIGHT=9
calculate_log_area(){
get_terminal_dimensions
LOG_AREA_HEIGHT=$((TERM_HEIGHT-LOGO_HEIGHT-2))
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
add_log "  $CLR_GRAY│$CLR_RESET   $CLR_GRAY$message$CLR_RESET"
}
start_live_installation(){
if ! command -v gum &>/dev/null;then
log "WARNING: gum is not installed, live logs disabled"
return 1
fi
LIVE_LOGS_ACTIVE=true
if type show_progress &>/dev/null 2>&1;then
eval "$(declare -f show_progress|sed '1s/show_progress/show_progress_original/')"
fi
show_progress(){
live_show_progress "$@"
}
export -f show_progress 2>/dev/null||true
calculate_log_area
tput smcup
_wiz_clear
show_banner
save_cursor_position
tput civis
add_log ""
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
live_log_section(){
local section_name="$1"
local first="${2:-}"
[[ $first != "first" ]]&&add_log ""
add_log "$CLR_CYAN▼ $section_name$CLR_RESET"
}
live_log_system_preparation(){
live_log_section "Rescue System Preparation" "first"
}
live_log_iso_download(){
live_log_section "Proxmox ISO Download"
}
live_log_autoinstall_preparation(){
live_log_section "Autoinstall Preparation"
}
live_log_proxmox_installation(){
live_log_section "Proxmox Installation"
}
live_log_system_configuration(){
live_log_section "System Configuration"
}
live_log_security_configuration(){
if [[ ${INSTALL_TAILSCALE:-} == "yes" ]]||[[ ${INSTALL_APPARMOR:-} == "yes" ]]||[[ ${FAIL2BAN_INSTALLED:-} == "yes" ]]||[[ ${INSTALL_AUDITD:-} == "yes" ]];then
add_log ""
add_log "$CLR_CYAN▼ Security Configuration$CLR_RESET"
fi
}
live_log_ssl_configuration(){
if [[ ${SSL_TYPE:-} == "letsencrypt" ]];then
add_log ""
add_log "$CLR_CYAN▼ SSL Configuration$CLR_RESET"
fi
}
live_log_validation_finalization(){
live_log_section "Validation & Finalization"
}
live_log_installation_complete(){
add_log ""
add_log "$CLR_CYAN━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$CLR_RESET"
add_log "$CLR_CYAN✓ Installation completed successfully!$CLR_RESET"
add_log "$CLR_CYAN━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$CLR_RESET"
add_log ""
}
LIVE_LOGS_ACTIVE=false
live_show_progress(){
local pid=$1
local message="${2:-Processing}"
local done_message="${3:-$message}"
local silent=false
[[ ${3:-} == "--silent" || ${4:-} == "--silent" ]]&&silent=true
[[ ${3:-} == "--silent" ]]&&done_message="$message"
start_task "  $CLR_GRAY├─$CLR_RESET $message"
local task_idx=$TASK_INDEX
while kill -0 "$pid" 2>/dev/null;do
sleep 0.3
local dots_count=$((($(date +%s)%3)+1))
local dots
dots=$(printf '.%.0s' $(seq 1 $dots_count))
LOG_LINES[task_idx]="  $CLR_GRAY├─$CLR_RESET $message$CLR_ORANGE$dots$CLR_RESET"
render_logs
done
wait "$pid" 2>/dev/null
local exit_code=$?
if [[ $exit_code -eq 0 ]];then
if [[ $silent != true ]];then
complete_task "$task_idx" "  $CLR_GRAY├─$CLR_RESET $done_message"
else
unset 'LOG_LINES[task_idx]'
LOG_LINES=("${LOG_LINES[@]}")
((LOG_COUNT--))
render_logs
fi
else
LOG_LINES[task_idx]="  $CLR_GRAY├─$CLR_RESET $message $CLR_RED✗$CLR_RESET"
render_logs
fi
return $exit_code
}
live_log_task_complete(){
local message="$1"
add_log "  $CLR_GRAY├─$CLR_RESET $message $CLR_CYAN✓$CLR_RESET"
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
boot_disk)_edit_boot_disk;;
pool_disks)_edit_pool_disks;;
zfs_mode)_edit_zfs_mode;;
zfs_arc)_edit_zfs_arc;;
tailscale)_edit_tailscale;;
ssl)_edit_ssl;;
shell)_edit_shell;;
power_profile)_edit_power_profile;;
features)_edit_features;;
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
local missing_fields=()
local missing_count=0
[[ -z $PVE_HOSTNAME ]]&&missing_fields+=("Hostname")&&((missing_count++))
[[ -z $DOMAIN_SUFFIX ]]&&missing_fields+=("Domain")&&((missing_count++))
[[ -z $EMAIL ]]&&missing_fields+=("Email")&&((missing_count++))
[[ -z $NEW_ROOT_PASSWORD ]]&&missing_fields+=("Password")&&((missing_count++))
[[ -z $TIMEZONE ]]&&missing_fields+=("Timezone")&&((missing_count++))
[[ -z $KEYBOARD ]]&&missing_fields+=("Keyboard")&&((missing_count++))
[[ -z $COUNTRY ]]&&missing_fields+=("Country")&&((missing_count++))
[[ -z $PROXMOX_ISO_VERSION ]]&&missing_fields+=("Proxmox Version")&&((missing_count++))
[[ -z $PVE_REPO_TYPE ]]&&missing_fields+=("Repository")&&((missing_count++))
[[ -z $INTERFACE_NAME ]]&&missing_fields+=("Network Interface")&&((missing_count++))
[[ -z $BRIDGE_MODE ]]&&missing_fields+=("Bridge mode")&&((missing_count++))
[[ -z $PRIVATE_SUBNET ]]&&missing_fields+=("Private subnet")&&((missing_count++))
[[ -z $IPV6_MODE ]]&&missing_fields+=("IPv6")&&((missing_count++))
[[ -z $ZFS_RAID ]]&&missing_fields+=("ZFS mode")&&((missing_count++))
[[ -z $ZFS_ARC_MODE ]]&&missing_fields+=("ZFS ARC")&&((missing_count++))
[[ -z $SHELL_TYPE ]]&&missing_fields+=("Shell")&&((missing_count++))
[[ -z $CPU_GOVERNOR ]]&&missing_fields+=("Power profile")&&((missing_count++))
[[ -z $SSH_PUBLIC_KEY ]]&&missing_fields+=("SSH Key")&&((missing_count++))
[[ ${#ZFS_POOL_DISKS[@]} -eq 0 ]]&&missing_fields+=("Pool disks")&&((missing_count++))
if [[ $INSTALL_TAILSCALE != "yes" ]];then
[[ -z $SSL_TYPE ]]&&missing_fields+=("SSL Certificate")&&((missing_count++))
fi
if [[ $missing_count -gt 0 ]];then
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
_wiz_render_menu(){
local selection="$1"
local output=""
local banner_output
banner_output=$(show_banner)
output="\n$banner_output\n\n"
local pass_display=""
if [[ -n $NEW_ROOT_PASSWORD ]];then
pass_display="********"
fi
local ipv6_display=""
if [[ -n $IPV6_MODE ]];then
case "$IPV6_MODE" in
auto)ipv6_display="Auto"
if [[ -n $MAIN_IPV6 ]];then
ipv6_display+=" ($MAIN_IPV6)"
fi
;;
manual)ipv6_display="Manual"
if [[ -n $MAIN_IPV6 ]];then
ipv6_display+=" ($MAIN_IPV6, gw: $IPV6_GATEWAY)"
fi
;;
disabled)ipv6_display="Disabled";;
*)ipv6_display="$IPV6_MODE"
esac
fi
local tailscale_display=""
if [[ -n $INSTALL_TAILSCALE ]];then
if [[ $INSTALL_TAILSCALE == "yes" ]];then
tailscale_display="Enabled + Stealth"
else
tailscale_display="Disabled"
fi
fi
local ssl_display=""
if [[ -n $SSL_TYPE ]];then
case "$SSL_TYPE" in
self-signed)ssl_display="Self-signed";;
letsencrypt)ssl_display="Let's Encrypt";;
*)ssl_display="$SSL_TYPE"
esac
fi
local repo_display=""
if [[ -n $PVE_REPO_TYPE ]];then
case "$PVE_REPO_TYPE" in
no-subscription)repo_display="No-subscription (free)";;
enterprise)repo_display="Enterprise";;
test)repo_display="Test/Development";;
*)repo_display="$PVE_REPO_TYPE"
esac
fi
local bridge_display=""
if [[ -n $BRIDGE_MODE ]];then
case "$BRIDGE_MODE" in
external)bridge_display="External bridge";;
internal)bridge_display="Internal NAT";;
both)bridge_display="Both";;
*)bridge_display="$BRIDGE_MODE"
esac
fi
local zfs_display=""
if [[ -n $ZFS_RAID ]];then
case "$ZFS_RAID" in
single)zfs_display="Single disk";;
raid0)zfs_display="RAID-0 (striped)";;
raid1)zfs_display="RAID-1 (mirror)";;
raidz1)zfs_display="RAID-Z1 (parity)";;
raidz2)zfs_display="RAID-Z2 (double parity)";;
raid5)zfs_display="RAID-5 (parity)";;
raid10)zfs_display="RAID-10 (striped mirrors)";;
*)zfs_display="$ZFS_RAID"
esac
fi
local zfs_arc_display=""
if [[ -n $ZFS_ARC_MODE ]];then
case "$ZFS_ARC_MODE" in
vm-focused)zfs_arc_display="VM-focused (4GB)";;
balanced)zfs_arc_display="Balanced (25-40%)";;
storage-focused)zfs_arc_display="Storage-focused (50%)";;
*)zfs_arc_display="$ZFS_ARC_MODE"
esac
fi
local shell_display=""
if [[ -n $SHELL_TYPE ]];then
case "$SHELL_TYPE" in
zsh)shell_display="ZSH";;
bash)shell_display="Bash";;
*)shell_display="$SHELL_TYPE"
esac
fi
local power_display=""
if [[ -n $CPU_GOVERNOR ]];then
case "$CPU_GOVERNOR" in
performance)power_display="Performance";;
ondemand)power_display="Balanced";;
powersave)power_display="Power saving";;
schedutil)power_display="Adaptive";;
conservative)power_display="Conservative";;
*)power_display="$CPU_GOVERNOR"
esac
fi
local features_display="none"
if [[ -n $INSTALL_VNSTAT || -n $INSTALL_APPARMOR || -n $INSTALL_AUDITD || -n $INSTALL_PROMETHEUS || -n $INSTALL_YAZI || -n $INSTALL_NVIM ]];then
features_display=""
[[ $INSTALL_VNSTAT == "yes" ]]&&features_display+="vnstat"
[[ $INSTALL_APPARMOR == "yes" ]]&&features_display+="${features_display:+, }apparmor"
[[ $INSTALL_AUDITD == "yes" ]]&&features_display+="${features_display:+, }auditd"
[[ $INSTALL_PROMETHEUS == "yes" ]]&&features_display+="${features_display:+, }prometheus"
[[ $INSTALL_YAZI == "yes" ]]&&features_display+="${features_display:+, }yazi"
[[ $INSTALL_NVIM == "yes" ]]&&features_display+="${features_display:+, }nvim"
[[ -z $features_display ]]&&features_display="none"
fi
local api_token_display=""
if [[ -n $INSTALL_API_TOKEN ]];then
case "$INSTALL_API_TOKEN" in
yes)api_token_display="Yes ($API_TOKEN_NAME)";;
no)api_token_display="No";;
*)api_token_display=""
esac
fi
local ssh_display=""
if [[ -n $SSH_PUBLIC_KEY ]];then
ssh_display="${SSH_PUBLIC_KEY:0:20}..."
fi
local iso_version_display=""
if [[ -n $PROXMOX_ISO_VERSION ]];then
iso_version_display=$(get_iso_version "$PROXMOX_ISO_VERSION")
fi
local hostname_display=""
if [[ -n $PVE_HOSTNAME && -n $DOMAIN_SUFFIX ]];then
hostname_display="$PVE_HOSTNAME.$DOMAIN_SUFFIX"
fi
_WIZ_FIELD_MAP=()
local field_idx=0
_add_section(){
output+="$CLR_CYAN--- $1 ---$CLR_RESET\n"
}
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
_add_section "Basic Settings"
_add_field "Hostname         " "$(_wiz_fmt "$hostname_display")" "hostname"
_add_field "Email            " "$(_wiz_fmt "$EMAIL")" "email"
_add_field "Password         " "$(_wiz_fmt "$pass_display")" "password"
_add_field "Timezone         " "$(_wiz_fmt "$TIMEZONE")" "timezone"
_add_field "Keyboard         " "$(_wiz_fmt "$KEYBOARD")" "keyboard"
_add_field "Country          " "$(_wiz_fmt "$COUNTRY")" "country"
_add_section "Proxmox"
_add_field "Version          " "$(_wiz_fmt "$iso_version_display")" "iso_version"
_add_field "Repository       " "$(_wiz_fmt "$repo_display")" "repository"
_add_section "Network"
if [[ ${INTERFACE_COUNT:-1} -gt 1 ]];then
_add_field "Interface        " "$(_wiz_fmt "$INTERFACE_NAME")" "interface"
fi
_add_field "Bridge mode      " "$(_wiz_fmt "$bridge_display")" "bridge_mode"
if [[ $BRIDGE_MODE == "internal" ]]||[[ $BRIDGE_MODE == "both" ]];then
_add_field "Private subnet   " "$(_wiz_fmt "$PRIVATE_SUBNET")" "private_subnet"
local mtu_display="${BRIDGE_MTU:-9000}"
[[ $mtu_display == "9000" ]]&&mtu_display="9000 (jumbo)"
_add_field "Bridge MTU       " "$(_wiz_fmt "$mtu_display")" "bridge_mtu"
fi
_add_field "IPv6             " "$(_wiz_fmt "$ipv6_display")" "ipv6"
_add_section "Storage"
if [[ $DRIVE_COUNT -gt 1 ]];then
local boot_display="All in pool"
if [[ -n $BOOT_DISK ]];then
for i in "${!DRIVES[@]}";do
if [[ ${DRIVES[$i]} == "$BOOT_DISK" ]];then
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
_add_section "VPN"
_add_field "Tailscale        " "$(_wiz_fmt "$tailscale_display")" "tailscale"
if [[ $INSTALL_TAILSCALE != "yes" ]];then
_add_section "SSL"
_add_field "Certificate      " "$(_wiz_fmt "$ssl_display")" "ssl"
fi
_add_section "Optional"
_add_field "Shell            " "$(_wiz_fmt "$shell_display")" "shell"
_add_field "Power profile    " "$(_wiz_fmt "$power_display")" "power_profile"
_add_field "Features         " "$(_wiz_fmt "$features_display")" "features"
_add_field "API Token        " "$(_wiz_fmt "$api_token_display")" "api_token"
_add_section "SSH"
_add_field "SSH Key          " "$(_wiz_fmt "$ssh_display")" "ssh_key"
_WIZ_FIELD_COUNT=$field_idx
output+="\n"
output+="$CLR_GRAY[$CLR_ORANGE↑↓$CLR_GRAY] navigate  [${CLR_ORANGE}Enter$CLR_GRAY] edit  [${CLR_ORANGE}S$CLR_GRAY] start  [${CLR_ORANGE}Q$CLR_GRAY] quit$CLR_RESET"
_wiz_clear
printf '%b' "$output"
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
Enabled)_wiz_input_screen "Enter Tailscale authentication key"
local auth_key
auth_key=$(_wiz_input \
--placeholder "tskey-auth-..." \
--prompt "Auth Key: ")
if [[ -n $auth_key ]];then
INSTALL_TAILSCALE="yes"
TAILSCALE_AUTH_KEY="$auth_key"
TAILSCALE_SSH="yes"
TAILSCALE_WEBUI="yes"
TAILSCALE_DISABLE_SSH="yes"
STEALTH_MODE="yes"
SSL_TYPE="self-signed"
else
INSTALL_TAILSCALE="no"
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH=""
TAILSCALE_WEBUI=""
TAILSCALE_DISABLE_SSH=""
STEALTH_MODE=""
SSL_TYPE=""
fi
;;
Disabled)INSTALL_TAILSCALE="no"
TAILSCALE_AUTH_KEY=""
TAILSCALE_SSH=""
TAILSCALE_WEBUI=""
TAILSCALE_DISABLE_SSH=""
STEALTH_MODE=""
SSL_TYPE=""
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
_wiz_description \
"CPU frequency scaling governor:" \
"" \
"  {{cyan:Performance}}:  Max frequency always (highest power)" \
"  {{cyan:Balanced}}:     Scale based on load (ondemand)" \
"  {{cyan:Adaptive}}:     Kernel-managed scaling (schedutil)" \
"  {{cyan:Power saving}}: Prefer low frequency (powersave)" \
"  {{cyan:Conservative}}: Gradual frequency changes" \
""
_show_input_footer "filter" 6
local selected
selected=$(echo "$WIZ_CPU_GOVERNORS"|_wiz_choose \
--header="Power profile:")
if [[ -n $selected ]];then
case "$selected" in
"Performance")CPU_GOVERNOR="performance";;
"Balanced")CPU_GOVERNOR="ondemand";;
"Power saving")CPU_GOVERNOR="powersave";;
"Adaptive")CPU_GOVERNOR="schedutil";;
"Conservative")CPU_GOVERNOR="conservative"
esac
fi
}
_edit_features(){
_wiz_start_edit
_wiz_description \
"Optional features (use Space to toggle):" \
"" \
"  {{cyan:vnstat}}:     Network traffic monitoring" \
"  {{cyan:apparmor}}:   Mandatory access control (MAC)" \
"  {{cyan:auditd}}:     Security audit logging" \
"  {{cyan:prometheus}}: Node exporter for metrics (port 9100)" \
"  {{cyan:yazi}}:       Terminal file manager" \
"  {{cyan:nvim}}:       Neovim as default editor" \
""
_show_input_footer "checkbox" 7
local preselected=()
[[ $INSTALL_VNSTAT == "yes" ]]&&preselected+=("vnstat")
[[ $INSTALL_APPARMOR == "yes" ]]&&preselected+=("apparmor")
[[ $INSTALL_AUDITD == "yes" ]]&&preselected+=("auditd")
[[ $INSTALL_PROMETHEUS == "yes" ]]&&preselected+=("prometheus")
[[ $INSTALL_YAZI == "yes" ]]&&preselected+=("yazi")
[[ $INSTALL_NVIM == "yes" ]]&&preselected+=("nvim")
local selected
local gum_args=(
--no-limit
--header="Features:"
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
selected=$(echo "$WIZ_OPTIONAL_FEATURES"|_wiz_choose "${gum_args[@]}")
INSTALL_VNSTAT="no"
INSTALL_APPARMOR="no"
INSTALL_AUDITD="no"
INSTALL_PROMETHEUS="no"
INSTALL_YAZI="no"
INSTALL_NVIM="no"
if echo "$selected"|grep -q "vnstat";then
INSTALL_VNSTAT="yes"
fi
if echo "$selected"|grep -q "apparmor";then
INSTALL_APPARMOR="yes"
fi
if echo "$selected"|grep -q "auditd";then
INSTALL_AUDITD="yes"
fi
if echo "$selected"|grep -q "prometheus";then
INSTALL_PROMETHEUS="yes"
fi
if echo "$selected"|grep -q "yazi";then
INSTALL_YAZI="yes"
fi
if echo "$selected"|grep -q "nvim";then
INSTALL_NVIM="yes"
fi
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
_download_iso_parallel(){
local url="$1"
local output="$2"
local checksum="$3"
local temp_dir
temp_dir=$(mktemp -d)
local pids=()
local methods=()
log "Starting parallel download race"
_cleanup_parallel_download(){
for pid in "${pids[@]}";do
kill "$pid" 2>/dev/null||true
wait "$pid" 2>/dev/null||true
done
rm -rf "$temp_dir"
rm -f "$output.aria2" "$output.curl" "$output.wget" 2>/dev/null
}
if command -v aria2c &>/dev/null;then
(_download_iso_aria2c "$url" "$temp_dir/iso.aria2" "$checksum"&&mv "$temp_dir/iso.aria2" "$temp_dir/done.aria2") \
&
pids+=($!)
methods+=("aria2c")
log "Started aria2c downloader (PID: $!)"
fi
(_download_iso_curl "$url" "$temp_dir/iso.curl"&&mv "$temp_dir/iso.curl" "$temp_dir/done.curl") \
&
pids+=($!)
methods+=("curl")
log "Started curl downloader (PID: $!)"
if command -v wget &>/dev/null;then
(_download_iso_wget "$url" "$temp_dir/iso.wget"&&mv "$temp_dir/iso.wget" "$temp_dir/done.wget") \
&
pids+=($!)
methods+=("wget")
log "Started wget downloader (PID: $!)"
fi
while true;do
for ext in aria2 curl wget;do
if [[ -f "$temp_dir/done.$ext" ]]&&[[ -s "$temp_dir/done.$ext" ]];then
log "Download completed by $ext"
mv "$temp_dir/done.$ext" "$output"
case "$ext" in
aria2)DOWNLOAD_METHOD="aria2c";;
*)DOWNLOAD_METHOD="$ext"
esac
_cleanup_parallel_download
return 0
fi
done
local all_dead=true
for pid in "${pids[@]}";do
if kill -0 "$pid" 2>/dev/null;then
all_dead=false
break
fi
done
if $all_dead;then
log "All download methods failed"
_cleanup_parallel_download
return 1
fi
sleep 1
done
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
log "Downloading ISO: $ISO_FILENAME (parallel mode)"
DOWNLOAD_METHOD=""
_download_iso_parallel "$PROXMOX_ISO_URL" "pve.iso" "$expected_checksum"&
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
sha256sum pve.iso|awk '{print $1}' >/dev/null&
if type show_progress &>/dev/null 2>&1;then
show_progress $! "Verifying checksum" "Checksum verified"
else
wait $!
fi
local actual_checksum
actual_checksum=$(sha256sum pve.iso|awk '{print $1}')
if [[ $actual_checksum != "$expected_checksum" ]];then
log "ERROR: Checksum mismatch! Expected: $expected_checksum, Got: $actual_checksum"
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
(if
! load_virtio_mapping
then
log "ERROR: Failed to load virtio mapping"
exit 1
fi) \
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
if [[ -n $BOOT_DISK ]];then
DRIVE_ARGS="$DRIVE_ARGS -drive file=$BOOT_DISK,format=raw,media=disk,if=virtio"
fi
for drive in "${ZFS_POOL_DISKS[@]}";do
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
download_template "./templates/fastfetch.sh"||exit 1
download_template "./templates/bat-config"||exit 1
download_template "./templates/fail2ban-jail.local"||exit 1
download_template "./templates/fail2ban-proxmox.conf"||exit 1
download_template "./templates/auditd-rules"||exit 1
download_template "./templates/apparmor-grub.cfg"||exit 1
download_template "./templates/disable-openssh.service"||exit 1
download_template "./templates/stealth-firewall.service"||exit 1
download_template "./templates/yazi-theme.toml"||exit 1
download_template "./templates/prometheus-node-exporter"||exit 1
download_template "./templates/proxmox-metrics.sh"||exit 1
download_template "./templates/proxmox-metrics.cron"||exit 1) > \
/dev/null 2>&1&
if ! show_progress $! "Downloading template files";then
log "ERROR: Failed to download template files"
exit 1
fi
(apply_common_template_vars "./templates/hosts"
apply_common_template_vars "./templates/interfaces"
postprocess_interfaces_ipv6 "./templates/interfaces"
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
(remote_exec "mkdir -p /root/.config/bat"
remote_copy "templates/bat-config" "/root/.config/bat/config") > \
/dev/null 2>&1&
show_progress $! "Configuring bat" "Bat configured"
}
configure_shell(){
if [[ $SHELL_TYPE == "zsh" ]];then
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
if [[ $TAILSCALE_SSH == "yes" && $TAILSCALE_DISABLE_SSH == "yes" ]];then
log "Deploying disable-openssh.service (TAILSCALE_SSH=$TAILSCALE_SSH, TAILSCALE_DISABLE_SSH=$TAILSCALE_DISABLE_SSH)"
(log "Using pre-downloaded disable-openssh.service, size: $(wc -c <./templates/disable-openssh.service 2>/dev/null||echo 'failed')"
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
(log "Using pre-downloaded stealth-firewall.service, size: $(wc -c <./templates/stealth-firewall.service 2>/dev/null||echo 'failed')"
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
_install_apparmor(){
run_remote "Installing AppArmor" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq apparmor apparmor-utils
  ' "AppArmor installed"
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

    # Enable and start AppArmor service
    systemctl enable apparmor.service
    systemctl start apparmor.service 2>/dev/null || true

    # Load profiles in enforce mode
    if command -v aa-enforce >/dev/null 2>&1; then
      for profile in /etc/apparmor.d/*; do
        [[ -f "$profile" && ! -d "$profile" ]] && aa-enforce "$profile" 2>/dev/null || true
      done
    fi
  '||exit 1
}
configure_apparmor(){
if [[ ${INSTALL_APPARMOR:-} != "yes" ]];then
log "Skipping AppArmor (not requested)"
return 0
fi
log "Installing and configuring AppArmor"
(_install_apparmor||exit 1
_config_apparmor||exit 1) > \
/dev/null 2>&1&
show_progress $! "Installing and configuring AppArmor" "AppArmor configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: AppArmor setup failed"
print_warning "AppArmor setup failed - continuing without it"
return 0
fi
APPARMOR_INSTALLED="yes"
}
_install_fail2ban(){
run_remote "Installing Fail2Ban" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq fail2ban
  ' "Fail2Ban installed"
}
_config_fail2ban(){
apply_template_vars "./templates/fail2ban-jail.local" \
"EMAIL=$EMAIL" \
"HOSTNAME=$PVE_HOSTNAME"
remote_copy "templates/fail2ban-jail.local" "/etc/fail2ban/jail.local"||exit 1
remote_copy "templates/fail2ban-proxmox.conf" "/etc/fail2ban/filter.d/proxmox.conf"||exit 1
remote_exec "systemctl enable fail2ban && systemctl restart fail2ban"||exit 1
}
configure_fail2ban(){
if [[ $INSTALL_TAILSCALE == "yes" ]];then
log "Skipping Fail2Ban (Tailscale provides security)"
return 0
fi
log "Installing Fail2Ban (no Tailscale)"
(_install_fail2ban||exit 1
_config_fail2ban||exit 1) > \
/dev/null 2>&1&
show_progress $! "Installing and configuring Fail2Ban" "Fail2Ban configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Fail2Ban setup failed"
print_warning "Fail2Ban setup failed - continuing without it"
return 0
fi
FAIL2BAN_INSTALLED="yes"
}
_install_auditd(){
run_remote "Installing auditd" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq auditd audispd-plugins
  ' "Auditd installed"
}
_config_auditd(){
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
  '||exit 1
}
configure_auditd(){
if [[ $INSTALL_AUDITD != "yes" ]];then
log "Skipping auditd (not requested)"
return 0
fi
log "Installing and configuring auditd"
(_install_auditd||exit 1
_config_auditd||exit 1) > \
/dev/null 2>&1&
show_progress $! "Installing and configuring auditd" "Auditd configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Auditd setup failed"
print_warning "Auditd setup failed - continuing without it"
return 0
fi
AUDITD_INSTALLED="yes"
}
_install_yazi(){
run_remote "Installing yazi" '
    # Install dependencies
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq curl file unzip

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
remote_exec 'mkdir -p /root/.config/yazi'||exit 1
remote_copy "templates/yazi-theme.toml" "/root/.config/yazi/theme.toml"||exit 1
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
print_warning "Yazi setup failed - continuing without it"
return 0
fi
YAZI_INSTALLED="yes"
}
_install_nvim(){
run_remote "Installing neovim" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq neovim
  ' "Neovim installed"
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
  '||exit 1
}
configure_nvim(){
if [[ $INSTALL_NVIM != "yes" ]];then
log "Skipping neovim (not requested)"
return 0
fi
log "Installing and configuring neovim"
(_install_nvim||exit 1
_config_nvim||exit 1) > \
/dev/null 2>&1&
show_progress $! "Installing and configuring neovim" "Neovim configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Neovim setup failed"
print_warning "Neovim setup failed - continuing without it"
return 0
fi
NVIM_INSTALLED="yes"
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
(remote_exec '
      # Check if Proxmox VE packages are installed
      if ! dpkg -l | grep -q "proxmox-ve"; then
        echo "ERROR: Proxmox VE package not found"
        exit 1
      fi

      # Check if pveproxy service is running (Proxmox web interface)
      if ! systemctl is-active --quiet pveproxy; then
        echo "ERROR: pveproxy service is not running"
        exit 1
      fi

      # Check if pvedaemon is running (Proxmox API daemon)
      if ! systemctl is-active --quiet pvedaemon; then
        echo "ERROR: pvedaemon service is not running"
        exit 1
      fi

      # Check if ZFS pool exists
      if ! zpool list | grep -q "rpool"; then
        echo "ERROR: ZFS root pool (rpool) not found"
        exit 1
      fi

      exit 0
    '||exit 1) > \
/dev/null 2>&1&
show_progress $! "Validating installation" "Installation validated"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "ERROR: Installation validation failed"
print_error "Installation validation failed - review logs for details"
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
configure_proxmox_via_ssh(){
log "Starting Proxmox configuration via SSH"
make_templates
configure_base_system
configure_zfs_arc
configure_zfs_pool
configure_shell
configure_system_services
if type live_log_security_configuration &>/dev/null 2>&1;then
live_log_security_configuration
fi
configure_tailscale
configure_apparmor
configure_fail2ban
configure_auditd
configure_prometheus
configure_yazi
configure_nvim
if type live_log_ssl_configuration &>/dev/null 2>&1;then
live_log_ssl_configuration
fi
configure_ssl_certificate
if [[ $INSTALL_API_TOKEN == "yes" ]];then
(source "$SCRIPT_DIR/58-configure-api-token.sh"
create_api_token||exit 1) > \
/dev/null 2>&1&
show_progress $! "Creating API token" "API token created"
fi
if type live_log_validation_finalization &>/dev/null 2>&1;then
live_log_validation_finalization
fi
configure_ssh_hardening
validate_installation
finalize_vm
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
print_warning "API token creation failed - continuing without it"
return 1
fi
local token_value
token_value=$(echo "$output"|jq -r '.value // empty' 2>/dev/null||true)
if [[ -z $token_value ]];then
log "ERROR: Failed to extract token value from pveum output"
log "DEBUG: pveum output: $output"
print_warning "API token creation failed - continuing without it"
return 1
fi
API_TOKEN_VALUE="$token_value"
API_TOKEN_ID="root@pam!$API_TOKEN_NAME"
cat >/tmp/pve-install-api-token.env <<EOF
API_TOKEN_VALUE=$token_value
API_TOKEN_ID=$API_TOKEN_ID
API_TOKEN_NAME=$API_TOKEN_NAME
EOF
log "INFO: API token created successfully: $API_TOKEN_ID"
return 0
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
_install_prometheus(){
run_remote "Installing prometheus-node-exporter" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq prometheus-node-exporter
  ' "Prometheus node exporter installed"
}
_config_prometheus(){
remote_exec '
    mkdir -p /var/lib/prometheus/node-exporter
    chown prometheus:prometheus /var/lib/prometheus/node-exporter
  '||exit 1
remote_copy "templates/prometheus-node-exporter" "/etc/default/prometheus-node-exporter"||exit 1
remote_copy "templates/proxmox-metrics.sh" "/usr/local/bin/proxmox-metrics.sh"||exit 1
remote_exec "chmod +x /usr/local/bin/proxmox-metrics.sh"||exit 1
remote_copy "templates/proxmox-metrics.cron" "/etc/cron.d/proxmox-metrics"||exit 1
remote_exec "/usr/local/bin/proxmox-metrics.sh" >/dev/null 2>&1||log "WARNING: Initial metrics collection failed (non-fatal)"
remote_exec '
    systemctl daemon-reload
    systemctl enable prometheus-node-exporter
    systemctl restart prometheus-node-exporter

    # Verify service is running
    systemctl is-active --quiet prometheus-node-exporter || exit 1
  '||exit 1
log "Prometheus node exporter listening on :9100 with textfile collector"
log "Custom metrics cron job installed (/etc/cron.d/proxmox-metrics, runs every 5 minutes)"
}
configure_prometheus(){
if [[ $INSTALL_PROMETHEUS != "yes" ]];then
log "Skipping prometheus-node-exporter (not requested)"
return 0
fi
log "Installing and configuring prometheus-node-exporter"
(_install_prometheus||exit 1
_config_prometheus||exit 1) > \
/dev/null 2>&1&
show_progress $! "Installing and configuring prometheus" "Prometheus configured"
local exit_code=$?
if [[ $exit_code -ne 0 ]];then
log "WARNING: Prometheus setup failed"
print_warning "Prometheus setup failed - continuing without it"
return 0
fi
PROMETHEUS_INSTALLED="yes"
if [[ $INSTALL_TAILSCALE == "yes" ]];then
log "Prometheus metrics accessible via Tailscale only (stealth firewall enabled)"
else
log "WARNING: Prometheus metrics exposed on public IP $MAIN_IPV4:9100"
log "Consider using firewall rules to restrict access to trusted IPs only"
fi
log "Textfile collector directory: /var/lib/prometheus/node-exporter"
}
_show_credentials_info(){
echo ""
print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$CLR_YELLOW${CLR_BOLD}Access Credentials$CLR_RESET $CLR_RED(SAVE THIS!)$CLR_RESET"
print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "$CLR_CYAN${CLR_BOLD}Root Access:$CLR_RESET"
echo "$CLR_CYAN  Hostname:$CLR_RESET  $PVE_HOSTNAME.$DOMAIN_SUFFIX"
echo "$CLR_CYAN  Username:$CLR_RESET  root"
echo "$CLR_CYAN  Password:$CLR_RESET  $NEW_ROOT_PASSWORD"
echo "$CLR_CYAN  Web UI:$CLR_RESET    https://$MAIN_IPV4:8006"
if [[ -f /tmp/pve-install-api-token.env ]];then
source /tmp/pve-install-api-token.env
if [[ -n $API_TOKEN_VALUE ]];then
echo ""
echo "$CLR_CYAN${CLR_BOLD}API Token:$CLR_RESET"
echo "$CLR_CYAN  Token ID:$CLR_RESET  $API_TOKEN_ID"
echo "$CLR_CYAN  Secret:$CLR_RESET    $API_TOKEN_VALUE"
echo ""
echo "$CLR_DIM  Usage (curl):$CLR_RESET"
echo "$CLR_DIM    curl -k -H \"Authorization: PVEAPIToken=$API_TOKEN_ID=$API_TOKEN_VALUE\" \\$CLR_RESET"
echo "$CLR_DIM         https://$MAIN_IPV4:8006/api2/json/nodes$CLR_RESET"
echo ""
echo "$CLR_DIM  Properties: privileged (full root@pam rights), never expires$CLR_RESET"
echo "$CLR_DIM  Revoke via: pveum user token remove $API_TOKEN_ID$CLR_RESET"
fi
fi
print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
}
reboot_to_main_os(){
finish_live_installation
_wiz_start_edit
print_info "Installation completed successfully!"
echo ""
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
declare -p|grep -E "^declare -[^ ]* (PREFLIGHT_|DRIVE_|INTERFACE_|CURRENT_INTERFACE|PREDICTABLE_NAME|DEFAULT_INTERFACE|AVAILABLE_|MAC_ADDRESS|MAIN_IPV|IPV6_|FIRST_IPV6_|_ISO_|_CHECKSUM_)" >"$SYSTEM_INFO_CACHE"
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
live_log_system_preparation
log "Step: prepare_packages"
prepare_packages
log_metric "packages"
live_log_iso_download
log "Step: download_proxmox_iso"
download_proxmox_iso
log_metric "iso_download"
live_log_autoinstall_preparation
log "Step: make_answer_toml"
make_answer_toml
log "Step: make_autoinstall_iso"
make_autoinstall_iso
log_metric "autoinstall_prep"
live_log_proxmox_installation
log "Step: install_proxmox"
install_proxmox
log_metric "proxmox_install"
log "Step: boot_proxmox_with_port_forwarding"
boot_proxmox_with_port_forwarding||{
log "ERROR: Failed to boot Proxmox with port forwarding"
exit 1
}
log_metric "qemu_boot"
live_log_system_configuration
log "Step: configure_proxmox_via_ssh"
configure_proxmox_via_ssh
log_metric "system_config"
live_log_installation_complete
finish_live_installation
metrics_finish
INSTALL_COMPLETED=true
log "Step: reboot_to_main_os"
reboot_to_main_os
