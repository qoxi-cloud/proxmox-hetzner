# shellcheck shell=bash
# =============================================================================
# Parallel execution helpers for faster installation
# =============================================================================

# Collects packages needed by enabled features and installs them in one batch.
# This eliminates redundant apt-get update calls across configure scripts.
# Must be called BEFORE running parallel config groups.
# Side effects: Installs packages on remote system
batch_install_packages() {
  local packages=()

  # Security packages
  [[ $INSTALL_FIREWALL == "yes" ]] && packages+=(nftables)
  if [[ $INSTALL_FIREWALL == "yes" && ${FIREWALL_MODE:-standard} != "stealth" ]]; then
    packages+=(fail2ban)
  fi
  [[ $INSTALL_APPARMOR == "yes" ]] && packages+=(apparmor apparmor-utils)
  [[ $INSTALL_AUDITD == "yes" ]] && packages+=(auditd audispd-plugins)
  [[ $INSTALL_AIDE == "yes" ]] && packages+=(aide aide-common)
  [[ $INSTALL_CHKROOTKIT == "yes" ]] && packages+=(chkrootkit)
  [[ $INSTALL_LYNIS == "yes" ]] && packages+=(lynis)
  [[ $INSTALL_NEEDRESTART == "yes" ]] && packages+=(needrestart)

  # Monitoring packages
  [[ $INSTALL_VNSTAT == "yes" ]] && packages+=(vnstat)
  [[ $INSTALL_PROMETHEUS == "yes" ]] && packages+=(prometheus-node-exporter)
  # Netdata installed via script, not apt

  # Tools packages
  [[ $INSTALL_NVIM == "yes" ]] && packages+=(neovim)
  [[ $INSTALL_RINGBUFFER == "yes" ]] && packages+=(ethtool)
  # Yazi installed via cargo

  if [[ ${#packages[@]} -eq 0 ]]; then
    log "No optional packages to install"
    return 0
  fi

  log "Batch installing packages: ${packages[*]}"

  (
    # shellcheck disable=SC2086,SC2016
    remote_exec '
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -yqq '"${packages[*]}"'
    ' || exit 1
  ) >/dev/null 2>&1 &
  show_progress $! "Installing packages (${#packages[@]})" "Packages installed"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "WARNING: Batch package installation failed"
    return 1
  fi
  return 0
}

# Runs multiple config functions in parallel with a single progress indicator.
# All functions run silently; only one progress line shown for the group.
# Skips disabled features (functions return 0 immediately).
# Parameters:
#   $1 - Group name for progress display
#   $2 - Done message
#   $@ - Function names to run in parallel
# Returns: 0 if all succeed, 1 if any fail (non-fatal)
# Side effects: Runs provided functions, shows single progress line
run_parallel_group() {
  local group_name="$1"
  local done_msg="$2"
  shift 2
  local funcs=("$@")

  if [[ ${#funcs[@]} -eq 0 ]]; then
    log "No functions to run in parallel group: $group_name"
    return 0
  fi

  log "Running parallel group '$group_name' with functions: ${funcs[*]}"

  # Track results via temp files (avoid subshell variable issues)
  local result_dir
  result_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$result_dir'" RETURN

  # Start all functions in background, each writes result to file
  local i=0
  for func in "${funcs[@]}"; do
    (
      if "$func" 2>&1; then
        touch "$result_dir/success_$i"
      else
        touch "$result_dir/fail_$i"
      fi
    ) >/dev/null &
    ((i++))
  done

  local count=$i

  # Wait for all with single progress
  (
    while true; do
      local done_count=0
      for j in $(seq 0 $((count - 1))); do
        [[ -f "$result_dir/success_$j" || -f "$result_dir/fail_$j" ]] && ((done_count++))
      done
      [[ $done_count -eq $count ]] && break
      sleep 0.2
    done
  ) &
  show_progress $! "$group_name" "$done_msg"

  # Check for failures
  local failures=0
  for j in $(seq 0 $((count - 1))); do
    [[ -f "$result_dir/fail_$j" ]] && ((failures++))
  done

  if [[ $failures -gt 0 ]]; then
    log "WARNING: $failures/$count functions failed in group '$group_name'"
    return 0 # Non-fatal
  fi

  return 0
}

# Collects function names based on enabled features.
# Parameters:
#   $1 - Variable name to store result array
#   $@ - Pairs of "INSTALL_VAR:function_name"
# Example: collect_enabled_funcs result_array "INSTALL_FIREWALL:_config_nftables" "INSTALL_AIDE:_config_aide"
collect_enabled_funcs() {
  local -n result_arr=$1
  shift
  result_arr=()

  for pair in "$@"; do
    local var="${pair%%:*}"
    local func="${pair#*:}"
    if [[ ${!var} == "yes" ]]; then
      result_arr+=("$func")
    fi
  done
}
