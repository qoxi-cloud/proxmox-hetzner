# shellcheck shell=bash
# =============================================================================
# Tests for 010-display.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"

# Set up colors before including script
CLR_RED=$'\033[1;31m'
CLR_GREEN=$'\033[1;32m'
CLR_CYAN=$'\033[38;2;0;177;255m'
CLR_YELLOW=$'\033[1;33m'
CLR_RESET=$'\033[m'

Describe "010-display.sh"
Include "$SCRIPTS_DIR/010-display.sh"

# ===========================================================================
# print_success()
# ===========================================================================
Describe "print_success()"
It "prints message"
When call print_success "Operation completed"
The output should include "Operation completed"
End

It "prints label and value when two args"
When call print_success "Status:" "OK"
The output should include "Status:"
The output should include "OK"
End

It "handles empty message"
When call print_success ""
The status should be success
The output should be present
End
End

# ===========================================================================
# print_error()
# ===========================================================================
Describe "print_error()"
It "prints error message"
When call print_error "Something failed"
The output should include "Something failed"
End

It "prints message with colon"
When call print_error "Error: File not found"
The output should include "Error: File not found"
End
End

# ===========================================================================
# print_warning()
# ===========================================================================
Describe "print_warning()"
It "prints warning message"
When call print_warning "Caution advised"
The output should include "Caution advised"
End

It "handles special characters"
When call print_warning "Warning: disk 90% full!"
The output should include "disk 90% full"
End
End

# ===========================================================================
# print_info()
# ===========================================================================
Describe "print_info()"
It "prints info message"
When call print_info "For your information"
The output should include "For your information"
End

It "prints message with colon"
When call print_info "Version: 1.0.0"
The output should include "Version: 1.0.0"
End
End
End
