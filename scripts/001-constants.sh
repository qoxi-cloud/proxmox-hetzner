# shellcheck shell=bash
# Configuration constants

# GitHub repository for template downloads (can be overridden via environment)
GITHUB_REPO="${GITHUB_REPO:-qoxi-cloud/proxmox-installer}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_BASE_URL="https://github.com/${GITHUB_REPO}/raw/refs/heads/${GITHUB_BRANCH}"

# Proxmox ISO download URLs
readonly PROXMOX_ISO_BASE_URL="https://enterprise.proxmox.com/iso/"
readonly PROXMOX_CHECKSUM_URL="https://enterprise.proxmox.com/iso/SHA256SUMS"

# DNS servers for connectivity checks and resolution (IPv4)
readonly DNS_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
readonly DNS_PRIMARY="1.1.1.1"
readonly DNS_SECONDARY="1.0.0.1"

# DNS servers (IPv6) - Cloudflare
readonly DNS6_PRIMARY="2606:4700:4700::1111"
readonly DNS6_SECONDARY="2606:4700:4700::1001"

# Resource requirements (ISO ~3.5GB + QEMU + overhead = 6GB)
readonly MIN_DISK_SPACE_MB=6000
readonly MIN_RAM_MB=4000
readonly MIN_CPU_CORES=2

# QEMU defaults
readonly MIN_QEMU_RAM=4096

# Download settings
readonly DOWNLOAD_RETRY_COUNT=3
readonly DOWNLOAD_RETRY_DELAY=2

# SSH settings
readonly SSH_CONNECT_TIMEOUT=10

# Ports configuration
readonly SSH_PORT_QEMU=5555   # SSH port for QEMU VM (installer-internal)
readonly PORT_SSH=22          # Standard SSH port for firewall rules
readonly PORT_PROXMOX_UI=8006 # Proxmox Web UI port

# Password settings
readonly DEFAULT_PASSWORD_LENGTH=16

# QEMU memory settings
readonly QEMU_MIN_RAM_RESERVE=2048

# DNS lookup timeout (seconds)
readonly DNS_LOOKUP_TIMEOUT=5

# Retry delays (seconds)
readonly DNS_RETRY_DELAY=10

# QEMU boot timeouts (seconds)
readonly QEMU_BOOT_TIMEOUT=300      # Max wait for QEMU to boot and expose SSH port
readonly QEMU_PORT_CHECK_INTERVAL=3 # Interval between port availability checks
readonly QEMU_SSH_READY_TIMEOUT=120 # Max wait for SSH to be fully ready

# Retry and timing constants
readonly RETRY_DELAY_SECONDS=2      # Standard retry delay for recoverable operations
readonly SSH_RETRY_ATTEMPTS=3       # Number of SSH connection retries
readonly PROGRESS_POLL_INTERVAL=0.2 # Polling interval for progress indicators
readonly PROCESS_KILL_WAIT=1        # Wait time after sending SIGTERM before SIGKILL
readonly VM_SHUTDOWN_TIMEOUT=120    # Max wait for VM to shutdown gracefully
readonly WIZARD_MESSAGE_DELAY=3     # Display duration for wizard notifications

# Keyboard layouts supported by Proxmox installer (from official documentation)
# shellcheck disable=SC2034
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
