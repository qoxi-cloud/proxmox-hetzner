# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034
# =============================================================================
# Tests for 001-cli.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"
%const SUPPORT_DIR: "${SHELLSPEC_PROJECT_ROOT}/spec/support"

# Load shared colors (for CLR_* variables used in error messages)
eval "$(cat "$SUPPORT_DIR/colors.sh")"

Describe "001-cli.sh"
  # Disable auto-parse on source
  BeforeAll '_CLI_PARSE_ON_SOURCE=false; VERSION="2"'

  Include "$SCRIPTS_DIR/001-cli.sh"

  # ===========================================================================
  # show_help()
  # ===========================================================================
  Describe "show_help()"
    It "displays help message"
      When call show_help
      The status should be success
      The output should include "Qoxi Automated Installer"
      The output should include "--help"
      The output should include "--qemu-ram"
      The output should include "--qemu-cores"
      The output should include "--iso-version"
    End

    It "shows usage examples"
      When call show_help
      The output should include "Examples:"
      The output should include "Interactive installation"
    End
  End

  # ===========================================================================
  # parse_cli_args() - help/version
  # ===========================================================================
  Describe "parse_cli_args() help and version"
    It "returns 2 for -h (early exit)"
      When call parse_cli_args -h
      The status should equal 2
      The output should include "Qoxi Automated Installer"
    End

    It "returns 2 for --help (early exit)"
      When call parse_cli_args --help
      The status should equal 2
      The output should include "Qoxi Automated Installer"
    End

    It "returns 2 for -v (early exit)"
      When call parse_cli_args -v
      The status should equal 2
      The output should include "Proxmox Installer v"
    End

    It "returns 2 for --version (early exit)"
      When call parse_cli_args --version
      The status should equal 2
      The output should include "v2"
    End
  End

  # ===========================================================================
  # parse_cli_args() - --qemu-ram
  # ===========================================================================
  Describe "parse_cli_args() --qemu-ram"
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

    It "rejects negative number (treated as missing value)"
      When call parse_cli_args --qemu-ram -1024
      The status should be failure
      The output should include "requires a value"
    End
  End

  # ===========================================================================
  # parse_cli_args() - --qemu-cores
  # ===========================================================================
  Describe "parse_cli_args() --qemu-cores"
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

    It "rejects negative number (treated as missing value)"
      When call parse_cli_args --qemu-cores -4
      The status should be failure
      The output should include "requires a value"
    End
  End

  # ===========================================================================
  # parse_cli_args() - --iso-version
  # ===========================================================================
  Describe "parse_cli_args() --iso-version"
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
  # parse_cli_args() - unknown options
  # ===========================================================================
  Describe "parse_cli_args() unknown options"
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
  # parse_cli_args() - multiple options
  # ===========================================================================
  Describe "parse_cli_args() multiple options"
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
  # parse_cli_args() - no arguments
  # ===========================================================================
  Describe "parse_cli_args() no arguments"
    It "succeeds with no arguments"
      When call parse_cli_args
      The status should be success
    End

    It "resets variables with no arguments"
      QEMU_RAM_OVERRIDE="previous"
      QEMU_CORES_OVERRIDE="previous"
      PROXMOX_ISO_VERSION="previous"
      When call parse_cli_args
      The variable QEMU_RAM_OVERRIDE should equal ""
      The variable QEMU_CORES_OVERRIDE should equal ""
      The variable PROXMOX_ISO_VERSION should equal ""
    End
  End
End
