# shellcheck shell=bash
# shellcheck disable=SC2034
# =============================================================================
# Tests for 341-configure-promtail.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"
%const SUPPORT_DIR: "${SHELLSPEC_PROJECT_ROOT}/spec/support"

# Load shared mocks
eval "$(cat "$SUPPORT_DIR/configure_mocks.sh")"

Describe "341-configure-promtail.sh"
Include "$SCRIPTS_DIR/341-configure-promtail.sh"

# ===========================================================================
# _config_promtail()
# ===========================================================================
Describe "_config_promtail()"
It "deploys config and service"
MOCK_REMOTE_COPY_RESULT=0
MOCK_REMOTE_EXEC_RESULT=0
When call _config_promtail
The status should be success
End

It "fails when remote_exec fails"
MOCK_REMOTE_COPY_RESULT=0
MOCK_REMOTE_EXEC_RESULT=1
When call _config_promtail
The status should be failure
End
End
End
