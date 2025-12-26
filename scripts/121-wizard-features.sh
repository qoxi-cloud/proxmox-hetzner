# shellcheck shell=bash
# Configuration Wizard - Shell, Power, and Features Editors
# shell, power_profile, features (security, monitoring, tools)

# Edits default shell for root user.
# Options: zsh (with Powerlevel10k) or bash.
# Updates SHELL_TYPE global.
_edit_shell() {
  _wiz_start_edit

  _wiz_description \
    "  Default shell for root user:" \
    "" \
    "  {{cyan:ZSH}}:  Modern shell with Powerlevel10k prompt" \
    "  {{cyan:Bash}}: Standard shell (minimal changes)" \
    ""

  # 1 header + 2 items for gum choose
  _show_input_footer "filter" 3

  _wiz_choose_mapped "SHELL_TYPE" "Shell:" \
    "${WIZ_MAP_SHELL[@]}"
}

# Edits CPU frequency scaling governor.
# Dynamically detects available governors from sysfs.
# Updates CPU_GOVERNOR global.
_edit_power_profile() {
  _wiz_start_edit

  # Detect available governors from sysfs
  local avail_governors=""
  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]]; then
    avail_governors=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
  fi

  # Build dynamic options based on available governors
  local options=()
  local descriptions=()

  # Always show Performance if available
  if [[ -z $avail_governors ]] || printf '%s\n' "$avail_governors" | grep -qw "performance"; then
    options+=("Performance")
    descriptions+=("  {{cyan:Performance}}:  Max frequency (highest power)")
  fi

  # Show governor-specific options
  if printf '%s\n' "$avail_governors" | grep -qw "ondemand"; then
    options+=("Balanced")
    descriptions+=("  {{cyan:Balanced}}:     Scale based on load")
  elif printf '%s\n' "$avail_governors" | grep -qw "powersave"; then
    # intel_pstate powersave is actually dynamic scaling
    options+=("Balanced")
    descriptions+=("  {{cyan:Balanced}}:     Dynamic scaling (power efficient)")
  fi

  if printf '%s\n' "$avail_governors" | grep -qw "schedutil"; then
    options+=("Adaptive")
    descriptions+=("  {{cyan:Adaptive}}:     Kernel-managed scaling")
  fi

  if printf '%s\n' "$avail_governors" | grep -qw "conservative"; then
    options+=("Conservative")
    descriptions+=("  {{cyan:Conservative}}: Gradual frequency changes")
  fi

  # Fallback if no governors detected
  if [[ ${#options[@]} -eq 0 ]]; then
    options=("Performance" "Balanced")
    descriptions=(
      "  {{cyan:Performance}}:  Max frequency (highest power)"
      "  {{cyan:Balanced}}:     Dynamic scaling (power efficient)"
    )
  fi

  _wiz_description \
    "  CPU frequency scaling governor:" \
    "" \
    "${descriptions[@]}" \
    ""

  # 1 header + N items for gum choose
  _show_input_footer "filter" $((${#options[@]} + 1))

  local options_str
  options_str=$(printf '%s\n' "${options[@]}")

  local selected
  if ! selected=$(printf '%s\n' "$options_str" | _wiz_choose --header="Power profile:"); then
    return
  fi

  case "$selected" in
    "Performance") CPU_GOVERNOR="performance" ;;
    "Balanced")
      # Use ondemand if available, otherwise powersave
      if printf '%s\n' "$avail_governors" | grep -qw "ondemand"; then
        CPU_GOVERNOR="ondemand"
      else
        CPU_GOVERNOR="powersave"
      fi
      ;;
    "Adaptive") CPU_GOVERNOR="schedutil" ;;
    "Conservative") CPU_GOVERNOR="conservative" ;;
  esac
}

# Features - Security

# Edits security feature toggles via multi-select checkbox.
# Options: apparmor, auditd, aide, chkrootkit, lynis, needrestart.
# Updates corresponding INSTALL_* globals.
_edit_features_security() {
  _wiz_start_edit

  _wiz_description \
    "  Security features (use Space to toggle):" \
    "" \
    "  {{cyan:apparmor}}:    Mandatory access control (MAC)" \
    "  {{cyan:auditd}}:      Security audit logging" \
    "  {{cyan:aide}}:        File integrity monitoring (daily)" \
    "  {{cyan:chkrootkit}}:  Rootkit scanning (weekly)" \
    "  {{cyan:lynis}}:       Security auditing (weekly)" \
    "  {{cyan:needrestart}}: Auto-restart services after updates" \
    ""

  _wiz_feature_checkbox "Security:" 7 "WIZ_FEATURES_SECURITY" \
    "apparmor:INSTALL_APPARMOR" \
    "auditd:INSTALL_AUDITD" \
    "aide:INSTALL_AIDE" \
    "chkrootkit:INSTALL_CHKROOTKIT" \
    "lynis:INSTALL_LYNIS" \
    "needrestart:INSTALL_NEEDRESTART"
}

# Features - Monitoring

# Edits monitoring feature toggles via multi-select checkbox.
# Options: vnstat, netdata, promtail.
# Updates corresponding INSTALL_* globals.
_edit_features_monitoring() {
  _wiz_start_edit

  _wiz_description \
    "  Monitoring features (use Space to toggle):" \
    "" \
    "  {{cyan:vnstat}}:   Network traffic monitoring" \
    "  {{cyan:netdata}}:  Real-time monitoring (port 19999)" \
    "  {{cyan:promtail}}: Log collector for Loki" \
    ""

  _wiz_feature_checkbox "Monitoring:" 4 "WIZ_FEATURES_MONITORING" \
    "vnstat:INSTALL_VNSTAT" \
    "netdata:INSTALL_NETDATA" \
    "promtail:INSTALL_PROMTAIL"
}

# Features - Tools

# Edits tools feature toggles via multi-select checkbox.
# Options: yazi (file manager), nvim (editor), ringbuffer (network tuning).
# Updates corresponding INSTALL_* globals.
_edit_features_tools() {
  _wiz_start_edit

  _wiz_description \
    "  Tools (use Space to toggle):" \
    "" \
    "  {{cyan:yazi}}:       Terminal file manager (Catppuccin theme)" \
    "  {{cyan:nvim}}:       Neovim as default editor" \
    "  {{cyan:ringbuffer}}: Network ring buffer tuning" \
    ""

  _wiz_feature_checkbox "Tools:" 4 "WIZ_FEATURES_TOOLS" \
    "yazi:INSTALL_YAZI" \
    "nvim:INSTALL_NVIM" \
    "ringbuffer:INSTALL_RINGBUFFER"
}
