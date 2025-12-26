# shellcheck shell=bash
# Parallel execution helpers for faster installation

# Install all base system packages in one batch
install_base_packages() {
  # shellcheck disable=SC2086
  local packages="${SYSTEM_UTILITIES} ${OPTIONAL_PACKAGES} locales chrony unattended-upgrades apt-listchanges linux-cpupower"

  # Add ZSH packages if needed
  if [[ ${SHELL_TYPE:-bash} == "zsh" ]]; then
    packages="$packages zsh git"
  fi

  log "Installing base packages: $packages"

  remote_run "Installing system packages" "
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get dist-upgrade -yqq
    apt-get install -yqq $packages
    apt-get autoremove -yqq
    apt-get clean
    set +e
    pveupgrade 2>/dev/null || echo 'pveupgrade check skipped' >&2
    pveam update 2>/dev/null || echo 'pveam update skipped' >&2
  " "System packages installed"

  # Show installed packages as subtasks
  # shellcheck disable=SC2086
  log_subtasks $packages
}

# Collect and install all feature packages in one batch
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
  [[ $INSTALL_CHKROOTKIT == "yes" ]] && packages+=(chkrootkit binutils)
  [[ $INSTALL_LYNIS == "yes" ]] && packages+=(lynis)
  [[ $INSTALL_NEEDRESTART == "yes" ]] && packages+=(needrestart)

  # Monitoring packages
  [[ $INSTALL_VNSTAT == "yes" ]] && packages+=(vnstat)
  [[ $INSTALL_PROMTAIL == "yes" ]] && packages+=(promtail)
  [[ $INSTALL_NETDATA == "yes" ]] && packages+=(netdata)

  # Tools packages
  [[ $INSTALL_NVIM == "yes" ]] && packages+=(neovim)
  [[ $INSTALL_RINGBUFFER == "yes" ]] && packages+=(ethtool)
  [[ $INSTALL_YAZI == "yes" ]] && packages+=(file unzip)

  # Tailscale (needs custom repo)
  [[ $INSTALL_TAILSCALE == "yes" ]] && packages+=(tailscale)

  # SSL packages
  [[ ${SSL_TYPE:-self-signed} == "letsencrypt" ]] && packages+=(certbot)

  if [[ ${#packages[@]} -eq 0 ]]; then
    log "No optional packages to install"
    return 0
  fi

  log "Batch installing packages: ${packages[*]}"

  # Build repo setup commands for packages needing custom repos
  # Detect Debian codename dynamically to support future releases (trixie, etc.)
  # shellcheck disable=SC2016
  local repo_setup='
    DEBIAN_CODENAME=$(grep -oP "VERSION_CODENAME=\K\w+" /etc/os-release 2>/dev/null || echo "bookworm")
  '

  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    # shellcheck disable=SC2016
    repo_setup+='
      curl -fsSL "https://pkgs.tailscale.com/stable/debian/${DEBIAN_CODENAME}.noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
      curl -fsSL "https://pkgs.tailscale.com/stable/debian/${DEBIAN_CODENAME}.tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list
    '
  fi

  if [[ $INSTALL_NETDATA == "yes" ]]; then
    # shellcheck disable=SC2016
    repo_setup+='
      curl -fsSL https://repo.netdata.cloud/netdatabot.gpg.key | gpg --dearmor -o /usr/share/keyrings/netdata-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/netdata-archive-keyring.gpg] https://repo.netdata.cloud/repos/stable/debian/ ${DEBIAN_CODENAME}/" > /etc/apt/sources.list.d/netdata.list
    '
  fi

  if [[ $INSTALL_PROMTAIL == "yes" ]]; then
    repo_setup+='
      curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
    '
  fi

  # Use remote_run for reliable execution (pipes script to bash -s, better for long scripts)
  # remote_run exits on failure, so no need for error handling here
  # shellcheck disable=SC2086
  remote_run "Installing packages (${#packages[@]})" '
      set -e
      export DEBIAN_FRONTEND=noninteractive
      '"$repo_setup"'
      apt-get update -qq
      apt-get install -yqq '"${packages[*]}"'
    ' "Packages installed"

  # Show installed packages as subtasks
  log_subtasks "${packages[@]}"

  return 0
}

# Internal: run single task in parallel group. $1=result_dir, $2=idx, $3=func
_run_parallel_task() {
  local result_dir="$1"
  local idx="$2"
  local func="$3"

  # Override show_progress to silent waiter to prevent TUI race conditions.
  # Each subshell has its own copy of LOG_LINES array and live_show_progress
  # writes to /dev/tty (bypassing >/dev/null). Multiple subshells racing to
  # redraw causes flickering and corruption. Parent handles group progress.
  # shellcheck disable=SC2317
  show_progress() {
    wait "$1" 2>/dev/null
    return $?
  }

  # Default to failure marker on ANY exit (handles remote_run's exit 1)
  # shellcheck disable=SC2064
  trap "touch '$result_dir/fail_$idx' 2>/dev/null" EXIT

  if "$func" >/dev/null 2>&1; then
    trap - EXIT # Clear trap on success
    touch "$result_dir/success_$idx"
  fi
}

# Run config functions in parallel. $1=name, $2=done_msg, $@=functions
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
  export PARALLEL_RESULT_DIR="$result_dir"
  # shellcheck disable=SC2064
  trap "rm -rf '$result_dir'" RETURN

  # Start all functions in background, each writes result to file
  # Use trap to ensure marker created even if function calls exit 1 (like remote_run)
  # NOTE: Each subshell gets its own copy of variables at fork time.
  # We pass idx as function argument to guarantee correct value capture.
  local i=0
  for func in "${funcs[@]}"; do
    _run_parallel_task "$result_dir" "$i" "$func" &
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
      sleep "${PROGRESS_POLL_INTERVAL:-0.2}"
    done
  ) &
  show_progress $! "$group_name" "$done_msg"

  # Collect configured features for display
  local configured=()
  for f in "$result_dir"/ran_*; do
    [[ -f $f ]] && configured+=("$(cat "$f")")
  done

  # Show configured features as subtasks
  if [[ ${#configured[@]} -gt 0 ]]; then
    log_subtasks "${configured[@]}"
  fi

  # Check for failures
  local failures=0
  for j in $(seq 0 $((count - 1))); do
    [[ -f "$result_dir/fail_$j" ]] && ((failures++))
  done

  if [[ $failures -gt 0 ]]; then
    log "ERROR: $failures/$count functions failed in group '$group_name'"
    return $failures
  fi

  return 0
}

# Mark feature as configured in parallel group. $1=feature name
parallel_mark_configured() {
  local feature="$1"
  [[ -n ${PARALLEL_RESULT_DIR:-} ]] && printf '%s' "$feature" >"$PARALLEL_RESULT_DIR/ran_$BASHPID"
}
