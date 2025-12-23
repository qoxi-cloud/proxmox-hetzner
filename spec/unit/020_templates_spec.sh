# shellcheck shell=bash
# shellcheck disable=SC2016
# =============================================================================
# Tests for 020-templates.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"

# Mock log function
log() { :; }

Describe "020-templates.sh"
Include "$SCRIPTS_DIR/020-templates.sh"

# ===========================================================================
# apply_template_vars()
# ===========================================================================
Describe "apply_template_vars()"
It "substitutes single variable"
template=$(mktemp)
echo "hostname = {{HOSTNAME}}" >"$template"
When call apply_template_vars "$template" "HOSTNAME=pve-test"
The status should be success
The contents of file "$template" should equal "hostname = pve-test"
rm -f "$template"
End

It "substitutes multiple variables"
template=$(mktemp)
echo "host={{HOST}} gw={{GW}}" >"$template"
When call apply_template_vars "$template" "HOST=server" "GW=192.168.1.1"
The status should be success
The contents of file "$template" should equal "host=server gw=192.168.1.1"
rm -f "$template"
End

It "fails for non-existent file"
When call apply_template_vars "/nonexistent/file.txt" "VAR=value"
The status should be failure
End

It "handles variables with special characters in value"
template=$(mktemp)
echo "path={{PATH}}" >"$template"
When call apply_template_vars "$template" "PATH=/usr/local/bin"
The status should be success
The contents of file "$template" should equal "path=/usr/local/bin"
rm -f "$template"
End

It "allows empty value substitution"
template=$(mktemp)
echo "var={{VAR}}" >"$template"
When call apply_template_vars "$template" "VAR="
The status should be success
The contents of file "$template" should equal "var="
rm -f "$template"
End

It "fails when unmatched placeholders remain"
template=$(mktemp)
echo "a={{A}} b={{B}}" >"$template"
When call apply_template_vars "$template" "A=1"
The status should be failure
rm -f "$template"
End
End
End
