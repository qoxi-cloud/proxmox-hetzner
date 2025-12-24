# shellcheck shell=bash
# shellcheck disable=SC2034
# =============================================================================
# Tests for 301-configure-tailscale.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"
%const SUPPORT_DIR: "${SHELLSPEC_PROJECT_ROOT}/spec/support"

# Load shared mocks
eval "$(cat "$SUPPORT_DIR/configure_mocks.sh")"

# Additional mocks specific to this script
add_log() { :; }
complete_task() { :; }
TASK_INDEX=0

# Create mock template file for stealth mode tests
# Note: Uses full path to ensure visibility across subshells
MOCK_TEMPLATE_DIR=""
setup_mock_template() {
  MOCK_TEMPLATE_DIR=$(mktemp -d)
  mkdir -p "$MOCK_TEMPLATE_DIR/templates"
  echo "mock service" > "$MOCK_TEMPLATE_DIR/templates/disable-openssh.service"
  # Also create in working directory for relative path access
  mkdir -p ./templates 2>/dev/null || true
  echo "mock service" > ./templates/disable-openssh.service
}

cleanup_mock_template() {
  rm -rf "$MOCK_TEMPLATE_DIR" 2>/dev/null || true
  rm -f ./templates/disable-openssh.service 2>/dev/null || true
}

Describe "301-configure-tailscale.sh"
  Include "$SCRIPTS_DIR/301-configure-tailscale.sh"

  # ===========================================================================
  # _config_tailscale()
  # ===========================================================================
  Describe "_config_tailscale()"
    BeforeEach 'MOCK_REMOTE_RUN_RESULT=0; MOCK_REMOTE_EXEC_RESULT=0; MOCK_REMOTE_COPY_RESULT=0; TAILSCALE_AUTH_KEY=""; TAILSCALE_WEBUI="no"; FIREWALL_MODE="standard"; TAILSCALE_IP=""; TAILSCALE_HOSTNAME=""'

    # -------------------------------------------------------------------------
    # Starting tailscaled
    # -------------------------------------------------------------------------
    Describe "starting tailscaled"
      It "starts tailscaled successfully"
        When call _config_tailscale
        The status should be success
      End

      It "continues when remote_run has issues (true at end of script)"
        # Note: The script has 'true' at the end so it always succeeds
        MOCK_REMOTE_RUN_RESULT=1
        When call _config_tailscale
        The status should be success
      End
    End

    # -------------------------------------------------------------------------
    # Without auth key
    # -------------------------------------------------------------------------
    Describe "without auth key"
      BeforeEach 'TAILSCALE_AUTH_KEY=""'

      It "sets TAILSCALE_IP to not authenticated"
        When call _config_tailscale
        The status should be success
        The variable TAILSCALE_IP should equal "not authenticated"
      End

      It "sets TAILSCALE_HOSTNAME to empty"
        When call _config_tailscale
        The status should be success
        The variable TAILSCALE_HOSTNAME should equal ""
      End

      It "calls add_log for warning messages"
        add_log_called=0
        add_log() { add_log_called=$((add_log_called + 1)); }
        When call _config_tailscale
        The status should be success
        The variable add_log_called should equal 2
      End
    End

    # -------------------------------------------------------------------------
    # With auth key
    # -------------------------------------------------------------------------
    Describe "with auth key"
      BeforeEach 'TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"; MOCK_REMOTE_EXEC_RESULT=0; MOCK_REMOTE_EXEC_OUTPUT=""'

      It "authenticates successfully"
        When call _config_tailscale
        The status should be success
      End

      It "calls complete_task after authentication"
        complete_task_called=false
        complete_task() { complete_task_called=true; }
        When call _config_tailscale
        The status should be success
        The variable complete_task_called should equal true
      End

      It "sets TAILSCALE_IP from remote response"
        # Use variable-based mock output (variables propagate to subshells, inline functions don't)
        MOCK_REMOTE_EXEC_OUTPUT=$'100.100.100.1\thost.tailnet.ts.net'
        When call _config_tailscale
        The status should be success
        The variable TAILSCALE_IP should equal "100.100.100.1"
      End

      It "sets TAILSCALE_HOSTNAME from remote response"
        MOCK_REMOTE_EXEC_OUTPUT=$'100.100.100.1\tmyhost.tailnet.ts.net'
        When call _config_tailscale
        The status should be success
        The variable TAILSCALE_HOSTNAME should equal "myhost.tailnet.ts.net"
      End

      It "returns empty when no IP from remote (cat succeeds on empty file)"
        # When remote_exec returns nothing, cat reads empty file successfully
        MOCK_REMOTE_EXEC_OUTPUT=""
        When call _config_tailscale
        The status should be success
        The variable TAILSCALE_IP should equal ""
      End
    End

    # -------------------------------------------------------------------------
    # Tailscale Serve (Web UI)
    # -------------------------------------------------------------------------
    Describe "with Tailscale Serve enabled"
      BeforeEach 'TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"; TAILSCALE_WEBUI="yes"; MOCK_REMOTE_RUN_RESULT=0; MOCK_REMOTE_EXEC_RESULT=0'

      It "configures Tailscale Serve when TAILSCALE_WEBUI is yes"
        serve_configured=false
        remote_run() {
          if [[ $1 == *"Tailscale Serve"* ]]; then
            serve_configured=true
          fi
          return 0
        }
        When call _config_tailscale
        The status should be success
        The variable serve_configured should equal true
      End

      It "skips Tailscale Serve when TAILSCALE_WEBUI is no"
        TAILSCALE_WEBUI="no"
        serve_configured=false
        remote_run() {
          if [[ $1 == *"Tailscale Serve"* ]]; then
            serve_configured=true
          fi
          return 0
        }
        When call _config_tailscale
        The status should be success
        The variable serve_configured should equal false
      End
    End

    # -------------------------------------------------------------------------
    # Stealth mode (disable-openssh.service)
    # Test overall success/failure since mocks don't propagate to subshells
    # -------------------------------------------------------------------------
    Describe "with stealth firewall mode"
      BeforeAll 'setup_mock_template'
      AfterAll 'cleanup_mock_template'
      BeforeEach 'TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"; FIREWALL_MODE="stealth"; MOCK_REMOTE_EXEC_RESULT=0; MOCK_REMOTE_COPY_RESULT=0'

      It "succeeds with stealth mode configuration"
        When call _config_tailscale
        The status should be success
      End
    End

    Describe "with standard firewall mode"
      BeforeEach 'TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"; FIREWALL_MODE="standard"; MOCK_REMOTE_EXEC_RESULT=0'

      It "skips disable-openssh.service when not stealth"
        openssh_service_deployed=false
        remote_copy() {
          if [[ $1 == *"disable-openssh.service"* ]]; then
            openssh_service_deployed=true
          fi
          return 0
        }
        When call _config_tailscale
        The status should be success
        The variable openssh_service_deployed should equal false
      End
    End

    Describe "with unset firewall mode"
      BeforeEach 'TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"; unset FIREWALL_MODE; MOCK_REMOTE_EXEC_RESULT=0'

      It "defaults to standard (skips disable-openssh.service)"
        openssh_service_deployed=false
        remote_copy() {
          if [[ $1 == *"disable-openssh.service"* ]]; then
            openssh_service_deployed=true
          fi
          return 0
        }
        When call _config_tailscale
        The status should be success
        The variable openssh_service_deployed should equal false
      End
    End

    # -------------------------------------------------------------------------
    # Error handling in stealth mode
    # -------------------------------------------------------------------------
    Describe "error handling in stealth mode"
      BeforeAll 'setup_mock_template'
      AfterAll 'cleanup_mock_template'
      BeforeEach 'TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"; FIREWALL_MODE="stealth"'

      It "fails when background job returns failure"
        # When remote_copy fails in the background job, show_progress captures the exit code
        MOCK_REMOTE_COPY_RESULT=1
        When call _config_tailscale
        The status should be failure
      End
    End
  End

  # ===========================================================================
  # configure_tailscale() - public wrapper
  # ===========================================================================
  Describe "configure_tailscale()"
    BeforeEach 'MOCK_REMOTE_RUN_RESULT=0; MOCK_REMOTE_EXEC_RESULT=0; MOCK_REMOTE_COPY_RESULT=0; TAILSCALE_AUTH_KEY=""; TAILSCALE_WEBUI="no"; FIREWALL_MODE="standard"'

    It "skips when INSTALL_TAILSCALE is not yes"
      INSTALL_TAILSCALE="no"
      When call configure_tailscale
      The status should be success
    End

    It "skips when INSTALL_TAILSCALE is unset"
      unset INSTALL_TAILSCALE
      When call configure_tailscale
      The status should be success
    End

    It "skips when INSTALL_TAILSCALE is empty"
      INSTALL_TAILSCALE=""
      When call configure_tailscale
      The status should be success
    End

    It "configures tailscale when INSTALL_TAILSCALE is yes"
      INSTALL_TAILSCALE="yes"
      config_called=false
      _config_tailscale() { config_called=true; return 0; }
      When call configure_tailscale
      The status should be success
      The variable config_called should equal true
    End

    It "propagates failure from _config_tailscale"
      INSTALL_TAILSCALE="yes"
      _config_tailscale() { return 1; }
      When call configure_tailscale
      The status should be failure
    End

    It "passes through success from _config_tailscale"
      INSTALL_TAILSCALE="yes"
      _config_tailscale() { return 0; }
      When call configure_tailscale
      The status should be success
    End
  End
End
