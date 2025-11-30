#!/bin/bash
# Remove Proxmox subscription notice from Web UI
# Only for non-enterprise installations

PROXMOX_LIB="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

if [ -f "$PROXMOX_LIB" ]; then
    sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$PROXMOX_LIB"
    systemctl restart pveproxy.service
fi
