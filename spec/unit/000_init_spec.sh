# shellcheck shell=bash
# shellcheck disable=SC2034,SC2016
# =============================================================================
# Tests for 000-init.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"
%const SUPPORT_DIR: "${SHELLSPEC_PROJECT_ROOT}/spec/support"

# Load init mocks (prevents side effects during sourcing)
eval "$(cat "$SUPPORT_DIR/init_mocks.sh")"

Describe "000-init.sh"
  Include "$SCRIPTS_DIR/000-init.sh"

  # ===========================================================================
  # Color constants
  # ===========================================================================
  Describe "color constants"
    It "defines CLR_RED"
      The variable CLR_RED should be defined
      The variable CLR_RED should include "31m"
    End

    It "defines CLR_CYAN"
      The variable CLR_CYAN should be defined
      The variable CLR_CYAN should include "38;2"
    End

    It "defines CLR_YELLOW"
      The variable CLR_YELLOW should be defined
      The variable CLR_YELLOW should include "33m"
    End

    It "defines CLR_ORANGE"
      The variable CLR_ORANGE should be defined
      The variable CLR_ORANGE should include "38;5;208"
    End

    It "defines CLR_GRAY"
      The variable CLR_GRAY should be defined
      The variable CLR_GRAY should include "38;5;240"
    End

    It "defines CLR_GOLD"
      The variable CLR_GOLD should be defined
      The variable CLR_GOLD should include "38;5;179"
    End

    It "defines CLR_RESET"
      The variable CLR_RESET should be defined
      The variable CLR_RESET should include "[m"
    End
  End

  # ===========================================================================
  # Hex color constants (for gum)
  # ===========================================================================
  Describe "hex color constants"
    It "defines HEX_RED as valid hex"
      The variable HEX_RED should equal "#ff0000"
    End

    It "defines HEX_CYAN as valid hex"
      The variable HEX_CYAN should equal "#00b1ff"
    End

    It "defines HEX_YELLOW as valid hex"
      The variable HEX_YELLOW should equal "#ffff00"
    End

    It "defines HEX_ORANGE as valid hex"
      The variable HEX_ORANGE should equal "#ff8700"
    End

    It "defines HEX_WHITE as valid hex"
      The variable HEX_WHITE should equal "#ffffff"
    End
  End

  # ===========================================================================
  # Version and dimensions
  # ===========================================================================
  Describe "version and dimensions"
    It "defines VERSION"
      The variable VERSION should be defined
      The variable VERSION should not equal ""
    End

    It "defines TERM_WIDTH as 80"
      The variable TERM_WIDTH should equal 80
    End

    It "defines BANNER_WIDTH as 51"
      The variable BANNER_WIDTH should equal 51
    End
  End

  # ===========================================================================
  # URL constants
  # ===========================================================================
  Describe "URL constants"
    It "defines PROXMOX_ISO_BASE_URL"
      The variable PROXMOX_ISO_BASE_URL should include "proxmox.com"
      The variable PROXMOX_ISO_BASE_URL should include "iso"
    End

    It "defines PROXMOX_CHECKSUM_URL"
      The variable PROXMOX_CHECKSUM_URL should include "SHA256SUMS"
    End

    It "defines GITHUB_BASE_URL"
      The variable GITHUB_BASE_URL should include "github.com"
    End
  End

  # ===========================================================================
  # DNS constants
  # ===========================================================================
  Describe "DNS constants"
    It "defines DNS_PRIMARY as valid IPv4"
      The variable DNS_PRIMARY should equal "1.1.1.1"
    End

    It "defines DNS_SECONDARY as valid IPv4"
      The variable DNS_SECONDARY should equal "1.0.0.1"
    End

    It "defines DNS6_PRIMARY as valid IPv6"
      The variable DNS6_PRIMARY should include "2606:4700"
    End

    It "defines DNS_SERVERS array"
      The variable DNS_SERVERS should be defined
    End
  End

  # ===========================================================================
  # Resource requirements
  # ===========================================================================
  Describe "resource requirements"
    It "defines MIN_DISK_SPACE_MB > 0"
      The variable MIN_DISK_SPACE_MB should be defined
      The value "$((MIN_DISK_SPACE_MB >= 6000))" should equal 1
    End

    It "defines MIN_RAM_MB > 0"
      The variable MIN_RAM_MB should be defined
      The value "$((MIN_RAM_MB >= 4000))" should equal 1
    End

    It "defines MIN_CPU_CORES >= 2"
      The variable MIN_CPU_CORES should be defined
      The value "$((MIN_CPU_CORES >= 2))" should equal 1
    End

    It "defines MIN_QEMU_RAM >= 4096"
      The variable MIN_QEMU_RAM should be defined
      The value "$((MIN_QEMU_RAM >= 4096))" should equal 1
    End
  End

  # ===========================================================================
  # Download and timeout settings
  # ===========================================================================
  Describe "download and timeout settings"
    It "defines DOWNLOAD_RETRY_COUNT > 0"
      The variable DOWNLOAD_RETRY_COUNT should be defined
      The value "$((DOWNLOAD_RETRY_COUNT > 0))" should equal 1
    End

    It "defines DOWNLOAD_RETRY_DELAY > 0"
      The variable DOWNLOAD_RETRY_DELAY should be defined
      The value "$((DOWNLOAD_RETRY_DELAY > 0))" should equal 1
    End

    It "defines SSH_CONNECT_TIMEOUT > 0"
      The variable SSH_CONNECT_TIMEOUT should be defined
      The value "$((SSH_CONNECT_TIMEOUT > 0))" should equal 1
    End

    It "defines QEMU_BOOT_TIMEOUT > 0"
      The variable QEMU_BOOT_TIMEOUT should be defined
      The value "$((QEMU_BOOT_TIMEOUT > 0))" should equal 1
    End

    It "defines QEMU_SSH_READY_TIMEOUT > 0"
      The variable QEMU_SSH_READY_TIMEOUT should be defined
      The value "$((QEMU_SSH_READY_TIMEOUT > 0))" should equal 1
    End
  End

  # ===========================================================================
  # Port constants
  # ===========================================================================
  Describe "port constants"
    It "defines SSH_PORT_QEMU as 5555"
      The variable SSH_PORT_QEMU should equal 5555
    End

    It "defines PORT_SSH as 22"
      The variable PORT_SSH should equal 22
    End

    It "defines PORT_PROXMOX_UI as 8006"
      The variable PORT_PROXMOX_UI should equal 8006
    End

    It "defines PORT_NETDATA as 19999"
      The variable PORT_NETDATA should equal 19999
    End
  End

  # ===========================================================================
  # Wizard option lists
  # ===========================================================================
  Describe "wizard option lists"
    It "defines WIZ_KEYBOARD_LAYOUTS with en-us"
      The variable WIZ_KEYBOARD_LAYOUTS should include "en-us"
    End

    It "defines WIZ_KEYBOARD_LAYOUTS with de"
      The variable WIZ_KEYBOARD_LAYOUTS should include "de"
    End

    It "defines WIZ_REPO_TYPES"
      The variable WIZ_REPO_TYPES should include "No-subscription"
      The variable WIZ_REPO_TYPES should include "Enterprise"
    End

    It "defines WIZ_BRIDGE_MODES"
      The variable WIZ_BRIDGE_MODES should include "NAT"
      The variable WIZ_BRIDGE_MODES should include "External"
    End

    It "defines WIZ_IPV6_MODES"
      The variable WIZ_IPV6_MODES should include "Auto"
      The variable WIZ_IPV6_MODES should include "Manual"
      The variable WIZ_IPV6_MODES should include "Disabled"
    End

    It "defines WIZ_ZFS_MODES"
      The variable WIZ_ZFS_MODES should include "Single"
      The variable WIZ_ZFS_MODES should include "RAID-1"
    End

    It "defines WIZ_SSL_TYPES"
      The variable WIZ_SSL_TYPES should include "Self-signed"
      The variable WIZ_SSL_TYPES should include "Let's Encrypt"
    End

    It "defines WIZ_FIREWALL_MODES"
      The variable WIZ_FIREWALL_MODES should include "Stealth"
      The variable WIZ_FIREWALL_MODES should include "Strict"
      The variable WIZ_FIREWALL_MODES should include "Standard"
    End

    It "defines WIZ_FEATURES_SECURITY"
      The variable WIZ_FEATURES_SECURITY should include "apparmor"
      The variable WIZ_FEATURES_SECURITY should include "auditd"
      The variable WIZ_FEATURES_SECURITY should include "aide"
    End

    It "defines WIZ_FEATURES_MONITORING"
      The variable WIZ_FEATURES_MONITORING should include "vnstat"
      The variable WIZ_FEATURES_MONITORING should include "netdata"
    End

    It "defines WIZ_FEATURES_TOOLS"
      The variable WIZ_FEATURES_TOOLS should include "yazi"
      The variable WIZ_FEATURES_TOOLS should include "nvim"
    End
  End

  # ===========================================================================
  # register_temp_file()
  # ===========================================================================
  Describe "register_temp_file()"
    It "registers a temp file"
      reset_temp_files
      When call register_temp_file "/tmp/testfile"
      The variable '_TEMP_FILES[0]' should equal "/tmp/testfile"
    End

    It "registers multiple temp files"
      reset_temp_files
      register_temp_file "/tmp/file1"
      When call register_temp_file "/tmp/file2"
      The variable '_TEMP_FILES[0]' should equal "/tmp/file1"
      The variable '_TEMP_FILES[1]' should equal "/tmp/file2"
    End
  End

  # ===========================================================================
  # cleanup_temp_files() logic
  # ===========================================================================
  Describe "cleanup_temp_files()"
    It "handles empty temp file list"
      reset_temp_files
      INSTALL_COMPLETED=true
      find() { :; }
      When call cleanup_temp_files
      The status should be success
    End

    It "handles missing files gracefully"
      reset_temp_files
      _TEMP_FILES=("/tmp/nonexistent_file_xyz")
      INSTALL_COMPLETED=true
      find() { :; }
      When call cleanup_temp_files
      The status should be success
    End
  End

  # ===========================================================================
  # Runtime configuration variables
  # ===========================================================================
  Describe "runtime configuration variables"
    It "initializes QEMU_RAM_OVERRIDE as empty"
      The variable QEMU_RAM_OVERRIDE should equal ""
    End

    It "initializes QEMU_CORES_OVERRIDE as empty"
      The variable QEMU_CORES_OVERRIDE should equal ""
    End

    It "initializes PROXMOX_ISO_VERSION as empty"
      The variable PROXMOX_ISO_VERSION should equal ""
    End

    It "initializes INSTALL_COMPLETED as false"
      The variable INSTALL_COMPLETED should equal false
    End

    It "initializes KEYBOARD with default"
      The variable KEYBOARD should equal "en-us"
    End

    It "initializes COUNTRY with default"
      The variable COUNTRY should equal "us"
    End

    It "initializes TIMEZONE with UTC"
      The variable TIMEZONE should equal "UTC"
    End

    It "defines SYSTEM_UTILITIES"
      The variable SYSTEM_UTILITIES should include "btop"
      The variable SYSTEM_UTILITIES should include "jq"
    End

    It "defines LOG_FILE path"
      The variable LOG_FILE should include "pve-install"
      The variable LOG_FILE should include ".log"
    End
  End

  # ===========================================================================
  # Password settings
  # ===========================================================================
  Describe "password settings"
    It "defines DEFAULT_PASSWORD_LENGTH as 16"
      The variable DEFAULT_PASSWORD_LENGTH should equal 16
    End
  End
End
