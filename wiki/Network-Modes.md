# Network Bridge Modes

Understanding the different network configurations available for your Proxmox installation.

## Overview

The installer offers three network bridge modes, each suited for different use cases:

| Mode | Bridge(s) | Best For |
|------|-----------|----------|
| **Internal only** | `vmbr0` (NAT) | Isolated VMs, single public IP |
| **External only** | `vmbr0` (bridged) | Additional Hetzner IPs, direct VM access |
| **Both** | `vmbr0` (external) + `vmbr1` (NAT) | Maximum flexibility |

## Internal Only (NAT)

```
Internet
    │
    ▼
┌─────────────────────────────┐
│  Proxmox Host               │
│  Public IP: x.x.x.x         │
│                             │
│  ┌─────────────────────┐    │
│  │ vmbr0 (NAT bridge)  │    │
│  │ 10.0.0.1/24         │    │
│  └──────┬──────────────┘    │
│         │                   │
│    ┌────┴────┐              │
│    ▼         ▼              │
│  ┌───┐     ┌───┐            │
│  │VM1│     │VM2│            │
│  │.10│     │.20│            │
│  └───┘     └───┘            │
└─────────────────────────────┘
```

**Configuration:**
- `vmbr0` = NAT bridge with private subnet (default: `10.0.0.0/24`)
- VMs get private IPs (e.g., `10.0.0.10`, `10.0.0.20`)
- Host performs NAT for outbound traffic
- Use port forwarding for inbound access to VMs

**Use cases:**
- You have only one public IP from Hetzner
- VMs don't need direct internet access
- You want network isolation between VMs and internet

**Port forwarding example:**
```bash
# Forward port 80 to VM at 10.0.0.10
iptables -t nat -A PREROUTING -i enp0s31f6 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.10:80
```

## External Only (Bridged)

```
Internet
    │
    ▼
┌─────────────────────────────┐
│  Proxmox Host               │
│  Public IP: x.x.x.x         │
│                             │
│  ┌─────────────────────┐    │
│  │ vmbr0 (bridged)     │    │
│  │ bridge to enp0s31f6 │    │
│  └──────┬──────────────┘    │
│         │                   │
│    ┌────┴────┐              │
│    ▼         ▼              │
│  ┌───┐     ┌───┐            │
│  │VM1│     │VM2│            │
│  │pub│     │pub│            │
│  └───┘     └───┘            │
└─────────────────────────────┘
```

**Configuration:**
- `vmbr0` = bridged directly to physical NIC
- VMs can get public IPs from Hetzner
- Direct internet connectivity for VMs

**Use cases:**
- You have additional public IPs from Hetzner
- VMs need direct internet access with public IPs
- Running services that require direct connectivity

**Requirements:**
- Additional IP addresses or subnets from Hetzner
- Proper MAC address configuration for additional IPs

## Both (Internal + External)

```
Internet
    │
    ▼
┌───────────────────────────────────────┐
│  Proxmox Host                         │
│  Public IP: x.x.x.x                   │
│                                       │
│  ┌─────────────┐   ┌─────────────┐    │
│  │ vmbr0       │   │ vmbr1       │    │
│  │ (external)  │   │ (NAT)       │    │
│  │ bridged     │   │ 10.0.0.1/24 │    │
│  └──────┬──────┘   └──────┬──────┘    │
│         │                 │           │
│    ┌────┴────┐       ┌────┴────┐      │
│    ▼         ▼       ▼         ▼      │
│  ┌───┐     ┌───┐   ┌───┐     ┌───┐    │
│  │VM1│     │VM2│   │VM3│     │VM4│    │
│  │pub│     │pub│   │.30│     │.40│    │
│  └───┘     └───┘   └───┘     └───┘    │
└───────────────────────────────────────┘
```

**Configuration:**
- `vmbr0` = bridged to physical NIC (external access)
- `vmbr1` = NAT bridge with private subnet (internal network)
- VMs can be connected to either or both bridges

**Use cases:**
- Maximum flexibility for different VM requirements
- Some VMs need public IPs, others need isolation
- Complex network topologies

## Choosing the Right Mode

| Scenario | Recommended Mode |
|----------|------------------|
| Single public IP, isolated VMs | Internal only |
| Multiple public IPs from Hetzner | External only |
| Mixed requirements | Both |
| Testing/development | Internal only |
| Production with multiple services | Both |

## Private Subnet Configuration

When using NAT (internal or both modes), you can customize the private subnet:

| Default | Alternative Examples |
|---------|---------------------|
| `10.0.0.0/24` | `192.168.100.0/24`, `172.16.0.0/24` |

The host will use `.1` address (e.g., `10.0.0.1`) as the gateway for VMs.

## MTU Configuration (Jumbo Frames)

Private bridges (vmbr0 in internal mode, vmbr1 in both mode) are configured with MTU 9000 (jumbo frames) by default for improved VM-to-VM performance.

| Bridge | MTU | Purpose |
|--------|-----|---------|
| vmbr0 (internal) | 9000 | VM-to-VM traffic optimization |
| vmbr1 (both mode) | 9000 | VM-to-VM traffic optimization |
| vmbr0 (external) | 1500 | Standard MTU for external network |

**Benefits of Jumbo Frames:**

- Reduced CPU overhead for large data transfers
- Higher throughput for VM-to-VM communication
- Better performance for storage traffic (NFS, iSCSI)

**Note:** External bridges keep the default MTU (1500) since Hetzner's network may not support jumbo frames. VMs connected to internal bridges should also configure MTU 9000 for optimal performance.

## IPv6 Configuration

The installer supports full dual-stack (IPv4 + IPv6) networking. IPv6 is automatically detected from your network interface.

### IPv6 Modes

| Mode | Description |
|------|-------------|
| `auto` | Automatically detect IPv6 from interface (default) |
| `manual` | Manually specify IPv6 address and gateway |
| `disabled` | IPv4-only configuration |

### IPv6 Network Layout

```text
Internet (IPv4 + IPv6)
    │
    ▼
┌─────────────────────────────────────────┐
│  Proxmox Host                           │
│  IPv4: x.x.x.x/32                       │
│  IPv6: 2001:db8::1/128                  │
│  Gateway (IPv6): fe80::1                │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ vmbr0 (NAT bridge)              │    │
│  │ IPv4: 10.0.0.1/24               │    │
│  │ IPv6: 2001:db8:0:1::1/80        │    │
│  └──────────┬──────────────────────┘    │
│             │                           │
│        ┌────┴────┐                      │
│        ▼         ▼                      │
│      ┌───┐     ┌───┐                    │
│      │VM1│     │VM2│                    │
│      │.10│     │.20│                    │
│      └───┘     └───┘                    │
└─────────────────────────────────────────┘
```

### Hetzner IPv6 Gateway

Hetzner uses link-local gateway `fe80::1` for IPv6 routing. This is the default value configured by the installer.

### IPv6 for VMs

VMs on internal bridges can use IPv6 addresses from the allocated subnet. The installer calculates a /80 prefix for VM networks, allowing up to 65536 /96 subnets.

Example allocation:

- Host: `2001:db8:85a3::1234/64` (your Hetzner IPv6)
- VM bridge: `2001:db8:85a3:0:1::1/80`
- VM networks: `2001:db8:85a3:0:2::/96`, `2001:db8:85a3:0:3::/96`, etc.

### Disabling IPv6

If you prefer IPv4-only configuration:

```bash
export IPV6_MODE=disabled
bash pve-install.sh
```

---

**Next:** [Post-Installation](Post-Installation) | [Tailscale Setup](Tailscale-Setup)
