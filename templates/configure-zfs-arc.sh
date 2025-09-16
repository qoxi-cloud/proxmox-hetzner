#!/bin/bash
# Configure ZFS ARC memory limits based on total system RAM
# This script is executed on the Proxmox host during installation

set -e

TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))

# Set ARC limits based on RAM size
# - 128GB+: 16GB min, 64GB max
# - 64GB+:  8GB min, 32GB max
# - 32GB+:  4GB min, 16GB max
# - <32GB:  1GB min, 50% of RAM max

if [ "$TOTAL_RAM_GB" -ge 128 ]; then
    ARC_MIN=$((16 * 1024 * 1024 * 1024))
    ARC_MAX=$((64 * 1024 * 1024 * 1024))
elif [ "$TOTAL_RAM_GB" -ge 64 ]; then
    ARC_MIN=$((8 * 1024 * 1024 * 1024))
    ARC_MAX=$((32 * 1024 * 1024 * 1024))
elif [ "$TOTAL_RAM_GB" -ge 32 ]; then
    ARC_MIN=$((4 * 1024 * 1024 * 1024))
    ARC_MAX=$((16 * 1024 * 1024 * 1024))
else
    ARC_MIN=$((1 * 1024 * 1024 * 1024))
    ARC_MAX=$((TOTAL_RAM_KB * 1024 / 2))
fi

mkdir -p /etc/modprobe.d
echo "options zfs zfs_arc_min=$ARC_MIN" > /etc/modprobe.d/zfs.conf
echo "options zfs zfs_arc_max=$ARC_MAX" >> /etc/modprobe.d/zfs.conf
