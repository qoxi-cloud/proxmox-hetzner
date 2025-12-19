# shellcheck shell=bash
# shellcheck disable=SC2016
# =============================================================================
# Tests for 032-template-helpers.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"

# Mock results - must be set before Include
MOCK_DOWNLOAD_RESULT=0
MOCK_APPLY_VARS_RESULT=0
MOCK_APPLY_COMMON_RESULT=0
MOCK_VALIDATE_RESULT=0
MOCK_REMOTE_COPY_RESULT=0

# Mock functions - must be defined before Include
log() { :; }

download_template() {
  return "$MOCK_DOWNLOAD_RESULT"
}

apply_template_vars() {
  return "$MOCK_APPLY_VARS_RESULT"
}

apply_common_template_vars() {
  return "$MOCK_APPLY_COMMON_RESULT"
}

validate_template_vars() {
  return "$MOCK_VALIDATE_RESULT"
}

remote_copy() {
  return "$MOCK_REMOTE_COPY_RESULT"
}

Describe "032-template-helpers.sh"
Include "$SCRIPTS_DIR/032-template-helpers.sh"

Describe "deploy_template()"
It "succeeds with all mocks returning 0"
MOCK_DOWNLOAD_RESULT=0
MOCK_APPLY_VARS_RESULT=0
MOCK_VALIDATE_RESULT=0
MOCK_REMOTE_COPY_RESULT=0
When call deploy_template "test.tmpl" "/etc/test.conf" "VAR1=value1"
The status should be success
End

It "succeeds with common vars when no vars provided"
MOCK_DOWNLOAD_RESULT=0
MOCK_APPLY_COMMON_RESULT=0
MOCK_VALIDATE_RESULT=0
MOCK_REMOTE_COPY_RESULT=0
When call deploy_template "test.tmpl" "/etc/test.conf"
The status should be success
End

It "fails when download fails"
MOCK_DOWNLOAD_RESULT=1
When call deploy_template "test.tmpl" "/etc/test.conf"
The status should be failure
End

It "fails when validation fails"
MOCK_DOWNLOAD_RESULT=0
MOCK_APPLY_COMMON_RESULT=0
MOCK_VALIDATE_RESULT=1
When call deploy_template "test.tmpl" "/etc/test.conf"
The status should be failure
End

It "fails when remote_copy fails"
MOCK_DOWNLOAD_RESULT=0
MOCK_APPLY_COMMON_RESULT=0
MOCK_VALIDATE_RESULT=0
MOCK_REMOTE_COPY_RESULT=1
When call deploy_template "test.tmpl" "/etc/test.conf"
The status should be failure
End
End
End
