# shellcheck shell=bash
# Cleanup and error handling

# Temp file registry for cleanup on exit
# Array to track temp files for cleanup on script exit
_TEMP_FILES=()

# Register temp file for cleanup on exit. $1=path
register_temp_file() {
  _TEMP_FILES+=("$1")
}

# Clean up temp files, secure delete secrets
cleanup_temp_files() {
  # Clean up registered temp files (from register_temp_file)
  for f in "${_TEMP_FILES[@]}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done

  # Use INSTALL_DIR with fallback for early cleanup calls
  local install_dir="${INSTALL_DIR:-${HOME:-/root}}"

  # Current session PID for scoped cleanup (only delete our own files)
  local pid="$$"

  # Secure delete files containing secrets (API token, root password)
  # secure_delete_file is defined in 012-utils.sh, check if available
  if type secure_delete_file &>/dev/null; then
    secure_delete_file /tmp/pve-install-api-token.env
    secure_delete_file "${install_dir}/answer.toml"
    # Secure delete password files - only current session (PID-scoped)
    secure_delete_file "/dev/shm/pve-ssh-session.${pid}"
    secure_delete_file "/tmp/pve-ssh-session.${pid}"
    # Legacy passfile patterns (also PID-scoped)
    secure_delete_file "/dev/shm/pve-passfile.${pid}"
    secure_delete_file "/tmp/pve-passfile.${pid}"
  else
    # Fallback if secure_delete_file not yet loaded (early exit)
    rm -f /tmp/pve-install-api-token.env 2>/dev/null || true
    rm -f "${install_dir}/answer.toml" 2>/dev/null || true
    rm -f "/dev/shm/pve-ssh-session.${pid}" "/tmp/pve-ssh-session.${pid}" 2>/dev/null || true
    rm -f "/dev/shm/pve-passfile.${pid}" "/tmp/pve-passfile.${pid}" 2>/dev/null || true
  fi

  # Clean up standard temporary files (non-sensitive, PID-scoped where applicable)
  rm -f /tmp/tailscale_*.txt /tmp/iso_checksum.txt /tmp/*.tmp 2>/dev/null || true

  # Clean up SSH control socket (current session only)
  rm -f "/tmp/ssh-pve-control.${pid}" 2>/dev/null || true

  # Clean up ISO and installation files (only if installation failed)
  if [[ $INSTALL_COMPLETED != "true" ]]; then
    rm -f "${install_dir}/pve.iso" "${install_dir}/pve-autoinstall.iso" "${install_dir}/SHA256SUMS" 2>/dev/null || true
    rm -f "${install_dir}"/qemu_*.log 2>/dev/null || true
  fi
}

# EXIT trap: cleanup processes, drives, cursor, show error if failed
cleanup_and_error_handler() {
  local exit_code=$?

  # Stop all background jobs
  jobs -p | xargs -r kill 2>/dev/null || true
  sleep "${PROCESS_KILL_WAIT:-1}"

  # Clean up SSH session passfile
  if type _ssh_session_cleanup &>/dev/null; then
    _ssh_session_cleanup
  fi

  # Clean up temporary files
  cleanup_temp_files

  # Release drives if QEMU is still running
  if [[ -n ${QEMU_PID:-} ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
    log "Cleaning up QEMU process $QEMU_PID"
    # Source release_drives if available (may not be sourced yet)
    if type release_drives &>/dev/null; then
      release_drives
    else
      # Fallback cleanup
      pkill -TERM qemu-system-x86 2>/dev/null || true
      sleep "${RETRY_DELAY_SECONDS:-2}"
      pkill -9 qemu-system-x86 2>/dev/null || true
    fi
  fi

  # Exit alternate screen buffer and restore cursor visibility
  tput rmcup 2>/dev/null || true
  tput cnorm 2>/dev/null || true

  # Show error message if installation failed
  if [[ $INSTALL_COMPLETED != "true" && $exit_code -ne 0 ]]; then
    printf '%s\n' "${CLR_RED}*** INSTALLATION FAILED ***${CLR_RESET}"
    printf '\n'
    printf '%s\n' "${CLR_YELLOW}An error occurred and the installation was aborted.${CLR_RESET}"
    printf '\n'
    printf '%s\n' "${CLR_YELLOW}Please check the log file for details:${CLR_RESET}"
    printf '%s\n' "${CLR_YELLOW}  ${LOG_FILE}${CLR_RESET}"
    printf '\n'
  fi
}

trap cleanup_and_error_handler EXIT
