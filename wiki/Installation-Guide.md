# Installation Guide

Complete guide to installing Proxmox VE on Hetzner dedicated servers.

## Prerequisites

- Hetzner dedicated server (AX, EX, or SX series)
- Access to Hetzner Robot Manager
- SSH client on your local machine

## Step 1: Prepare Rescue Mode

1. Log in to the [Hetzner Robot Manager](https://robot.hetzner.com/)
2. Select your server
3. Navigate to the **Rescue** tab and configure:
   - Operating system: **Linux**
   - Architecture: **64 bit**
   - Public key: *optional but recommended*
4. Click **Activate rescue system**
5. Go to the **Reset** tab
6. Check: **Execute an automatic hardware reset**
7. Click **Send**
8. Wait 2-3 minutes for the server to boot into rescue mode
9. Connect via SSH to the rescue system:
   ```bash
   ssh root@YOUR-SERVER-IP
   ```

## Step 2: Run Installation Script

Execute this command in the rescue system terminal:

```bash
bash <(curl -sSL https://qoxi-cloud.github.io/proxmox-hetzner/pve-install.sh)
```

The interactive installer will guide you through:
- Hostname configuration
- Root password setup
- SSH key configuration
- Network bridge mode selection
- ZFS RAID configuration
- Optional Tailscale installation

## Step 3: Wait for Installation

The script will:
1. Download the latest Proxmox VE ISO
2. Create an auto-installation configuration
3. Install Proxmox VE using QEMU
4. Configure networking and security
5. Apply system optimizations
6. Reboot into the installed system

Total installation time: approximately 15-25 minutes depending on server hardware.

## Step 4: Access Proxmox

After the server reboots:

1. Open your browser and navigate to: `https://YOUR-SERVER-IP:8006`
2. Accept the self-signed certificate warning
3. Log in with:
   - **Username:** `root`
   - **Password:** the password you set during installation

## Troubleshooting

### Installation hangs at a specific step

Check the log file for detailed output:
```bash
cat /tmp/pve-install.log
```

### Cannot connect after reboot

- Wait 2-3 minutes for all services to start
- Verify the server has rebooted (check Hetzner Robot console)
- Try connecting via SSH first: `ssh root@YOUR-SERVER-IP`

### Web interface not accessible

- Ensure port 8006 is not blocked by your firewall
- Try accessing via IP instead of hostname
- Check if Proxmox services are running: `systemctl status pveproxy`

---

**Next:** [Configuration Reference](Configuration-Reference) | [Network Modes](Network-Modes)
