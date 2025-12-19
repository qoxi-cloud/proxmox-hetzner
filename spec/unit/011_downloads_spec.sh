# shellcheck shell=bash
# shellcheck disable=SC2016
# =============================================================================
# Tests for 011-downloads.sh
# =============================================================================

%const SCRIPTS_DIR: "${SHELLSPEC_PROJECT_ROOT}/scripts"

# Mock control variables
MOCK_WGET_FAIL=false
MOCK_WGET_EMPTY=false

# Mock functions - defined before Include
log() { :; }
print_error() { :; }
print_warning() { :; }

# Override wget
wget() {
  local output_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -O)
        output_file="$2"
        shift 2
        ;;
      -q) shift ;;
      *) shift ;;
    esac
  done

  if [[ "$MOCK_WGET_FAIL" == "true" ]]; then
    return 1
  fi

  if [[ -n "$output_file" ]]; then
    if [[ "$MOCK_WGET_EMPTY" == "true" ]]; then
      : >"$output_file"
    else
      echo "mock file content" >"$output_file"
    fi
  fi
  return 0
}

# Override file command
file() {
  local filepath="$1"
  if [[ -s "$filepath" ]]; then
    echo "$filepath: ASCII text"
  else
    echo "$filepath: empty"
  fi
}

Describe "011-downloads.sh"
Include "$SCRIPTS_DIR/011-downloads.sh"

Describe "download_file()"
It "downloads file successfully"
MOCK_WGET_FAIL=false
MOCK_WGET_EMPTY=false
DOWNLOAD_RETRY_COUNT=1
DOWNLOAD_RETRY_DELAY=0
tmpfile=$(mktemp)
When call download_file "$tmpfile" "http://example.com/file.txt"
The status should be success
The contents of file "$tmpfile" should include "mock"
rm -f "$tmpfile"
End

It "returns failure when wget fails after retries"
MOCK_WGET_FAIL=true
DOWNLOAD_RETRY_COUNT=2
DOWNLOAD_RETRY_DELAY=0
tmpfile=$(mktemp)
When call download_file "$tmpfile" "http://example.com/file.txt"
The status should be failure
rm -f "$tmpfile"
End

It "retries on empty file"
MOCK_WGET_FAIL=false
MOCK_WGET_EMPTY=true
DOWNLOAD_RETRY_COUNT=2
DOWNLOAD_RETRY_DELAY=0
tmpfile=$(mktemp)
When call download_file "$tmpfile" "http://example.com/file.txt"
The status should be failure
rm -f "$tmpfile"
End
End
End
