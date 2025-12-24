# shellcheck shell=bash
# shellcheck disable=SC2034,SC2016
# =============================================================================
# Tests for 200-packages.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"
%const SUPPORT_DIR: "${SHELLSPEC_PROJECT_ROOT}/spec/support"

# Load shared mocks
eval "$(cat "$SUPPORT_DIR/colors.sh")"
eval "$(cat "$SUPPORT_DIR/core_mocks.sh")"
eval "$(cat "$SUPPORT_DIR/packages_mocks.sh")"

Describe "200-packages.sh"
  Include "$SCRIPTS_DIR/200-packages.sh"

  # ===========================================================================
  # prepare_packages()
  # ===========================================================================
  Describe "prepare_packages()"
    BeforeEach 'reset_packages_mocks'

    Describe "successful execution"
      It "succeeds when all operations complete"
        When call prepare_packages
        The status should be success
      End

      It "logs startup message"
        logged=""
        log() { logged="$logged $*"; }
        When call prepare_packages
        The variable logged should include "Starting"
      End

      It "logs repository addition"
        logged=""
        log() { logged="$logged $*"; }
        When call prepare_packages
        The variable logged should include "repository"
      End

      It "logs GPG key download"
        logged=""
        log() { logged="$logged $*"; }
        When call prepare_packages
        The variable logged should include "GPG"
      End

      It "logs package installation"
        logged=""
        log() { logged="$logged $*"; }
        When call prepare_packages
        The variable logged should include "packages"
      End
    End

    Describe "curl failure"
      It "logs error when GPG key download fails"
        curl() { return 1; }
        wait() { return 1; }
        exit() { return "$1"; }
        logged=""
        log() { logged="$logged $*"; }
        When call prepare_packages
        The variable logged should include "ERROR"
      End
    End

    Describe "apt update failure"
      It "logs error when apt update fails"
        apt() {
          case "$1" in
            clean) return 0 ;;
            update) return 1 ;;
            *) return 0 ;;
          esac
        }
        # First wait succeeds (curl), second fails (apt update)
        _wait_call=0
        wait() {
          _wait_call=$((_wait_call + 1))
          [[ $_wait_call -eq 2 ]] && return 1
          return 0
        }
        exit() { return "$1"; }
        logged=""
        log() { logged="$logged $*"; }
        When call prepare_packages
        The variable logged should include "package"
      End
    End

    Describe "apt install failure"
      It "logs error when apt install fails"
        apt() {
          case "$1" in
            install) return 1 ;;
            *) return 0 ;;
          esac
        }
        # First two waits succeed, third fails (apt install)
        _wait_call=0
        wait() {
          _wait_call=$((_wait_call + 1))
          [[ $_wait_call -eq 3 ]] && return 1
          return 0
        }
        exit() { return "$1"; }
        logged=""
        log() { logged="$logged $*"; }
        When call prepare_packages
        The variable logged should include "package"
      End
    End

    Describe "live log integration"
      It "calls live_log_subtask when type succeeds"
        MOCK_SUBTASK_CALLS=()
        type() { return 0; }
        When call prepare_packages
        The variable 'MOCK_SUBTASK_CALLS[0]' should equal "Configuring APT sources"
      End
    End
  End
End
