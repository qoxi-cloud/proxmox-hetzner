# Wizard Development Guide

Guide for extending and modifying the configuration wizard.

## Architecture Overview

```
100-wizard-core.sh   # Main loop, event handling
101-wizard-ui.sh     # UI rendering, gum wrappers
102-wizard-nav.sh    # Screen switching, navigation state
103-wizard-menu.sh   # Menu building, field mapping
104-wizard-display.sh# Display value formatters
110-121-wizard-*.sh  # Screen-specific editors
```

## Screen Structure

The wizard has 7 screens:

| Index | Name | Script | Fields |
|-------|------|--------|--------|
| 0 | Basic | 110-wizard-basic-locale.sh, 111-wizard-basic.sh | hostname, email, password, timezone, keyboard, country |
| 1 | Proxmox | 112-wizard-proxmox.sh | iso_version, repository |
| 2 | Network | 113-wizard-network-bridge.sh, 114-wizard-network-ipv6.sh | interface, bridge_mode, private_subnet, ipv6, mtu |
| 3 | Storage | 115-wizard-storage.sh | boot_disk, existing_pool, pool_disks, zfs_mode, zfs_arc |
| 4 | Services | 116-wizard-ssl.sh, 117-wizard-tailscale.sh, 121-wizard-features.sh | tailscale, ssl, firewall, security, monitoring, tools |
| 5 | Access | 118-wizard-access.sh, 119-wizard-ssh.sh | admin_username, admin_password, ssh_key |
| 6 | Disks | 120-wizard-disks.sh | disk detection and assignment |

## Adding a New Field

### 1. Add to Screen Menu

Edit the appropriate wizard editor file:

```bash
# In 121-wizard-features.sh, function _add_services_menu:
_add_services_menu() {
  # ... existing fields ...
  
  # Add new field
  local my_feature_display
  if [[ $INSTALL_MY_FEATURE == "yes" ]]; then
    my_feature_display="Enabled"
  else
    my_feature_display="Disabled"
  fi
  _add_field "my_feature" "My Feature" "$my_feature_display"
}
```

### 2. Create Editor Function

```bash
# In same file, add editor:
_edit_my_feature() {
  _wiz_start_edit  # Clear and show banner
  
  _wiz_label "My Feature Configuration"
  _wiz_blank_line
  _wiz_desc "Description of what this feature does"
  _wiz_blank_line
  
  local result
  result=$(_wiz_choose "Enable My Feature?" "yes" "no")
  
  if [[ -n $result ]]; then
    INSTALL_MY_FEATURE="$result"
  fi
}
```

### 3. Register in Core

Add case in `100-wizard-core.sh`:

```bash
# In _wizard_main(), add case for your field:
case "$field_name" in
  # ... existing cases ...
  my_feature) _edit_my_feature ;;
esac
```

### 4. Add Global Variable

In `003-init.sh`:

```bash
INSTALL_MY_FEATURE="${INSTALL_MY_FEATURE:-no}"
```

### 5. Add Validation (if required)

In `100-wizard-core.sh`, function `_validate_config`:

```bash
[[ -z $INSTALL_MY_FEATURE ]] && missing_fields+=("My Feature")
```

## UI Helper Functions

### Labels and Text

```bash
_wiz_label "Bold label text"
_wiz_desc "Regular description text"
_wiz_desc "{{cyan:highlighted}} text with color"
_wiz_blank_line
```

### Input Components

```bash
# Text input
result=$(_wiz_input "Enter hostname:" "$default_value" "placeholder")

# Single choice
result=$(_wiz_choose "Select option:" "option1" "option2" "option3")

# Multi-choice (checkboxes)
result=$(_wiz_checkbox "Select features:" "feat1" "feat2" "feat3")

# Filterable list
result=$(_wiz_filter "option1" "option2" "option3" ...)

# Yes/No confirmation
if _wiz_confirm "Are you sure?"; then
  echo "Confirmed"
fi
```

### Messages

```bash
_wiz_error "Error message"
_wiz_error --bold "Bold error"
_wiz_warn "Warning message"
_wiz_info "Info message"
```

### Screen Management

```bash
_wiz_start_edit     # Clear screen, show banner
_wiz_show_cursor    # Show terminal cursor
_wiz_hide_cursor    # Hide terminal cursor
_wiz_center "text"  # Center text on screen
```

### Footer for Input

```bash
_show_input_footer "input"     # [Enter] confirm  [Esc] cancel
_show_input_footer "filter"    # [↑↓] navigate  [Enter] select  [Esc] cancel
_show_input_footer "checkbox"  # [↑↓] navigate  [Space] toggle  [Enter] confirm
```

## Field Mapping

Fields are mapped via `_WIZ_FIELD_MAP` array:

```bash
_WIZ_FIELD_MAP[0]="hostname"
_WIZ_FIELD_MAP[1]="email"
# ...
```

When user presses Enter, the field name is used to call `_edit_<fieldname>`:

```bash
field_name="${_WIZ_FIELD_MAP[$selection]}"
"_edit_${field_name}"  # Dynamic function call
```

## Adding a New Screen

### 1. Create Screen Script

```bash
# scripts/122-wizard-myscreen.sh

# Screen menu builder
_add_myscreen_menu() {
  # Add fields for this screen
  _add_field "my_field1" "Field 1" "$MY_FIELD1"
  _add_field "my_field2" "Field 2" "$MY_FIELD2"
}

# Field editors
_edit_my_field1() {
  _wiz_start_edit
  _wiz_label "Configure Field 1"
  # ... input logic ...
}

_edit_my_field2() {
  _wiz_start_edit
  _wiz_label "Configure Field 2"
  # ... input logic ...
}
```

### 2. Register Screen

In `101-wizard-ui.sh`:

```bash
# Add to WIZ_SCREENS array:
WIZ_SCREENS=("Basic" "Proxmox" "Network" "Storage" "Services" "Access" "MyScreen")
```

### 3. Add Menu Builder Call

In `103-wizard-menu.sh`:

```bash
_wiz_build_screen_menu() {
  case "$WIZ_CURRENT_SCREEN" in
    # ... existing cases ...
    6) _add_myscreen_menu ;;
  esac
}
```

### 4. Source Script

In `900-main.sh`:

```bash
source "$SCRIPT_DIR/122-wizard-myscreen.sh"
```

## Navigation

### Key Handling

Navigation is handled in `100-wizard-core.sh`:

```bash
case "$WIZ_KEY" in
  up)    # Move selection up
  down)  # Move selection down
  left)  # Previous screen
  right) # Next screen
  enter) # Edit selected field
  start) # Start installation (S key)
  quit)  # Quit wizard (Q or Esc)
esac
```

### Key Reading

`_wiz_read_key` reads a single keypress and sets `WIZ_KEY`:

```bash
_wiz_read_key
case "$WIZ_KEY" in
  up|down|left|right|enter|start|quit|esc) ...
esac
```

## Gum Styling

Gum components are styled via command-line flags:

```bash
gum input \
  --prompt.foreground "#ff8700" \
  --cursor.foreground "#00d7ff" \
  --placeholder.foreground "#6c6c6c" \
  --width 40

gum choose \
  --cursor.foreground "#ff8700" \
  --selected.foreground "#00d7ff"

gum filter \
  --indicator.foreground "#ff8700" \
  --match.foreground "#00d7ff"
```

Color constants are defined in `000-colors.sh`:

```bash
HEX_ORANGE="#ff8700"
HEX_CYAN="#00d7ff"
HEX_GRAY="#6c6c6c"
```

## Inline Colors in Descriptions

Use `{{color:text}}` syntax in descriptions:

```bash
_wiz_desc "Press {{cyan:Enter}} to continue or {{orange:Esc}} to cancel"
```

Supported colors: `cyan`, `orange`, `green`, `red`, `yellow`, `gray`, `gold`

## Validation Pattern

### Field-Level Validation

Validate in the editor function:

```bash
_edit_hostname() {
  _wiz_start_edit
  _wiz_label "Hostname"
  
  local result
  result=$(_wiz_input "Enter hostname:" "$PVE_HOSTNAME")
  
  if [[ -n $result ]]; then
    if validate_hostname "$result"; then
      PVE_HOSTNAME="$result"
    else
      _wiz_error "Invalid hostname format"
      sleep 1
    fi
  fi
}
```

### Screen-Level Validation

Check all required fields before allowing installation:

```bash
_validate_config() {
  local missing_fields=()
  [[ -z $PVE_HOSTNAME ]] && missing_fields+=("Hostname")
  [[ -z $EMAIL ]] && missing_fields+=("Email")
  # ...
  
  if [[ ${#missing_fields[@]} -gt 0 ]]; then
    # Show error UI
    return 1
  fi
  return 0
}
```

## Best Practices

1. **Always call `_wiz_start_edit`** at the start of editors
2. **Handle empty results** - user may press Esc to cancel
3. **Validate before saving** - show error, don't save invalid values
4. **Use consistent styling** - follow existing field patterns
5. **Add to validation** - if field is required, check in `_validate_config`
6. **Test navigation** - verify arrow keys work correctly
7. **Test with gum** - run wizard to verify UI appearance

