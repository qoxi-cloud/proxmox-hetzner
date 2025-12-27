# PBS Support Implementation Plan

## Overview

Add Proxmox Backup Server (PBS) support to the installer alongside existing PVE functionality. User selects product type (PVE/PBS) in wizard, installer adapts accordingly.

## Core Changes

### 1. Product Selection Variable

**File: `scripts/00-init.sh`**
```bash
# Add new global variable
PRODUCT_TYPE="pve"  # Default, can be: pve, pbs
```

### 2. ISO Management

**File: `scripts/21-system-check.sh`**

Add PBS ISO detection:
```bash
# Current: PVE_ISO_*, PVE_CHECKSUM_*
# Add: PBS_ISO_*, PBS_CHECKSUM_*

_fetch_pbs_iso_info() {
  # Parse https://enterprise.proxmox.com/iso/ for PBS versions
  # Similar to _fetch_pve_iso_info but for PBS
}

# Conditional ISO selection based on PRODUCT_TYPE
_select_iso_based_on_product() {
  if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
    SELECTED_ISO="$PBS_ISO_URL"
    SELECTED_CHECKSUM="$PBS_CHECKSUM"
  else
    SELECTED_ISO="$PVE_ISO_URL"
    SELECTED_CHECKSUM="$PVE_CHECKSUM"
  fi
}
```

### 3. Wizard Integration

**File: `scripts/32-wizard-basic.sh`**

Add new editor function:
```bash
_edit_product_type() {
  local header="Product Type"
  local current="$PRODUCT_TYPE"

  echo -e "${CLR_CYAN}Select Proxmox Product:${CLR_RESET}"
  echo "  ${CLR_DIM}PVE: Virtual Environment (hypervisor for VMs/containers)${CLR_RESET}"
  echo "  ${CLR_DIM}PBS: Backup Server (dedicated backup solution)${CLR_RESET}"
  echo

  local choice
  choice=$(gum choose --header="$header" \
    "pve" \
    "pbs")

  [[ -n "$choice" ]] && PRODUCT_TYPE="$choice"
}
```

**File: `scripts/30-wizard-core.sh`**

Add product_type to config array:
```bash
CONFIG_ITEMS=(
  "product_type:Product:$PRODUCT_TYPE"
  "hostname:Hostname:$HOSTNAME"
  # ... rest
)
```

Conditional config items based on product:
```bash
_get_config_items() {
  local items=()
  items+=("product_type:Product:$PRODUCT_TYPE")
  items+=("hostname:Hostname:$HOSTNAME")
  # ... basic items

  if [[ "$PRODUCT_TYPE" == "pve" ]]; then
    # PVE-specific items
    items+=("network_mode:Network Mode:$NETWORK_MODE")
    items+=("zfs_mode:ZFS Mode:$ZFS_RAID_MODE")
    items+=("private_subnet:Private Subnet:$PRIVATE_SUBNET")
  fi

  # PBS doesn't need network bridges, private subnets, etc.

  # Common items for both
  items+=("ssh_key:SSH Key:...")
  items+=("ssl_type:SSL:$SSL_TYPE")
  # ...
}
```

### 4. Network Configuration

**File: `scripts/34-wizard-network.sh`**

Skip bridge configuration for PBS:
```bash
# Wrap bridge-related editors in condition
if [[ "$PRODUCT_TYPE" == "pve" ]]; then
  _edit_bridge_mode() { ... }
  _edit_private_subnet() { ... }
fi
```

**New Template: `templates/interfaces.pbs.tmpl`**
```bash
# Simple interface config for PBS (no bridges)
auto lo
iface lo inet loopback

auto {{INTERFACE}}
iface {{INTERFACE}} inet static
    address {{MAIN_IPV4}}
    netmask {{NETMASK}}
    gateway {{GATEWAY}}
{{#if IPV6_ENABLED}}
iface {{INTERFACE}} inet6 static
    address {{MAIN_IPV6}}
    netmask 64
    gateway {{IPV6_GATEWAY}}
{{/if}}
```

### 5. Repository Configuration

**File: `scripts/33-wizard-proxmox.sh`**

Update repository selection:
```bash
_edit_repository() {
  local repos
  if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
    repos=("pbs-no-subscription" "pbs-enterprise" "pbs-test")
  else
    repos=("no-subscription" "enterprise" "test")
  fi

  local choice
  choice=$(gum choose --header="Repository" "${repos[@]}")
  [[ -n "$choice" ]] && PVE_REPO_TYPE="$choice"
}
```

**File: `scripts/50-configure-base.sh`**

Update repository URLs:
```bash
configure_repositories() {
  if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
    case "$PVE_REPO_TYPE" in
      pbs-no-subscription)
        echo "deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" > /etc/apt/sources.list.d/pbs.list
        ;;
      pbs-enterprise)
        echo "deb https://enterprise.proxmox.com/debian/pbs bookworm pbs-enterprise" > /etc/apt/sources.list.d/pbs-enterprise.list
        ;;
      pbs-test)
        echo "deb http://download.proxmox.com/debian/pbs bookworm pbstest" > /etc/apt/sources.list.d/pbs-test.list
        ;;
    esac
  else
    # Current PVE logic
  fi
}
```

### 6. Answer Template

**New File: `templates/answer.toml.pbs.tmpl`**
```toml
[global]
keyboard = "{{KEYBOARD_LAYOUT}}"
country = "{{COUNTRY_CODE}}"
fqdn = "{{HOSTNAME}}.{{DOMAIN}}"
mailto = "{{EMAIL}}"
timezone = "{{TIMEZONE}}"
root_password = "{{NEW_ROOT_PASSWORD}}"
root_ssh_keys = """{{SSH_KEY}}"""

[network]
source = "from-iso"

[disk-setup]
filesystem = "zfs"
zfs.raid = "{{ZFS_RAID}}"
disk-list = [{{DRIVE_IDS}}]
# PBS has simpler disk setup, no ZFS tuning needed
```

### 7. Post-Install Scripts Conditional Logic

**File: `scripts/50-configure-base.sh`**

Skip PVE-specific packages:
```bash
install_base_packages() {
  local packages="sudo curl wget vim git htop"

  if [[ "$PRODUCT_TYPE" == "pve" ]]; then
    packages+=" ifupdown2"  # PVE needs this for network management
  fi

  apt-get install -y $packages
}
```

**File: `scripts/52-configure-fail2ban.sh`**

PBS-specific jail configuration:
```bash
configure_fail2ban_jails() {
  if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
    # PBS uses different log paths
    cat > /etc/fail2ban/jail.d/proxmox.local <<EOF
[proxmox]
enabled = true
port = https,http,8007
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
bantime = 1h
EOF
  else
    # Current PVE logic
  fi
}
```

### 8. Features Compatibility

**File: `scripts/36-wizard-services.sh`**

Some features might not apply to PBS:
```bash
_edit_features() {
  local available_features=()

  # Common features
  available_features+=("yazi:File Manager")
  available_features+=("nvim:Neovim Editor")

  # PVE-only features (if any)
  if [[ "$PRODUCT_TYPE" == "pve" ]]; then
    # Example: VM-specific tools
    available_features+=("vm-tools:VM Management Tools")
  fi

  # PBS-only features (if any)
  if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
    available_features+=("backup-verify:Automated Backup Verification")
  fi

  # ... rest of implementation
}
```

## New Files Required

### 1. PBS Templates
- `templates/interfaces.pbs.tmpl` - Simple network config (no bridges)
- `templates/answer.toml.pbs.tmpl` - PBS installer automation

### 2. PBS-Specific Configuration (optional)
- `scripts/58-configure-pbs.sh` - PBS-specific post-install (if needed)
  - Datastore setup
  - Prune schedules
  - Verification jobs

## Template Selection Logic

**File: `scripts/42-templates.sh`**

Select template based on product:
```bash
generate_answer_toml() {
  local template
  if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
    template="templates/answer.toml.pbs.tmpl"
  else
    template="templates/answer.toml.tmpl"
  fi

  deploy_template "$template" "/tmp/answer.toml" \
    HOSTNAME DOMAIN EMAIL TIMEZONE \
    NEW_ROOT_PASSWORD SSH_KEY \
    KEYBOARD_LAYOUT COUNTRY_CODE \
    ZFS_RAID_MODE DRIVE_IDS
}

generate_network_config() {
  local template
  if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
    template="templates/interfaces.pbs.tmpl"
  else
    # Unified template with bridge mode post-processing
    template="templates/interfaces.tmpl"
  fi

  deploy_template "$template" "/target/etc/network/interfaces" \
    INTERFACE MAIN_IPV4 NETMASK GATEWAY \
    MAIN_IPV6 IPV6_GATEWAY PRIVATE_SUBNET

  # Apply bridge mode sections (removes inapplicable sections)
  postprocess_interfaces_bridge_mode "/target/etc/network/interfaces"
}
```

## Validation Updates

**File: `scripts/20-validation.sh`**

Add product type validation:
```bash
validate_product_type() {
  local product="$1"
  [[ "$product" =~ ^(pve|pbs)$ ]] || return 1
  return 0
}
```

## UI/UX Changes

### Wizard Display

**File: `scripts/31-wizard-ui.sh`**

Update labels based on product:
```bash
_get_field_label() {
  local field="$1"

  case "$field" in
    product_type) echo "Product" ;;
    iso_version)
      if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
        echo "PBS Version"
      else
        echo "ISO Version"
      fi
      ;;
    repository)
      if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
        echo "PBS Repo"
      else
        echo "PVE Repo"
      fi
      ;;
    # ... rest
  esac
}
```

### Banner Updates

**File: `scripts/03-banner.sh`**

Show product type in banner:
```bash
show_banner() {
  if [[ "$PRODUCT_TYPE" == "pbs" ]]; then
    cat << 'EOF'
╔═══════════════════════════════════════╗
║   Proxmox Backup Server Installer    ║
║        for Hetzner Dedicated          ║
╚═══════════════════════════════════════╝
EOF
  else
    # Current PVE banner
  fi
}
```

## System Check Updates

**File: `scripts/21-system-check.sh`**

Fetch both PVE and PBS ISOs in background:
```bash
collect_system_info() {
  {
    # Detect hardware
    detect_drives
    detect_network

    # Fetch ISO info based on product (or fetch both?)
    if [[ -n "$PRODUCT_TYPE" && "$PRODUCT_TYPE" == "pbs" ]]; then
      _fetch_pbs_iso_info
    else
      _fetch_pve_iso_info
    fi

    # Export results
    export_system_info
  } >/dev/null 2>&1 &

  show_loading_animation $! "Collecting system information"
}
```

## CLI Arguments

**File: `scripts/01-cli.sh`**

Add `--product` flag:
```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --product)
      PRODUCT_TYPE="$2"
      shift 2
      ;;
    --iso-version)
      ISO_VERSION="$2"
      shift 2
      ;;
    # ... rest
  esac
done

# Validate product type
if [[ -n "$PRODUCT_TYPE" ]]; then
  validate_product_type "$PRODUCT_TYPE" || {
    print_error "Invalid product type: $PRODUCT_TYPE (must be 'pve' or 'pbs')"
    exit 1
  }
fi
```

## Testing Strategy

### 1. Unit Tests
- Validate product type selection
- Test template generation for both products
- Verify repository URL generation

### 2. Integration Tests
- Test full wizard flow for PBS
- Verify network config generation (no bridges for PBS)
- Test QEMU installation with PBS ISO

### 3. Manual Testing
- Install PBS on test server
- Verify all post-install scripts work
- Test SSL setup (Let's Encrypt + self-signed)
- Test Tailscale integration
- Verify SSH hardening

### 4. Compatibility Testing
- Ensure PVE installation still works (regression test)
- Test switching between PVE/PBS in wizard
- Verify all existing features work with PVE

## Rollout Plan

### Phase 1: Core Infrastructure (1-2 days)
1. Add `PRODUCT_TYPE` variable
2. Update wizard to show product selection
3. Add PBS ISO detection
4. Create PBS templates (answer.toml, interfaces)

### Phase 2: Conditional Logic (2-3 days)
1. Update wizard to hide PVE-only options for PBS
2. Add repository configuration for PBS
3. Update post-install scripts with conditionals
4. Test basic PBS installation

### Phase 3: Polish & Testing (1-2 days)
1. Update banners and UI text
2. Add CLI argument support
3. Comprehensive testing (PVE + PBS)
4. Documentation updates

### Phase 4: Optional Features (1 day)
1. PBS-specific features (datastore setup, etc.)
2. Advanced configuration options
3. Performance tuning

## Risks & Considerations

### Technical Risks
1. **PBS ISO format changes** - PBS automated installer might have different format than PVE
   - Mitigation: Test with latest PBS ISO, check Proxmox docs

2. **Network config differences** - PBS might require different network setup
   - Mitigation: Test network connectivity post-install

3. **Repository compatibility** - PBS repos structure might differ
   - Mitigation: Verify URLs against official Proxmox docs

### UX Risks
1. **Wizard complexity** - Too many conditional options might confuse users
   - Mitigation: Clear labels, contextual help text

2. **Breaking changes** - Existing users expect PVE by default
   - Mitigation: Keep PVE as default, make product selection optional

### Maintenance Risks
1. **Code duplication** - Maintaining two product paths
   - Mitigation: Maximize code reuse, extract common functions

2. **Testing overhead** - Need to test both products
   - Mitigation: Automated testing where possible

## Documentation Updates

### CLAUDE.md
- Update architecture section with product selection
- Document PBS-specific variables
- Add PBS templates to template list

### README.md (if exists)
- Mention PBS support
- Add PBS-specific examples
- Update screenshots/demos

### Inline Documentation
- Update function comments to mention PBS support
- Add product-specific notes where relevant

## Future Enhancements

### PBS-Specific Features
1. **Datastore Management**
   - Interactive datastore creation during install
   - Custom mount points
   - Quota configuration

2. **Backup Integration**
   - Pre-configure PVE → PBS backup jobs
   - Setup verification schedules
   - Configure retention policies

3. **HA Setup**
   - Support for PBS replication
   - Multi-PBS deployment

### Advanced Options
1. **Hybrid Mode** - Install both PVE and PBS on same server (not recommended, but possible)
2. **Migration Tools** - Scripts to convert PVE → PBS or vice versa
3. **Cluster Support** - Setup PBS in cluster mode

## Success Criteria

### Minimum Viable Product (MVP)
- [ ] PBS ISO detection works
- [ ] Wizard shows product selection
- [ ] PBS installs successfully via QEMU
- [ ] Network config correct (single interface, no bridges)
- [ ] Repository configuration works
- [ ] SSH hardening works
- [ ] SSL setup works (self-signed + Let's Encrypt)
- [ ] PVE installation still works (no regression)

### Full Feature Parity
- [ ] All post-install scripts work with PBS
- [ ] Tailscale integration works
- [ ] Fail2ban works with PBS logs
- [ ] Optional features (zsh, yazi, nvim) work
- [ ] CLI arguments work
- [ ] Live logs display works
- [ ] System check works for PBS

### Quality Standards
- [ ] Passes shellcheck
- [ ] No code duplication (DRY principle)
- [ ] Clear error messages
- [ ] Comprehensive logging
- [ ] Documentation updated
- [ ] Tested on real Hetzner server

## Estimated Effort

- **Development**: 4-6 days
- **Testing**: 2-3 days
- **Documentation**: 1 day
- **Total**: ~1-1.5 weeks

## Dependencies

- Access to Hetzner server for testing
- Latest PBS ISO from Proxmox
- Familiarity with PBS automated installer format
- Testing PBS repository access

## Open Questions

1. Does PBS support automated installation via answer.toml? (Need to verify)
2. Are there PBS-specific post-install requirements?
3. Should we support PBS clustering in initial implementation?
4. Do we need PBS-specific ZFS tuning?
5. Should Tailscale work differently with PBS?

## Notes

- Keep PVE as default for backwards compatibility
- Prioritize code reuse over feature-specific implementations
- Test thoroughly before merging to main
- Consider creating a separate branch for PBS development
- May need to adjust based on actual PBS installation behavior
