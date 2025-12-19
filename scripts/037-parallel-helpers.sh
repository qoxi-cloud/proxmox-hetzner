# shellcheck shell=bash
# =============================================================================
# Parallel execution helpers for faster installation
# =============================================================================

# Installs all base system packages in one batch.
# Called at the start of configure_base_system().
# Includes: SYSTEM_UTILITIES, locales, chrony, unattended-upgrades, cpufrequtils
# And conditionally: zsh/git/curl (if SHELL_TYPE=zsh)
# Side effects: Runs apt-get update and installs packages on remote system
install_base_packages() {
  # shellcheck disable=SC2086
  local packages="${SYSTEM_UTILITIES} ${OPTIONAL_PACKAGES} locales chrony unattended-upgrades apt-listchanges cpufrequtils"

  # Add ZSH packages if needed
  if [[ ${SHELL_TYPE:-bash} == "zsh" ]]; then
    packages="$packages zsh git curl"
  fi

  log "Installing base packages: $packages"

  run_remote "Installing system packages" "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get dist-upgrade -yqq
    apt-get install -yqq $packages
    apt-get autoremove -yqq
    apt-get clean
    pveupgrade 2>/dev/null || true
    pveam update 2>/dev/null || true
  " "System packages installed"
}

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
  [[ $INSTALL_NETDATA == "yes" ]] && packages+=(netdata)

  # Tools packages
  [[ $INSTALL_NVIM == "yes" ]] && packages+=(neovim)
  [[ $INSTALL_RINGBUFFER == "yes" ]] && packages+=(ethtool)
  [[ $INSTALL_YAZI == "yes" ]] && packages+=(curl file unzip)

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
  local repo_setup=""

  if [[ $INSTALL_TAILSCALE == "yes" ]]; then
    repo_setup+='
      curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
      curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
    '
  fi

  if [[ $INSTALL_NETDATA == "yes" ]]; then
    repo_setup+='
      curl -fsSL https://repo.netdata.cloud/netdatabot.gpg.key | gpg --dearmor -o /usr/share/keyrings/netdata-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/netdata-archive-keyring.gpg] https://repo.netdata.cloud/repos/stable/debian/ bookworm/" > /etc/apt/sources.list.d/netdata.list
    '
  fi

  (
    # shellcheck disable=SC2086,SC2016
    remote_exec '
      export DEBIAN_FRONTEND=noninteractive
      '"$repo_setup"'
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
