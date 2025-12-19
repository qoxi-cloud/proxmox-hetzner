# shellcheck shell=bash
# =============================================================================
# Tests for 031-feature-installer.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"

# Mocks
log() { :; }
print_error() { echo "ERROR: $*" >&2; }
print_warning() { echo "WARNING: $*"; }
show_progress() {
  wait "$1" 2>/dev/null
  return $?
}

# Test functions
test_install_success() { return 0; }
test_install_fail() { return 1; }
test_config_success() { return 0; }
test_config_fail() { return 1; }
test_install_slow() {
  sleep 0.1
  return 0
}

Describe "031-feature-installer.sh"
Include "$SCRIPTS_DIR/031-feature-installer.sh"

# ===========================================================================
# install_optional_feature()
# ===========================================================================
Describe "install_optional_feature()"
It "skips when install var is not 'yes'"
INSTALL_TEST="no"
When call install_optional_feature "Test Feature" "INSTALL_TEST" "test_install_success" "test_config_success"
The status should be success
End

It "skips when install var is empty"
INSTALL_TEST=""
When call install_optional_feature "Test Feature" "INSTALL_TEST" "test_install_success" "test_config_success"
The status should be success
End

It "runs install and config when enabled"
INSTALL_TEST="yes"
When call install_optional_feature "Test Feature" "INSTALL_TEST" "test_install_success" "test_config_success" "TEST_INSTALLED"
The status should be success
The variable TEST_INSTALLED should equal "yes"
End

It "fails when install function fails"
INSTALL_TEST="yes"
When call install_optional_feature "Test Feature" "INSTALL_TEST" "test_install_fail" "test_config_success"
The status should be failure
The stderr should include "installation failed"
End

It "continues when config fails (non-fatal)"
INSTALL_TEST="yes"
When call install_optional_feature "Test Feature" "INSTALL_TEST" "test_install_success" "test_config_fail"
The status should be success
The output should include "configuration failed"
End

It "works without installed_var parameter"
INSTALL_NOFLAG="yes"
When call install_optional_feature "NoFlag" "INSTALL_NOFLAG" "test_install_success" "test_config_success"
The status should be success
End
End

# ===========================================================================
# install_optional_feature_with_progress()
# ===========================================================================
Describe "install_optional_feature_with_progress()"
It "skips when disabled"
INSTALL_PROGRESS="no"
When call install_optional_feature_with_progress "Progress Test" "INSTALL_PROGRESS" "test_install_success" "test_config_success"
The status should be success
End

It "runs with progress when enabled"
INSTALL_PROGRESS="yes"
When call install_optional_feature_with_progress "Progress Test" "INSTALL_PROGRESS" "test_install_success" "test_config_success" "PROGRESS_INSTALLED"
The status should be success
The variable PROGRESS_INSTALLED should equal "yes"
End

It "handles slow install"
INSTALL_SLOW="yes"
When call install_optional_feature_with_progress "Slow Test" "INSTALL_SLOW" "test_install_slow" "test_config_success" "SLOW_INSTALLED"
The status should be success
The variable SLOW_INSTALLED should equal "yes"
End
End
End
