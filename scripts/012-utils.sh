# shellcheck shell=bash
# General utilities
# NOTE: Many functions have been moved to specialized modules:
# - download_file → 011-downloads.sh
# - apply_template_vars, download_template → 020-templates.sh
# - generate_password → 034-password-utils.sh
# - show_progress → 010-display.sh

# Check if command exists. $1=command → 0 if available
cmd_exists() { command -v "$1" &>/dev/null; }

# Get file size in bytes (cross-platform: GNU and BSD stat). $1=file → size
_get_file_size() {
  local file="$1"
  # Try GNU stat first (-c%s), then BSD stat (-f%z)
  stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 1024
}

# Securely delete file (shred or dd fallback). $1=file_path
secure_delete_file() {
  local file="$1"

  [[ -z $file ]] && return 0
  [[ ! -f $file ]] && return 0

  if cmd_exists shred; then
    shred -u -z "$file" 2>/dev/null || rm -f "$file"
  else
    # Fallback: overwrite with zeros before deletion
    local file_size
    file_size=$(_get_file_size "$file")
    dd if=/dev/zero of="$file" bs=1 count="$file_size" conv=notrunc 2>/dev/null || true
    rm -f "$file"
  fi

  return 0
}
