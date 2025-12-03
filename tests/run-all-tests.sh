#!/usr/bin/env bash
# =============================================================================
# Run all unit tests
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track results
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_SUITES=()

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}       Running All Unit Tests${NC}"
echo -e "${CYAN}=================================================${NC}"

# Find all test files
# Find all test files
test_files=(
    "$SCRIPT_DIR/test-validation.sh"
    "$SCRIPT_DIR/test-utils.sh"
    "$SCRIPT_DIR/test-ssh.sh"
    "$SCRIPT_DIR/test-config.sh"
    "$SCRIPT_DIR/test-wizard-core.sh"
    "$SCRIPT_DIR/test-wizard-inputs.sh"
    "$SCRIPT_DIR/test-wizard-fields.sh"
    "$SCRIPT_DIR/test-wizard-steps.sh"
    "$SCRIPT_DIR/test-wizard-main.sh"
    "$SCRIPT_DIR/test-main.sh"
)
    "$SCRIPT_DIR/test-wizard-inputs.sh"
    "$SCRIPT_DIR/test-wizard-fields.sh"
    "$SCRIPT_DIR/test-wizard-steps.sh"
    "$SCRIPT_DIR/test-wizard-main.sh"
    "$SCRIPT_DIR/test-main.sh"
)
# Find all test files
test_files=(
    "$SCRIPT_DIR/test-validation.sh"
    "$SCRIPT_DIR/test-utils.sh"
    "$SCRIPT_DIR/test-ssh.sh"
    "$SCRIPT_DIR/test-config.sh"
    "$SCRIPT_DIR/test-wizard-core.sh"
    "$SCRIPT_DIR/test-wizard-inputs.sh"
    "$SCRIPT_DIR/test-wizard-fields.sh"
    "$SCRIPT_DIR/test-wizard-steps.sh"
    "$SCRIPT_DIR/test-wizard-main.sh"
    "$SCRIPT_DIR/test-main.sh"
)
# Find all test files
test_files=(
    "$SCRIPT_DIR/test-validation.sh"
    "$SCRIPT_DIR/test-utils.sh"
    "$SCRIPT_DIR/test-ssh.sh"
    "$SCRIPT_DIR/test-config.sh"
    "$SCRIPT_DIR/test-wizard-core.sh"
    "$SCRIPT_DIR/test-wizard-inputs.sh"
    "$SCRIPT_DIR/test-wizard-fields.sh"
    "$SCRIPT_DIR/test-wizard-steps.sh"
    "$SCRIPT_DIR/test-wizard-main.sh"
    "$SCRIPT_DIR/test-main.sh"
)
# Find all test files
test_files=(
    "$SCRIPT_DIR/test-validation.sh"
    "$SCRIPT_DIR/test-utils.sh"
    "$SCRIPT_DIR/test-ssh.sh"
    "$SCRIPT_DIR/test-config.sh"
    "$SCRIPT_DIR/test-wizard-core.sh"
    "$SCRIPT_DIR/test-wizard-inputs.sh"
    "$SCRIPT_DIR/test-wizard-fields.sh"
    "$SCRIPT_DIR/test-wizard-steps.sh"
    "$SCRIPT_DIR/test-wizard-main.sh"
    "$SCRIPT_DIR/test-main.sh"
)
# Find all test files
test_files=(
    "$SCRIPT_DIR/test-validation.sh"
    "$SCRIPT_DIR/test-utils.sh"
    "$SCRIPT_DIR/test-ssh.sh"
    "$SCRIPT_DIR/test-config.sh"
    "$SCRIPT_DIR/test-wizard-core.sh"
    "$SCRIPT_DIR/test-wizard-inputs.sh"
    "$SCRIPT_DIR/test-wizard-fields.sh"
    "$SCRIPT_DIR/test-wizard-steps.sh"
    "$SCRIPT_DIR/test-wizard-main.sh"
    "$SCRIPT_DIR/test-main.sh"
)
# Find all test files
test_files=(
    "$SCRIPT_DIR/test-validation.sh"
    "$SCRIPT_DIR/test-utils.sh"
    "$SCRIPT_DIR/test-ssh.sh"
    "$SCRIPT_DIR/test-config.sh"
    "$SCRIPT_DIR/test-wizard-core.sh"
    "$SCRIPT_DIR/test-wizard-inputs.sh"
    "$SCRIPT_DIR/test-wizard-fields.sh"
    "$SCRIPT_DIR/test-wizard-steps.sh"
    "$SCRIPT_DIR/test-wizard-main.sh"
    "$SCRIPT_DIR/test-main.sh"
)
# Find all test files
test_files=(
    "$SCRIPT_DIR/test-validation.sh"
    "$SCRIPT_DIR/test-utils.sh"
    "$SCRIPT_DIR/test-ssh.sh"
    "$SCRIPT_DIR/test-config.sh"
    "$SCRIPT_DIR/test-wizard-core.sh"
    "$SCRIPT_DIR/test-wizard-inputs.sh"
    "$SCRIPT_DIR/test-wizard-fields.sh"
    "$SCRIPT_DIR/test-wizard-steps.sh"
    "$SCRIPT_DIR/test-wizard-main.sh"
    "$SCRIPT_DIR/test-main.sh"
)

for test_file in "${test_files[@]}"; do
    if [[ ! -f "$test_file" ]]; then
        echo -e "${YELLOW}Skipping: $test_file (not found)${NC}"
        continue
    fi

    test_name=$(basename "$test_file" .sh)
    echo -e "\n${CYAN}Running: $test_name${NC}"
    echo -e "${CYAN}$(printf '%.0s-' {1..50})${NC}"

    # Run test and capture output
    set +e
    output=$("$test_file" 2>&1)
    exit_code=$?
    set -e

    echo "$output"

    # Extract summary from output
    if echo "$output" | grep -q "Tests run:"; then
        tests=$(echo "$output" | grep "Tests run:" | tail -1 | grep -oE '[0-9]+' | head -1)
        passed=$(echo "$output" | grep "Passed:" | tail -1 | grep -oE '[0-9]+' | head -1)
        failed=$(echo "$output" | grep "Failed:" | tail -1 | grep -oE '[0-9]+' | head -1)

        TOTAL_TESTS=$((TOTAL_TESTS + ${tests:-0}))
        TOTAL_PASSED=$((TOTAL_PASSED + ${passed:-0}))
        TOTAL_FAILED=$((TOTAL_FAILED + ${failed:-0}))
    fi

    if [[ $exit_code -ne 0 ]]; then
        FAILED_SUITES+=("$test_name")
    fi
done

# Print overall summary
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}              Overall Summary${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "Total tests run: ${YELLOW}$TOTAL_TESTS${NC}"
echo -e "Total passed:    ${GREEN}$TOTAL_PASSED${NC}"
echo -e "Total failed:    ${RED}$TOTAL_FAILED${NC}"

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    echo -e "\n${RED}Failed test suites:${NC}"
    for suite in "${FAILED_SUITES[@]}"; do
        echo -e "  ${RED}✗${NC} $suite"
    done
    echo -e "${CYAN}=================================================${NC}"
    exit 1
else
    echo -e "\n${GREEN}All tests passed!${NC}"
    echo -e "${CYAN}=================================================${NC}"
    exit 0
fi
