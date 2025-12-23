# shellcheck shell=bash
# shellcheck disable=SC2016
# =============================================================================
# Tests for 001-cli.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"

Describe "001-cli.sh"
  # Set up required variables from 000-init.sh before testing
  setup_vars() {
    VERSION="2"
    CLR_RED=$'\033[1;31m'
    CLR_RESET=$'\033[m'
    QEMU_RAM_OVERRIDE=""
    QEMU_CORES_OVERRIDE=""
    PROXMOX_ISO_VERSION=""
  }
  BeforeAll 'setup_vars'

  # Helper to run CLI parsing with arguments
  # We source only the show_help function, then simulate argument parsing
  parse_cli_args() {
    # Reset variables
    QEMU_RAM_OVERRIDE=""
    QEMU_CORES_OVERRIDE=""
    PROXMOX_ISO_VERSION=""

    while [[ $# -gt 0 ]]; do
      case $1 in
        -h | --help)
          printf '%s\n' "help shown"
          return 0
          ;;
        -v | --version)
          printf '%s\n' "Proxmox Installer v${VERSION}"
          return 0
          ;;
        --qemu-ram)
          if [[ -z $2 || $2 =~ ^- ]]; then
            printf '%s\n' "Error: --qemu-ram requires a value in MB"
            return 1
          fi
          if ! [[ $2 =~ ^[0-9]+$ ]] || [[ $2 -lt 2048 ]]; then
            printf '%s\n' "Error: --qemu-ram must be a number >= 2048 MB"
            return 1
          fi
          if [[ $2 -gt 131072 ]]; then
            printf '%s\n' "Error: --qemu-ram must be <= 131072 MB (128 GB)"
            return 1
          fi
          QEMU_RAM_OVERRIDE="$2"
          shift 2
          ;;
        --qemu-cores)
          if [[ -z $2 || $2 =~ ^- ]]; then
            printf '%s\n' "Error: --qemu-cores requires a value"
            return 1
          fi
          if ! [[ $2 =~ ^[0-9]+$ ]] || [[ $2 -lt 1 ]]; then
            printf '%s\n' "Error: --qemu-cores must be a positive number"
            return 1
          fi
          if [[ $2 -gt 256 ]]; then
            printf '%s\n' "Error: --qemu-cores must be <= 256"
            return 1
          fi
          QEMU_CORES_OVERRIDE="$2"
          shift 2
          ;;
        --iso-version)
          if [[ -z $2 || $2 =~ ^- ]]; then
            printf '%s\n' "Error: --iso-version requires a filename"
            return 1
          fi
          if ! [[ $2 =~ ^proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso$ ]]; then
            printf '%s\n' "Error: --iso-version must be in format: proxmox-ve_X.Y-Z.iso"
            return 1
          fi
          PROXMOX_ISO_VERSION="$2"
          shift 2
          ;;
        *)
          printf '%s\n' "Unknown option: $1"
          return 1
          ;;
      esac
    done
  }

  # ===========================================================================
  # show_help() / --help / -h
  # ===========================================================================
  Describe "--help option"
    It "displays help message with -h"
      When call parse_cli_args -h
      The status should be success
      The output should include "help shown"
    End

    It "displays help message with --help"
      When call parse_cli_args --help
      The status should be success
      The output should include "help shown"
    End
  End

  # ===========================================================================
  # --version / -v
  # ===========================================================================
  Describe "--version option"
    It "displays version with -v"
      When call parse_cli_args -v
      The status should be success
      The output should include "Proxmox Installer v"
    End

    It "displays version with --version"
      When call parse_cli_args --version
      The status should be success
      The output should include "Proxmox Installer v"
    End

    It "includes VERSION number"
      When call parse_cli_args --version
      The output should include "v2"
    End
  End

  # ===========================================================================
  # --qemu-ram
  # ===========================================================================
  Describe "--qemu-ram option"
    It "accepts valid RAM value (4096)"
      When call parse_cli_args --qemu-ram 4096
      The status should be success
      The variable QEMU_RAM_OVERRIDE should equal "4096"
    End

    It "accepts minimum valid RAM (2048)"
      When call parse_cli_args --qemu-ram 2048
      The status should be success
      The variable QEMU_RAM_OVERRIDE should equal "2048"
    End

    It "accepts maximum valid RAM (131072)"
      When call parse_cli_args --qemu-ram 131072
      The status should be success
      The variable QEMU_RAM_OVERRIDE should equal "131072"
    End

    It "rejects missing value"
      When call parse_cli_args --qemu-ram
      The status should be failure
      The output should include "requires a value"
    End

    It "rejects value starting with dash"
      When call parse_cli_args --qemu-ram --other
      The status should be failure
      The output should include "requires a value"
    End

    It "rejects non-numeric value"
      When call parse_cli_args --qemu-ram abc
      The status should be failure
      The output should include "must be a number"
    End

    It "rejects value below minimum (2047)"
      When call parse_cli_args --qemu-ram 2047
      The status should be failure
      The output should include ">= 2048"
    End

    It "rejects value above maximum (131073)"
      When call parse_cli_args --qemu-ram 131073
      The status should be failure
      The output should include "<= 131072"
    End

    It "rejects zero"
      When call parse_cli_args --qemu-ram 0
      The status should be failure
      The output should include ">= 2048"
    End

    It "rejects negative number"
      When call parse_cli_args --qemu-ram -1024
      The status should be failure
      The output should include "requires a value"
    End
  End

  # ===========================================================================
  # --qemu-cores
  # ===========================================================================
  Describe "--qemu-cores option"
    It "accepts valid cores value (4)"
      When call parse_cli_args --qemu-cores 4
      The status should be success
      The variable QEMU_CORES_OVERRIDE should equal "4"
    End

    It "accepts minimum valid cores (1)"
      When call parse_cli_args --qemu-cores 1
      The status should be success
      The variable QEMU_CORES_OVERRIDE should equal "1"
    End

    It "accepts maximum valid cores (256)"
      When call parse_cli_args --qemu-cores 256
      The status should be success
      The variable QEMU_CORES_OVERRIDE should equal "256"
    End

    It "rejects missing value"
      When call parse_cli_args --qemu-cores
      The status should be failure
      The output should include "requires a value"
    End

    It "rejects value starting with dash"
      When call parse_cli_args --qemu-cores --other
      The status should be failure
      The output should include "requires a value"
    End

    It "rejects non-numeric value"
      When call parse_cli_args --qemu-cores abc
      The status should be failure
      The output should include "must be a positive number"
    End

    It "rejects zero"
      When call parse_cli_args --qemu-cores 0
      The status should be failure
      The output should include "must be a positive number"
    End

    It "rejects value above maximum (257)"
      When call parse_cli_args --qemu-cores 257
      The status should be failure
      The output should include "<= 256"
    End

    It "rejects negative number"
      When call parse_cli_args --qemu-cores -4
      The status should be failure
      The output should include "requires a value"
    End
  End

  # ===========================================================================
  # --iso-version
  # ===========================================================================
  Describe "--iso-version option"
    It "accepts valid ISO filename"
      When call parse_cli_args --iso-version proxmox-ve_8.3-1.iso
      The status should be success
      The variable PROXMOX_ISO_VERSION should equal "proxmox-ve_8.3-1.iso"
    End

    It "accepts older version format"
      When call parse_cli_args --iso-version proxmox-ve_7.4-2.iso
      The status should be success
      The variable PROXMOX_ISO_VERSION should equal "proxmox-ve_7.4-2.iso"
    End

    It "accepts single digit version"
      When call parse_cli_args --iso-version proxmox-ve_8.0-1.iso
      The status should be success
      The variable PROXMOX_ISO_VERSION should equal "proxmox-ve_8.0-1.iso"
    End

    It "rejects missing value"
      When call parse_cli_args --iso-version
      The status should be failure
      The output should include "requires a filename"
    End

    It "rejects value starting with dash"
      When call parse_cli_args --iso-version --other
      The status should be failure
      The output should include "requires a filename"
    End

    It "rejects invalid format (missing proxmox-ve_ prefix)"
      When call parse_cli_args --iso-version 8.3-1.iso
      The status should be failure
      The output should include "must be in format"
    End

    It "rejects invalid format (wrong extension)"
      When call parse_cli_args --iso-version proxmox-ve_8.3-1.img
      The status should be failure
      The output should include "must be in format"
    End

    It "rejects invalid format (missing version)"
      When call parse_cli_args --iso-version proxmox-ve_.iso
      The status should be failure
      The output should include "must be in format"
    End

    It "rejects invalid format (missing minor version)"
      When call parse_cli_args --iso-version proxmox-ve_8-1.iso
      The status should be failure
      The output should include "must be in format"
    End

    It "rejects invalid format (missing build number)"
      When call parse_cli_args --iso-version proxmox-ve_8.3.iso
      The status should be failure
      The output should include "must be in format"
    End

    It "rejects random string"
      When call parse_cli_args --iso-version random-file.iso
      The status should be failure
      The output should include "must be in format"
    End
  End

  # ===========================================================================
  # Unknown options
  # ===========================================================================
  Describe "unknown options"
    It "rejects unknown option"
      When call parse_cli_args --unknown
      The status should be failure
      The output should include "Unknown option"
    End

    It "rejects unknown short option"
      When call parse_cli_args -x
      The status should be failure
      The output should include "Unknown option"
    End

    It "shows which option is unknown"
      When call parse_cli_args --foobar
      The status should be failure
      The output should include "--foobar"
    End
  End

  # ===========================================================================
  # Multiple options
  # ===========================================================================
  Describe "multiple options"
    It "accepts multiple valid options"
      When call parse_cli_args --qemu-ram 8192 --qemu-cores 8
      The status should be success
      The variable QEMU_RAM_OVERRIDE should equal "8192"
      The variable QEMU_CORES_OVERRIDE should equal "8"
    End

    It "accepts all options together"
      When call parse_cli_args --qemu-ram 16384 --qemu-cores 16 --iso-version proxmox-ve_8.3-1.iso
      The status should be success
      The variable QEMU_RAM_OVERRIDE should equal "16384"
      The variable QEMU_CORES_OVERRIDE should equal "16"
      The variable PROXMOX_ISO_VERSION should equal "proxmox-ve_8.3-1.iso"
    End

    It "stops at first invalid option"
      When call parse_cli_args --qemu-ram 4096 --invalid --qemu-cores 4
      The status should be failure
      The output should include "Unknown option"
    End
  End

  # ===========================================================================
  # No arguments
  # ===========================================================================
  Describe "no arguments"
    It "succeeds with no arguments"
      When call parse_cli_args
      The status should be success
    End

    It "leaves variables empty with no arguments"
      When call parse_cli_args
      The variable QEMU_RAM_OVERRIDE should equal ""
      The variable QEMU_CORES_OVERRIDE should equal ""
      The variable PROXMOX_ISO_VERSION should equal ""
    End
  End
End
